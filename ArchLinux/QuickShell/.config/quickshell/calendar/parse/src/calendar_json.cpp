#include "calendar_json.h"
#include "series_group.h"
#include "recurrence.h"
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QRegularExpression>
#include <libical/ical.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <set>
#include <sstream>

namespace {

QJsonObject eventJson(const Event &event, const std::string &sourceId, bool synced) {
    QJsonArray reminders;
    for (const int minutes : event.reminders)
        reminders.append(QJsonObject{{QStringLiteral("minutesBefore"), minutes}});
    QJsonObject result{
        {QStringLiteral("uid"), QString::fromStdString(sourceId + ":" + event.uid)},
        {QStringLiteral("calendarId"), QString::fromStdString(sourceId)},
        {QStringLiteral("title"), QString::fromStdString(event.summary)},
        {QStringLiteral("description"), QString::fromStdString(event.description)},
        {QStringLiteral("location"), QString::fromStdString(event.location)},
        {QStringLiteral("start"), QString::fromStdString(event.startTime)},
        {QStringLiteral("end"), QString::fromStdString(event.endTime)},
        {QStringLiteral("allDay"), event.allDay},
        {QStringLiteral("reminders"), reminders}};
    if (synced) {
        result.insert(QStringLiteral("sourceUid"), QString::fromStdString(event.uid));
        result.insert(QStringLiteral("revision"), QString::fromStdString(eventRevision(event)));
    }
    if (synced && !event.recurrence.empty()) {
        result.insert(QStringLiteral("recurrence"), QJsonDocument::fromJson(QByteArray::fromStdString(event.recurrence)).object());
    } else if (!event.ical.empty()) {
        result.insert(QStringLiteral("ical"), QString::fromStdString(event.ical));
        result.insert(QStringLiteral("readOnly"), true);
    }
    if (synced && !event.seriesGroup.empty())
        result.insert(QStringLiteral("seriesGroup"), QJsonDocument::fromJson(QByteArray::fromStdString(event.seriesGroup)).object());
    if (event.readOnly)
        result.insert(QStringLiteral("readOnly"), true);
    if (synced && !event.allDay && !event.timezone.empty())
        result.insert(QStringLiteral("timezone"), QString::fromStdString(event.timezone));
    return result;
}

std::string jsonText(const QJsonObject &object) {
    return QJsonDocument(object).toJson(QJsonDocument::Indented).toStdString();
}

} // namespace

namespace {
bool cachedDocument(const std::string &path, const std::string &id, QJsonObject &root, std::string &error, bool allowMissing) {
    const int fd = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        if (allowMissing && errno == ENOENT) {
            root = {{"version", 2}, {"events", QJsonArray{}}, {"warnings", QJsonArray{}}}; return true;
        }
        error = "calendar cache unavailable; refresh calendar"; return false;
    }
    struct stat stamp{};
    if (fstat(fd, &stamp) != 0 || !S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid() || stamp.st_nlink != 1
        || stamp.st_size < 0 || stamp.st_size > 64 * 1024 * 1024) {
        close(fd); error = "calendar cache is unsafe or too large"; return false;
    }
    QFile file;
    if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) { close(fd); error = "calendar cache unavailable"; return false; }
    QJsonParseError parsed;
    const auto doc = QJsonDocument::fromJson(file.read(64 * 1024 * 1024 + 1), &parsed);
    root = doc.object();
    if (file.error() != QFileDevice::NoError || parsed.error != QJsonParseError::NoError || !doc.isObject()
        || root.size() != 3 || !QList<int>{2, 3, 4}.contains(root.value("version").toInt())
        || !root.value("events").isArray() || !root.value("warnings").isArray()) {
        error = "calendar cache invalid; refresh calendar"; return false;
    }
    std::set<QString> seen;
    for (const auto &value : root.value("events").toArray()) {
        const auto event = value.toObject();
        QString detail;
        const auto uid = event.value("sourceUid").toString();
        if (!value.isObject() || uid.isEmpty() || seen.count(uid) || event.value("calendarId") != QString::fromStdString(id)
            || event.value("uid") != QString::fromStdString(id) + ':' + uid || event.value("revision").toString().size() != 64
            || !event.value("title").isString() || !event.value("description").isString() || !event.value("location").isString()
            || !event.value("reminders").isArray() || !validateRecurrenceMaster(event, detail)) {
            error = "calendar cache event invalid; refresh calendar"; return false;
        }
        seen.insert(uid);
    }
    for (const auto &value : root.value("warnings").toArray()) if (!value.isString()) {
        error = "calendar cache warnings invalid"; return false;
    }
    return true;
}
} // namespace

bool validateSyncedCache(const std::string &output, const std::string &sourceId, std::string &error, bool allowMissing) {
    QJsonObject cache;
    return cachedDocument(output, sourceId, cache, error, allowMissing);
}

bool updateSyncedCache(const std::string &output, const std::string &sourceId,
                       const std::vector<std::string> &removedUids, std::vector<Event> replacements,
                       std::string &error, bool allowMissing) {
    QJsonObject cache;
    if (!cachedDocument(output, sourceId, cache, error, allowMissing)) return false;
    const std::set<std::string> removed(removedUids.begin(), removedUids.end());
    const auto changed = QJsonDocument::fromJson(QByteArray::fromStdString(serializeSyncedCalendar(std::move(replacements), sourceId))).object();
    std::vector<QJsonValue> events;
    std::set<QString> retained;
    for (const auto &value : cache.value("events").toArray()) {
        const auto uid = value.toObject().value("sourceUid").toString();
        if (!removed.count(uid.toStdString())) { events.push_back(value); retained.insert(uid); }
    }
    for (const auto &value : changed.value("events").toArray()) {
        const auto uid = value.toObject().value("sourceUid").toString();
        if (!retained.insert(uid).second) { error = "cache update collides with another event"; return false; }
        events.push_back(value);
    }
    std::sort(events.begin(), events.end(), [](const QJsonValue &a, const QJsonValue &b) {
        return a.toObject().value("uid").toString() < b.toObject().value("uid").toString();
    });
    QJsonArray array;
    for (const auto &event : events) array.append(event);
    cache["events"] = array;
    cache["version"] = std::max(cache.value("version").toInt(), changed.value("version").toInt());
    return writeAtomicallyFile(output, jsonText(cache), error);
}

bool refreshSyncedCacheEntry(const std::string &directory, const std::string &output,
                            const std::string &sourceId, const std::string &uid, std::string &error) {
    QJsonObject cache;
    if (uid.empty() || !cachedDocument(output, sourceId, cache, error, false)) return false;
    std::vector<std::string> affected{uid};
    for (const auto &value : cache.value("events").toArray()) {
        const auto event = value.toObject();
        if (event.value("sourceUid") != QString::fromStdString(uid)) continue;
        for (const auto &member : event.value("seriesGroup").toObject().value("members").toArray())
            affected.push_back(member.toObject().value("uid").toString().toStdString());
    }
    QJsonObject group;
    QString detail;
    std::vector<Event> replacements;
    if (inspectSeriesGroup(directory, QString::fromStdString(uid), group, detail)) {
        for (const auto &value : group.value("members").toArray()) {
            const auto member = value.toObject();
            affected.push_back(member.value("uid").toString().toStdString());
            auto parsed = parseCalendar(member.value("ical").toString().toStdString());
            if (!parsed.error.empty()) { error = parsed.error; return false; }
            replacements.insert(replacements.end(), parsed.events.begin(), parsed.events.end());
        }
    } else {
        if (detail != "group not found") { error = detail.toStdString(); return false; }
        std::string path;
        if (!syncedSourcePath(directory, uid, path, error)) return false;
        if (!path.empty()) {
            std::ifstream file(path, std::ios::binary);
            const std::string raw((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
            auto parsed = parseCalendar(raw);
            if (!file || !parsed.error.empty() || parsed.events.size() != 1 || parsed.events[0].uid != uid) {
                error = "changed event source is invalid"; return false;
            }
            replacements = std::move(parsed.events);
        } else for (const auto &member : affected) {
            std::string memberPath;
            if (!syncedSourcePath(directory, member, memberPath, error)) return false;
            if (member != uid && !memberPath.empty()) {
                error = "group member identity changed; refresh or resolve calendar"; return false;
            }
        }
    }
    return updateSyncedCache(output, sourceId, affected, std::move(replacements), error);
}

bool syncedSourcePath(const std::string &directory, const std::string &uid, std::string &path, std::string &error) {
    path.clear();
    std::error_code ec;
    std::filesystem::directory_iterator iterator(directory, ec), end;
    for (; !ec && iterator != end; iterator.increment(ec)) {
        if (iterator->path().extension() != ".ics") continue;
        const int fd = open(iterator->path().c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        struct stat stamp{};
        if (fd < 0 || fstat(fd, &stamp) != 0 || !S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid()
            || stamp.st_nlink != 1 || stamp.st_size < 0 || stamp.st_size > 32 * 1024 * 1024) {
            if (fd >= 0) close(fd);
            error = "event source is unavailable or unsafe"; return false;
        }
        QFile file;
        if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) { close(fd); error = "could not read event source"; return false; }
        auto header = QString::fromUtf8(file.read(32 * 1024 * 1024 + 1));
        if (file.error() != QFileDevice::NoError || header.size() > 32 * 1024 * 1024) { error = "event source exceeds limit"; return false; }
        header.replace(QRegularExpression("\\r?\\n[ \\t]"), "");
        const QRegularExpression property("^UID(?:;[^:\\r\\n]*)?:[^\\r\\n]*", QRegularExpression::CaseInsensitiveOption | QRegularExpression::MultilineOption);
        auto properties = property.globalMatch(header);
        bool candidate = false;
        while (properties.hasNext()) {
            const auto line = properties.next().captured().toUtf8();
            auto *value = icalproperty_new_from_string(line.constData());
            if (value) {
                const auto *sourceUid = icalproperty_get_uid(value);
                candidate = candidate || (sourceUid && uid == sourceUid);
                icalproperty_free(value);
            }
        }
        if (candidate) {
            if (!path.empty()) { error = "duplicate event UID"; return false; }
            path = iterator->path().string();
        }
    }
    if (ec) { error = "could not inspect event directory"; return false; }
    return true;
}

std::string eventRevision(const Event &event) {
    if (!event.groupRevision.empty())
        return event.groupRevision;
    std::ostringstream canonical;
    canonical << event.uid << '\n'
              << event.summary << '\n'
              << event.description << '\n'
              << event.location << '\n'
              << event.startTime << '\n'
              << event.endTime << '\n'
              << event.allDay << '\n';
    for (const int reminder : event.reminders)
        canonical << reminder << ',';
    if (!event.nominalOneDayAlarmRevision.empty())
        canonical << "\nnominal-one-day:" << event.nominalOneDayAlarmRevision;
    if (event.recurrence.empty() && !event.timezone.empty())
        canonical << '\n' << event.timezone;
    if (!event.ical.empty())
        canonical << '\n'
                  << event.ical;
    const std::string source = canonical.str();
    return QCryptographicHash::hash(QByteArray::fromStdString(source), QCryptographicHash::Sha256)
        .toHex()
        .toStdString();
}

std::string serializeCalendar(std::vector<Event> events, const std::string &sourceId) {
    std::sort(events.begin(), events.end(), [](const Event &left, const Event &right) {
        if (left.startTime != right.startTime)
            return left.startTime < right.startTime;
        if (left.endTime != right.endTime)
            return left.endTime < right.endTime;
        return left.uid < right.uid;
    });

    QJsonArray eventArray;
    for (const Event &event : events)
        eventArray.append(eventJson(event, sourceId, false));
    const bool extended = std::any_of(events.begin(), events.end(), [](const Event &event) { return !event.ical.empty(); });
    return jsonText({{QStringLiteral("version"), extended ? 2 : 1}, {QStringLiteral("events"), eventArray}});
}

std::string serializeSyncedCalendar(std::vector<Event> events, const std::string &sourceId,
                                    const std::vector<std::string> &warnings) {
    auto diagnostics = warnings;
    reconstructSeriesGroups(events, diagnostics);
    std::sort(events.begin(), events.end(), [](const Event &left, const Event &right) {
        return left.uid < right.uid;
    });

    QJsonArray eventArray;
    for (const Event &event : events)
        eventArray.append(eventJson(event, sourceId, true));
    QJsonArray warningArray;
    for (const std::string &warning : diagnostics)
        warningArray.append(QString::fromStdString(warning));
    const bool extended = std::any_of(events.begin(), events.end(), [](const Event &event) { return !event.ical.empty() || !event.recurrence.empty() || !event.timezone.empty(); });
    const bool grouped  = std::any_of(events.begin(), events.end(), [](const Event &event) { return !event.seriesGroup.empty(); });
    return jsonText({{QStringLiteral("version"), grouped ? 4 : extended ? 3
                                                                        : 2},
                     {QStringLiteral("events"), eventArray},
                     {QStringLiteral("warnings"), warningArray}});
}

bool rebuildSyncedCache(const std::string &directory, const std::string &output,
                        const std::string &sourceId, std::string &error, bool strict) {
    namespace fs = std::filesystem;
    std::error_code filesystemError;
    if (!fs::is_directory(directory, filesystemError)) {
        error = "calendar directory is unavailable";
        return false;
    }
    std::vector<Event> events;
    std::vector<std::string> warnings;
    std::set<std::string> uids;
    fs::directory_iterator entry(directory, filesystemError), end;
    for (; !filesystemError && entry != end; entry.increment(filesystemError)) {
        if (strict && entry->path().extension() == ".ics") {
            struct stat stamp{};
            if (lstat(entry->path().c_str(), &stamp) != 0 || !S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid()
                || stamp.st_nlink != 1 || stamp.st_size < 0 || stamp.st_size > 16 * 1024 * 1024) {
                error = "calendar source is unsafe or too large"; return false;
            }
        }
        if (!entry->is_regular_file(filesystemError) || entry->path().extension() != ".ics")
            continue;
        std::ifstream file(entry->path(), std::ios::binary);
        if (!file) {
            error = entry->path().string() + ": could not open file";
            return false;
        }
        const std::string source((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        const auto parsed = parseCalendar(source);
        if (strict && (!parsed.error.empty() || parsed.events.empty())) {
            error = "calendar conversion is incomplete; previous cache retained"; return false;
        }
        if (!parsed.error.empty()) {
            warnings.push_back(entry->path().filename().string() + ": malformed event omitted from cache");
            continue;
        }
        for (const auto &event : parsed.events) {
            if (!uids.insert(event.uid).second) {
                error = "duplicate UID: " + event.uid;
                return false;
            }
        }
        events.insert(events.end(), parsed.events.begin(), parsed.events.end());
    }
    if (filesystemError) {
        error = "could not scan calendar directory: " + filesystemError.message();
        return false;
    }
    const auto contents = serializeSyncedCalendar(std::move(events), sourceId, warnings);
    std::ifstream existing(output, std::ios::binary);
    if (existing && std::string((std::istreambuf_iterator<char>(existing)), std::istreambuf_iterator<char>()) == contents)
        return true;
    return writeAtomicallyFile(output, contents, error);
}
