#include "caldav_remote.h"
#include "calendar_json.h"
#include "series_group.h"
#include <QJsonDocument>
#include <QSet>
#include <libical/ical.h>
#include <limits>
#include <map>
#include <memory>

namespace CalDavBackend {
namespace {
constexpr qint64 sideLimit = 64LL * 1024 * 1024, payloadLimit = 616LL * 1024 * 1024;
struct Side {
    QMap<QString, std::vector<Event>> groups;
    QMap<QString, QString> identities;
    QMap<QString, QJsonObject> previews;
    QMap<QString, QString> revisions;
    QMap<QString, QMap<QString, QString>> signatures;
};
QByteArray preservationSignature(const std::string &source) {
    using Calendar = std::unique_ptr<icalcomponent, decltype(&icalcomponent_free)>;
    Calendar calendar(icalparser_parse_string(source.c_str()), icalcomponent_free);
    if (!calendar || icalcomponent_isa(calendar.get()) != ICAL_VCALENDAR_COMPONENT || icalcomponent_count_errors(calendar.get())) return {};
    auto strip = [](icalcomponent *component) {
        // Sync bookkeeping is not an active dependency of the local result.
        for (const auto kind : {ICAL_PRODID_PROPERTY, ICAL_DTSTAMP_PROPERTY, ICAL_CREATED_PROPERTY, ICAL_LASTMODIFIED_PROPERTY, ICAL_SEQUENCE_PROPERTY})
            while (auto *property = icalcomponent_get_first_property(component, kind)) {
                icalcomponent_remove_property(component, property); icalproperty_free(property);
            }
    };
    strip(calendar.get());
    for (auto *event = icalcomponent_get_first_component(calendar.get(), ICAL_VEVENT_COMPONENT); event;
         event = icalcomponent_get_next_component(calendar.get(), ICAL_VEVENT_COMPONENT)) {
        strip(event);
        if (icalcomponent_count_properties(event, ICAL_DTSTART_PROPERTY) != 1) continue;
        auto *start = icalcomponent_get_first_property(event, ICAL_DTSTART_PROPERTY);
        // Match the reminder parser's explicit-UTC rule; never flatten civil/DST offsets.
        if (!icaltime_is_utc(icalproperty_get_dtstart(start)) || icalproperty_get_first_parameter(start, ICAL_TZID_PARAMETER)) continue;
        for (auto *alarm = icalcomponent_get_first_component(event, ICAL_VALARM_COMPONENT); alarm;
             alarm = icalcomponent_get_next_component(event, ICAL_VALARM_COMPONENT)) {
            if (icalcomponent_count_properties(alarm, ICAL_TRIGGER_PROPERTY) != 1) continue;
            auto *trigger = icalcomponent_get_first_property(alarm, ICAL_TRIGGER_PROPERTY);
            if (icalproperty_get_first_parameter(trigger, ICAL_ANY_PARAMETER)) continue;
            auto value = icalproperty_get_trigger(trigger);
            const qint64 seconds = (qint64(value.duration.weeks) * 7 + value.duration.days) * 86400
                + qint64(value.duration.hours) * 3600 + qint64(value.duration.minutes) * 60 + value.duration.seconds;
            if (!icaltime_is_null_time(value.time) || seconds < 0 || (!value.duration.is_neg && seconds != 0)
                || seconds % 60 != 0 || seconds / 60 > std::numeric_limits<int>::max()) continue;
            value.duration = {};
            value.duration.is_neg = seconds != 0;
            value.duration.minutes = static_cast<unsigned int>(seconds / 60);
            icalproperty_set_trigger(trigger, value);
        }
    }
    icalcomponent_normalize(calendar.get());
    char *text = icalcomponent_as_ical_string_r(calendar.get());
    const QByteArray result = text ? QByteArray(text) : QByteArray{};
    if (text) icalmemory_free_buffer(text);
    return result;
}
QJsonObject encoded(const QMap<QString, QByteArray> &sources) {
    QJsonObject result;
    for (auto it = sources.begin(); it != sources.end(); ++it) result[it.key()] = QString::fromLatin1(it.value().toBase64());
    return result;
}
bool decoded(const QJsonValue &value, QMap<QString, QByteArray> &sources, QString &error) {
    if (!value.isObject()) { error = "Preserved event snapshots are missing"; return false; }
    qint64 total = 0;
    const auto object = value.toObject();
    for (auto it = object.begin(); it != object.end(); ++it) {
        const auto raw = QByteArray::fromBase64Encoding(it.value().toString().toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
        total += raw.decoded.size();
        if (!it.value().isString() || !raw || raw.decoded.isEmpty() || raw.decoded.size() > 16 * 1024 * 1024 || total > sideLimit) {
            error = "Preserved event snapshot is invalid or too large"; return false;
        }
        sources[it.key()] = raw.decoded;
    }
    return true;
}
bool readSide(const QString &id, const QMap<QString, QByteArray> &sources, Side &side, QString &error) {
    qint64 total = 0;
    QSet<QString> seen;
    std::vector<Event> events;
    QMap<QString, std::map<std::string, std::string>> grouped;
    for (auto it = sources.begin(); it != sources.end(); ++it) {
        total += it.value().size();
        if (it.value().isEmpty() || it.value().size() > 16 * 1024 * 1024 || total > sideLimit || it.value().contains('\0')) {
            error = "Calendar source is empty, invalid or exceeds preservation limit"; return false;
        }
        const auto raw = it.value().toStdString();
        using Calendar = std::unique_ptr<icalcomponent, decltype(&icalcomponent_free)>;
        Calendar calendar(icalparser_parse_string(raw.c_str()), icalcomponent_free);
        if (!calendar || icalcomponent_isa(calendar.get()) != ICAL_VCALENDAR_COMPONENT || icalcomponent_count_errors(calendar.get())) {
            error = "Calendar source is malformed; no events may be discarded"; return false;
        }
        for (auto *child = icalcomponent_get_first_component(calendar.get(), ICAL_ANY_COMPONENT); child;
             child = icalcomponent_get_next_component(calendar.get(), ICAL_ANY_COMPONENT)) {
            const auto kind = icalcomponent_isa(child);
            if (kind != ICAL_VEVENT_COMPONENT && kind != ICAL_VTIMEZONE_COMPONENT) {
                error = "Calendar contains unsupported non-event content; nothing deleted"; return false;
            }
        }
        auto parsed = parseCalendar(raw);
        if (!parsed.error.empty() || parsed.events.size() != 1) {
            error = "Calendar resource must contain one complete event/series"; return false;
        }
        auto event = parsed.events.front();
        const auto uid = QString::fromStdString(event.uid);
        if (seen.contains(uid)) { error = "Calendar contains an ambiguous duplicate event identity"; return false; }
        seen.insert(uid);
        bool tagged = false, ambiguous = false;
        auto logical = seriesSourceGroup(event, tagged, ambiguous);
        if (ambiguous) { error = "Calendar series identity is ambiguous"; return false; }
        if (!tagged) logical = uid;
        else grouped[logical].emplace(event.uid, raw);
        side.identities[uid] = logical;
        const auto signature = preservationSignature(raw);
        if (signature.isEmpty()) { error = "Calendar content cannot be normalized safely; nothing deleted"; return false; }
        side.signatures[logical][uid] = SubscriptionBackend::revision(signature);
        if (!tagged && (event.ical.empty() || !event.recurrence.empty())) {
            auto modeled = event;
            modeled.ical.clear();
            if (event.startTime == event.endTime || signature != preservationSignature(serializeEvent(modeled))) {
                event.ical = raw; event.recurrence.clear(); event.timezone.clear(); event.readOnly = true;
            }
        } else if (!tagged) event.ical = raw; // Keep the complete opaque resource, including unreferenced zones.
        side.groups[logical].push_back(event);
        events.push_back(std::move(event));
    }
    for (auto it = grouped.begin(); it != grouped.end(); ++it) {
        QJsonObject verified;
        if (seen.contains(it.key()) || !inspectSeriesSources(it.value(), it.key(), verified, error)) {
            if (error.isEmpty()) error = "Calendar series collides with an ordinary event";
            return false;
        }
        QJsonObject modeled;
        if (!buildSeriesGroup(verified.value("master").toObject(), modeled, error)) return false;
        for (const auto &value : modeled.value("members").toArray()) {
            const auto member = value.toObject();
            const auto found = it.value().find(member.value("uid").toString().toStdString());
            const auto original = found == it.value().end() ? QByteArray{} : preservationSignature(found->second);
            const auto generated = preservationSignature(member.value("ical").toString().toStdString());
            if (original.isEmpty() || generated.isEmpty() || original != generated) {
                error = "Series contains opaque data that local logical recurrence cannot preserve; nothing deleted";
                return false;
            }
        }
    }
    const auto cache = QJsonDocument::fromJson(QByteArray::fromStdString(serializeSyncedCalendar(events, id.toStdString()))).object();
    if (!cache.value("warnings").toArray().isEmpty() || cache.value("events").toArray().size() != side.groups.size()) {
        error = "Calendar series cannot be preserved completely"; return false;
    }
    for (const auto &value : cache.value("events").toArray()) {
        auto preview = value.toObject();
        const auto uid = preview.value("sourceUid").toString();
        side.revisions[uid] = preview.value("revision").toString();
        preview.remove("ical"); preview.remove("seriesGroup"); preview.remove("sourceUid"); preview.remove("revision");
        side.previews[uid] = preview;
    }
    return true;
}
QJsonArray conflictsFor(const QString &id, const Side &local, const Side &remote) {
    QJsonArray conflicts;
    for (auto it = local.groups.begin(); it != local.groups.end(); ++it) {
        const auto uid = it.key();
        if (!remote.groups.contains(uid) || local.signatures.value(uid) == remote.signatures.value(uid)) continue;
        const auto pair = local.revisions.value(uid).toUtf8() + '\0' + remote.revisions.value(uid).toUtf8();
        const bool group = it.value().size() > 1 || remote.groups.value(uid).size() > 1
            || it.value().front().uid != uid.toStdString() || remote.groups.value(uid).front().uid != uid.toStdString();
        conflicts.append(QJsonObject{{"uid", uid}, {"kind", group ? "group" : "event"}, {"calendarId", id},
            {"local", local.previews.value(uid)}, {"remote", remote.previews.value(uid)}, {"revision", SubscriptionBackend::revision(pair)}, {"ready", true}});
    }
    return conflicts;
}
}

bool buildRemoteReview(const Record &target, const QMap<QString, QByteArray> &localSources,
                       const RemoteSnapshot &remote, QJsonObject &payload, QJsonArray &conflicts, QString &error) {
    payload = {}; conflicts = {}; error.clear();
    Side local, other;
    if (!SubscriptionBackend::validId(target.id) || !readSide(target.id, localSources, local, error)
        || !readSide(target.id, remote.resources, other, error)) {
        if (error.isEmpty()) error = "Invalid preservation calendar ID";
        return false;
    }
    for (auto it = local.identities.begin(); it != local.identities.end(); ++it)
        if (other.identities.contains(it.key()) && other.identities.value(it.key()) != it.value()) {
            error = "Event identity belongs to different logical series on each side; nothing deleted";
            return false;
        }
    conflicts = conflictsFor(target.id, local, other);
    payload = {{"version", 1}, {"id", target.id}, {"localSources", encoded(localSources)}, {"remoteSources", encoded(remote.resources)},
               {"homeHref", remote.homeHref}, {"fingerprint", remote.fingerprint}, {"conflicts", conflicts}};
    if (QJsonDocument(payload).toJson().size() > payloadLimit) { error = "Preservation review exceeds size limit"; return false; }
    return true;
}
bool projectRemoteSources(const QString &id, const QJsonObject &payload, const QJsonArray &choices, QMap<QString, QByteArray> &out, QString &error) {
    error.clear(); out = {};
    QMap<QString, QByteArray> localSources;
    RemoteSnapshot snapshot;
    snapshot.homeHref = payload.value("homeHref").toString(); snapshot.fingerprint = payload.value("fingerprint").toString();
    QJsonObject rebuilt;
    QJsonArray conflicts;
    Record target; target.id = id;
    if (!decoded(payload.value("localSources"), localSources, error) || !decoded(payload.value("remoteSources"), snapshot.resources, error)
        || !buildRemoteReview(target, localSources, snapshot, rebuilt, conflicts, error) || rebuilt != payload) {
        if (error.isEmpty()) error = "Preservation review metadata changed; reopen review";
        return false;
    }
    QMap<QString, QJsonObject> selected;
    for (const auto &value : choices) {
        const auto choice = value.toObject(); const auto uid = choice.value("uid").toString();
        if (!value.isObject() || choice.size() != 3 || !choice.value("revision").isString() || uid.isEmpty() || selected.contains(uid)
            || !QStringList{"local", "remote"}.contains(choice.value("choice").toString())) {
            error = "Invalid or duplicate preservation choice; choose local or remote"; return false;
        }
        selected[uid] = choice;
    }
    if (selected.size() != conflicts.size()) { error = "Choose a version for every preservation conflict"; return false; }
    for (const auto &value : conflicts) {
        const auto conflict = value.toObject(); const auto uid = conflict.value("uid").toString();
        if (selected.value(uid).value("revision") != conflict.value("revision")) { error = "Preservation choice is stale or extra"; return false; }
    }
    Side local, remote;
    if (!readSide(id, localSources, local, error) || !readSide(id, snapshot.resources, remote, error)) return false;
    auto append = [&](const QMap<QString, QByteArray> &sources, const Side &side, bool other) {
        for (auto it = sources.begin(); it != sources.end(); ++it) {
            const auto event = parseCalendar(it.value().toStdString()).events.front();
            const auto uid = QString::fromStdString(event.uid), logical = side.identities.value(uid);
            const bool useRemote = !local.groups.contains(logical) || selected.value(logical).value("choice") == "remote";
            if (other == useRemote) out[uid] = it.value();
        }
    };
    append(localSources, local, false);
    append(snapshot.resources, remote, true);
    return true;
}
bool projectRemoteReview(const QString &id, const QJsonObject &payload, const QJsonArray &choices, QJsonObject &out, QString &error) {
    out = {};
    QMap<QString, QByteArray> sources;
    Side chosen;
    if (!projectRemoteSources(id, payload, choices, sources, error) || !readSide(id, sources, chosen, error)) return false;
    std::vector<Event> events;
    for (const auto &members : chosen.groups) events.insert(events.end(), members.begin(), members.end());
    const auto cache = QJsonDocument::fromJson(QByteArray::fromStdString(serializeSyncedCalendar(events, id.toStdString()))).object();
    if (!cache.value("warnings").toArray().isEmpty() || cache.value("events").toArray().size() != chosen.groups.size()) {
        error = "Preserved union cannot retain every logical event; nothing deleted";
        return false;
    }
    return makeLocalDocument(id, cache.value("events").toArray(), out, error);
}
}
