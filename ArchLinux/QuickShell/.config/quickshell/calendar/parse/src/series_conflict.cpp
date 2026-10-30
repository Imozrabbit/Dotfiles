#include "series_conflict.h"
#include "calendar_json.h"
#include "conflict_limits.h"
#include "helper.h"
#include "series_group.h"
#include <QCryptographicHash>
#include <QJsonDocument>
#include <map>

bool seriesConflictIdentity(const std::string &source, QString &uid, bool &tagged, QString &error) {
    const auto parsed = parseCalendar(source);
    if (!parsed.error.empty() || parsed.events.size() != 1) {
        error = "conflict snapshot must contain one valid event";
        return false;
    }
    bool ambiguous;
    uid = seriesSourceGroup(parsed.events.front(), tagged, ambiguous);
    if (ambiguous) {
        error = "conflict group identity is missing or ambiguous; member protected";
        return false;
    }
    return true;
}

namespace {
QJsonObject preview(const Event &event) {
    QJsonArray reminders;
    for (const auto minutes : event.reminders)
        reminders.append(QJsonObject{{"minutesBefore", minutes}});
    return QJsonObject{{"uid", QString::fromStdString(event.uid)}, {"title", QString::fromStdString(event.summary)}, {"description", QString::fromStdString(event.description)}, {"location", QString::fromStdString(event.location)}, {"start", QString::fromStdString(event.startTime)}, {"end", QString::fromStdString(event.endTime)}, {"allDay", event.allDay}, {"reminders", reminders}};
}
QString digest(const QJsonArray &value) {
    return QString::fromLatin1(QCryptographicHash::hash(QJsonDocument(value).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex());
}
}

bool buildSeriesConflict(const QString &uid, const QJsonArray &pairs, QJsonObject &result, QString &error) {
    if (uid.isEmpty() || pairs.isEmpty() || pairs.size() > 366) {
        error = "conflict group identity or member count is invalid";
        return false;
    }
    std::map<QString, QJsonObject> ordered;
    std::map<std::string, std::string> localSources, remoteSources;
    QJsonObject localPreview, remotePreview;
    qsizetype localBytes = 0, remoteBytes = 0;
    for (const auto &value : pairs) {
        const auto pair = value.toObject();
        if (!value.isObject() || pair.size() != 3 || !pair.value("uid").isString() || pair.value("uid").toString().isEmpty() || !pair.value("localIcs").isString() || !pair.value("remoteIcs").isString() || !ordered.emplace(pair.value("uid").toString(), pair).second) {
            error = "conflict group members are invalid or duplicated";
            return false;
        }
        const auto uidBytes = pair.value("uid").toString().toUtf8().size();
        localBytes += uidBytes + pair.value("localIcs").toString().toUtf8().size();
        remoteBytes += uidBytes + pair.value("remoteIcs").toString().toUtf8().size();
        if (localBytes > maxConflictSourceBytes || remoteBytes > maxConflictSourceBytes) {
            error = "conflict group snapshot exceeds limit";
            return false;
        }
    }
    QJsonArray members, localRaw, remoteRaw;
    for (auto &[memberUid, pair] : ordered) {
        QString localGroup, remoteGroup;
        bool localTagged = false, remoteTagged = false;
        const auto a = pair.value("localIcs").toString().toStdString();
        const auto b = pair.value("remoteIcs").toString().toStdString();
        if (!seriesConflictIdentity(a, localGroup, localTagged, error) || !seriesConflictIdentity(b, remoteGroup, remoteTagged, error) || (localGroup != uid && remoteGroup != uid)) {
            if (error.isEmpty())
                error = "conflict member does not belong to group";
            return false;
        }
        const auto local  = parseCalendar(a).events.front();
        const auto remote = parseCalendar(b).events.front();
        if (local.uid != memberUid.toStdString() || remote.uid != memberUid.toStdString()) {
            error = "conflict member identity differs between snapshots";
            return false;
        }
        if (localPreview.isEmpty())
            localPreview = preview(local);
        if (remotePreview.isEmpty())
            remotePreview = preview(remote);
        localSources.emplace(local.uid, a);
        remoteSources.emplace(remote.uid, b);
        pair["localRevision"]  = QString::fromStdString(eventRevision(local));
        pair["remoteRevision"] = QString::fromStdString(eventRevision(remote));
        members.append(pair);
        localRaw.append(QJsonObject{{"uid", memberUid}, {"ical", pair.value("localIcs")}});
        remoteRaw.append(QJsonObject{{"uid", memberUid}, {"ical", pair.value("remoteIcs")}});
    }
    QJsonObject local, remote;
    QString localError, remoteError;
    const bool localOk  = inspectSeriesSources(localSources, uid, local, localError);
    const bool remoteOk = inspectSeriesSources(remoteSources, uid, remote, remoteError);
    const bool ready    = localOk && remoteOk;
    result              = QJsonObject{{"kind", "group"}, {"version", 1}, {"uid", uid}, {"members", members}, {"choice", ""}, {"local", localOk ? local.value("master").toObject() : localPreview}, {"remote", remoteOk ? remote.value("master").toObject() : remotePreview}, {"localIcs", QString::fromUtf8(QJsonDocument(localRaw).toJson(QJsonDocument::Compact))}, {"remoteIcs", QString::fromUtf8(QJsonDocument(remoteRaw).toJson(QJsonDocument::Compact))}, {"revision", digest(members)}, {"ready", ready}, {"problem", ready ? QString{} : (!localOk ? "Local: " + localError : "Remote: " + remoteError)}};
    error.clear();
    return true;
}

bool validateSeriesConflict(const QJsonObject &record, QString &error) {
    if (!record.value("members").isArray() || !record.value("uid").isString() || !record.value("choice").isString() || !QStringList{"", "local", "remote"}.contains(record.value("choice").toString())) {
        error = "conflict group schema is invalid";
        return false;
    }
    QJsonArray pairs;
    for (const auto &value : record.value("members").toArray()) {
        auto pair = value.toObject();
        if (!value.isObject() || pair.size() != 5 || !pair.contains("localRevision") || !pair.contains("remoteRevision")) {
            error = "conflict group member schema is invalid";
            return false;
        }
        pair.remove("localRevision");
        pair.remove("remoteRevision");
        pairs.append(pair);
    }
    QJsonObject generated;
    if (!buildSeriesConflict(record.value("uid").toString(), pairs, generated, error))
        return false;
    generated["choice"] = record.value("choice");
    if (generated != record || (!generated.value("ready").toBool() && generated.value("choice") != "")) {
        error = "conflict group snapshot or revision changed; reopen conflict";
        return false;
    }
    return true;
}
