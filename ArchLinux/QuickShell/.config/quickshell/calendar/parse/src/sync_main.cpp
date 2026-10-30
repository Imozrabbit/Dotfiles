#include "calendar_json.h"
#include "subscriptions.h"
#include "caldav.h"
#include "calendar_lock.h"
#include "conflict_limits.h"
#include "conflict_state.h"
#include "helper.h"
#include "recurrence.h"
#include "series_conflict.h"
#include "series_group.h"
#include "series_resolution.h"
#include "synced_recurrence.h"
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QTimeZone>
#include <algorithm>
#include <chrono>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <libical/ical.h>
#include <set>
#include <string>
#include <sys/file.h>
#include <sys/stat.h>
#include <system_error>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

namespace {

bool writeCache(const fs::path &path, const std::string &contents, std::string &error) {
    std::ifstream existing(path, std::ios::binary);
    if (existing) {
        const std::string previous((std::istreambuf_iterator<char>(existing)), std::istreambuf_iterator<char>());
        if (previous == contents)
            return true;
    }
    return writeAtomicallyFile(path.string(), contents, error);
}

bool rebuildUnlocked(const fs::path &directory, const fs::path &output,
                     const std::string &sourceId, std::string &error) {
    return rebuildSyncedCache(directory.string(), output.string(), sourceId, error);
}

bool rebuild(const fs::path &directory, const fs::path &output,
             const std::string &sourceId, std::string &error) {
    CalendarLock lock(directory, error);
    return lock.acquired() && rebuildUnlocked(directory, output, sourceId, error);
}

std::string uidFileName(const std::string &uid) {
    return QCryptographicHash::hash(QByteArray::fromStdString(uid), QCryptographicHash::Sha256)
               .toHex()
               .toStdString() +
           ".ics";
}

bool eventFromJson(const QJsonObject &input, Event &event, std::string &error) {
    return syncedEventFromJson(input, event, error);
}

bool mutate(const fs::path &directory, const fs::path &output,
            const std::string &sourceId, const std::string &operation,
            std::string &error, bool &sourceCommitted) {
    sourceCommitted = false;
    CalendarLock lock(directory, error);
    if (!lock.acquired())
        return false;
    QFile standardInput;
    if (!standardInput.open(stdin, QIODevice::ReadOnly)) {
        error = "could not read request JSON";
        return false;
    }
    const QByteArray input = standardInput.readLine();
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(input, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        error = "request JSON is invalid";
        return false;
    }

    const QJsonObject object = document.object();
    const std::string uid    = object.value("uid").toString().toStdString();
    if (uid.empty()) {
        error = "event UID is required";
        return false;
    }
    if (!validateSyncedCache(output.string(), sourceId, error, operation == "create")) return false;
    std::string existingPath;
    if (!syncedSourcePath(directory.string(), uid, existingPath, error)) return false;
    const fs::path eventPath = existingPath.empty() ? directory / uidFileName(uid) : fs::path(existingPath);
    std::error_code filesystemError;
    const bool hadExistingFile = fs::exists(eventPath, filesystemError);
    if (filesystemError) {
        error = "could not inspect event file: " + filesystemError.message();
        return false;
    }
    if ((operation == "update" || operation == "delete") && !hadExistingFile) {
        error = "event does not exist";
        return false;
    }
    std::string previousFile;
    if (hadExistingFile) {
        std::ifstream file(eventPath, std::ios::binary);
        previousFile.assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    }
    if ((operation == "update" || operation == "delete") && hadExistingFile) {
        const std::string expectedRevision = object.value("revision").toString().toStdString();
        const ParseResult current          = parseCalendar(previousFile);
        if (!current.error.empty() || current.events.size() != 1) {
            error = "could not read current event for stale check";
            return false;
        }
        if (expectedRevision.empty() || eventRevision(current.events[0]) != expectedRevision) {
            error = "event changed on another device; reopen it";
            return false;
        }
        if (!current.events[0].ical.empty() && current.events[0].recurrence.empty()) {
            error = "external recurrence is read-only";
            return false;
        }
    }
    if (operation == "delete") {
        if (!fs::remove(eventPath, filesystemError)) {
            error = filesystemError ? "could not remove event file: " + filesystemError.message()
                                    : "event does not exist";
            return false;
        }
        sourceCommitted = true;
    } else if (operation == "create" || operation == "update") {
        Event event;
        if (!eventFromJson(object, event, error))
            return false;
        if (operation == "create" && fs::exists(eventPath)) {
            error = "event already exists";
            return false;
        }
        if (operation == "update" && !fs::exists(eventPath)) {
            error = "event does not exist";
            return false;
        }
        const bool wrote = operation == "update"
                               ? writeEventFilePreserving(eventPath.string(), event, previousFile, error)
                               : writeEventFile(eventPath.string(), event, error);
        if (!wrote)
            return false;
        sourceCommitted = true;
    } else {
        error = "unknown mutation operation";
        return false;
    }
    std::vector<Event> changed;
    if (operation != "delete") {
        std::ifstream file(eventPath, std::ios::binary);
        const std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        auto parsed = parseCalendar(contents);
        if (!parsed.error.empty()) { error = "event saved but cache parse failed"; return false; }
        changed = std::move(parsed.events);
    }
    if (updateSyncedCache(output.string(), sourceId, {uid}, std::move(changed), error, operation == "create"))
        return true;
    error = "event committed but cache rebuild failed: " + error;
    return false;
}

} // namespace

QJsonObject eventJson(const Event &event) {
    QJsonArray reminders;
    for (const int minutes : event.reminders)
        reminders.append(QJsonObject{{"minutesBefore", minutes}});
    QJsonObject result{
        {"uid", QString::fromStdString(event.uid)},
        {"title", QString::fromStdString(event.summary)},
        {"description", QString::fromStdString(event.description)},
        {"location", QString::fromStdString(event.location)},
        {"start", QString::fromStdString(event.startTime)},
        {"end", QString::fromStdString(event.endTime)},
        {"allDay", event.allDay},
        {"reminders", reminders}};
    if (!event.recurrence.empty()) {
        result["recurrence"] = QJsonDocument::fromJson(QByteArray::fromStdString(event.recurrence)).object();
    } else if (!event.ical.empty()) {
        QStringList details{"External recurrence"};
        auto *calendar = icalparser_parse_string(event.ical.c_str());
        if (calendar) {
            for (auto *component      = icalcomponent_get_first_component(calendar, ICAL_VEVENT_COMPONENT);
                 component; component = icalcomponent_get_next_component(calendar, ICAL_VEVENT_COMPONENT)) {
                for (const auto kind : {ICAL_RRULE_PROPERTY, ICAL_RDATE_PROPERTY, ICAL_EXDATE_PROPERTY, ICAL_EXRULE_PROPERTY, ICAL_RECURRENCEID_PROPERTY}) {
                    for (auto *property     = icalcomponent_get_first_property(component, kind);
                         property; property = icalcomponent_get_next_property(component, kind))
                        details.append(QString::fromUtf8(icalproperty_as_ical_string(property)).trimmed());
                }
            }
            icalcomponent_free(calendar);
        }
        result["recurrenceSummary"] = details.join(" · ");
    }
    if (!event.allDay && !event.timezone.empty())
        result["timezone"] = QString::fromStdString(event.timezone);
    return result;
}

bool readConflictState(const fs::path &path, QJsonObject &state, std::string &error) {
    QFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::ReadOnly) && !file.exists()) {
        state = QJsonObject{{"version", 1}, {"conflicts", QJsonArray{}}};
        return true;
    }
    if (!file.isOpen()) {
        error = "conflict state is unavailable";
        return false;
    }
    const auto contents = file.read(maxConflictStateBytes + 1);
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(contents, &parseError);
    const auto object            = document.object();
    if (contents.size() > maxConflictStateBytes || parseError.error != QJsonParseError::NoError || !document.isObject() || object.size() != 2 || (object.value("version") != 1 && object.value("version") != 2) || !object.value("conflicts").isArray()) {
        error = "conflict state is invalid";
        return false;
    }
    std::set<QString> identities;
    for (const auto &value : object.value("conflicts").toArray()) {
        const auto record = value.toObject();
        QString detail;
        const bool group = record.value("kind") == "group";
        const bool valid = group ? object.value("version") == 2 && validateSeriesConflict(record, detail)
                                 : record.size() == 6 && record.value("local").isObject() && record.value("remote").isObject() && record.value("localIcs").isString() && record.value("remoteIcs").isString() && record.value("choice").isString() && QStringList{"", "local", "remote"}.contains(record.value("choice").toString());
        if (!value.isObject() || !record.value("uid").isString() || record.value("uid").toString().isEmpty() || !identities.insert(record.value("uid").toString()).second || !valid) {
            error = detail.isEmpty() ? "conflict state record is invalid" : detail.toStdString();
            return false;
        }
    }
    state = object;
    return true;
}

bool writeConflictState(const fs::path &path, const QJsonObject &state, std::string &error) {
    const auto text = QJsonDocument(state).toJson(QJsonDocument::Compact);
    if (text.size() >= maxConflictStateBytes) {
        error = "conflict state exceeds limit";
        return false;
    }
    return writeCache(path, text.toStdString() + "\n", error);
}

bool readSingleEvent(const fs::path &path, Event &event, std::string &raw, std::string &error) {
    QFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::ReadOnly)) {
        error = "conflict ICS file is unavailable";
        return false;
    }
    const auto contents = file.read(16 * 1024 * 1024 + 1);
    if (contents.size() > 16 * 1024 * 1024) {
        error = "conflict ICS file exceeds limit";
        return false;
    }
    raw                      = contents.toStdString();
    const ParseResult parsed = parseCalendar(raw);
    if (!parsed.error.empty() || parsed.events.size() != 1) {
        error = "conflict ICS file must contain one valid event";
        return false;
    }
    event = parsed.events.front();
    return true;
}

bool writeConflictBuffer(const fs::path &path, const std::string &expected,
                         const std::string &selected, std::string &error) {
    const int fd = open(path.c_str(), O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    struct stat info{};
    if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size > 16 * 1024 * 1024) {
        if (fd >= 0)
            close(fd);
        error = "conflict temporary buffer is unavailable or unsafe";
        return false;
    }
    QFile file;
    if (!file.open(fd, QIODevice::ReadWrite, QFileDevice::AutoCloseHandle)) {
        close(fd);
        return false;
    }
    if (file.read(16 * 1024 * 1024 + 1).toStdString() != expected || !file.seek(0)) {
        error = "conflict temporary buffer changed; reopen conflict";
        return false;
    }
    const auto bytes = QByteArray::fromStdString(selected);
    qint64 written   = 0;
    while (written < bytes.size()) {
        const auto count = file.write(bytes.constData() + written, bytes.size() - written);
        if (count <= 0) {
            error = "could not write conflict temporary buffer";
            return false;
        }
        written += count;
    }
    if (!file.flush() || ftruncate(fd, bytes.size()) != 0) {
        error = "could not finish conflict temporary buffer";
        return false;
    }
    return true;
}

static QString storedGroupOwner(const QJsonObject &state, const QString &uid) {
    for (const auto &value : state.value("conflicts").toArray()) {
        const auto record = value.toObject();
        if (record.value("kind") != "group")
            continue;
        if (record.value("uid") == uid)
            return record.value("uid").toString();
        for (const auto &member : record.value("members").toArray()) {
            if (member.toObject().value("uid") == uid)
                return record.value("uid").toString();
        }
    }
    return {};
}

bool captureConflict(const fs::path &statePath, const fs::path &localPath,
                     const fs::path &remotePath, std::string &error) {
    CalendarLock lock(statePath.parent_path(), error);
    if (!lock.acquired())
        return false;
    Event local;
    Event remote;
    std::string localRaw;
    std::string remoteRaw;
    if (!readSingleEvent(localPath, local, localRaw, error) || !readSingleEvent(remotePath, remote, remoteRaw, error))
        return false;
    if (local.uid.empty() || local.uid != remote.uid) {
        error = "conflict events have different UIDs";
        return false;
    }
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
    QJsonArray conflicts = state.value("conflicts").toArray();
    QString localGroup, remoteGroup, detail;
    bool localTagged = false, remoteTagged = false;
    if (!seriesConflictIdentity(localRaw, localGroup, localTagged, detail) || !seriesConflictIdentity(remoteRaw, remoteGroup, remoteTagged, detail)) {
        error = detail.toStdString();
        return false;
    }
    const auto owner = storedGroupOwner(state, QString::fromStdString(local.uid));
    if (owner == QString::fromStdString(local.uid)) {
        error = "ordinary conflict identity collides with grouped record";
        return false;
    }
    if (!localTagged && !remoteTagged && !owner.isEmpty()) {
        error = "stored group member lost grouping metadata; whole-group review required";
        return false;
    }
    if (localTagged || remoteTagged) {
        if (!localGroup.isEmpty() && !remoteGroup.isEmpty() && localGroup != remoteGroup) {
            error = "conflict group identities diverge; members protected";
            return false;
        }
        const auto groupUid = owner.isEmpty() ? (localTagged ? localGroup : remoteGroup) : owner;
        if ((!localGroup.isEmpty() && localGroup != groupUid) || (!remoteGroup.isEmpty() && remoteGroup != groupUid)) {
            error = "stored conflict group ownership diverges; members protected";
            return false;
        }
        QJsonArray remaining;
        std::map<QString, QJsonObject> pairs;
        QJsonObject previous;
        for (const auto &value : conflicts) {
            const auto record = value.toObject();
            if (record.value("kind") == "group" && record.value("uid") == groupUid) {
                previous = record;
                for (const auto &member : record.value("members").toArray()) {
                    auto pair = member.toObject();
                    pair.remove("localRevision");
                    pair.remove("remoteRevision");
                    pairs[pair.value("uid").toString()] = pair;
                }
                continue;
            }
            if (!record.contains("kind")) {
                QString a, b, ignored;
                bool taggedA = false, taggedB = false;
                if (seriesConflictIdentity(record.value("localIcs").toString().toStdString(), a, taggedA, ignored) && seriesConflictIdentity(record.value("remoteIcs").toString().toStdString(), b, taggedB, ignored) && (a == groupUid || b == groupUid || storedGroupOwner(state, record.value("uid").toString()) == groupUid)) {
                    pairs[record.value("uid").toString()] = QJsonObject{{"uid", record.value("uid")},
                                                                        {"localIcs", record.value("localIcs")},
                                                                        {"remoteIcs", record.value("remoteIcs")}};
                    continue;
                }
            }
            remaining.append(value);
        }
        pairs[QString::fromStdString(local.uid)] = QJsonObject{{"uid", QString::fromStdString(local.uid)},
                                                               {"localIcs", QString::fromStdString(localRaw)},
                                                               {"remoteIcs", QString::fromStdString(remoteRaw)}};
        QJsonArray members;
        for (const auto &[uid, pair] : pairs)
            members.append(pair);
        QJsonObject grouped;
        if (!buildSeriesConflict(groupUid, members, grouped, detail)) {
            error = detail.toStdString();
            return false;
        }
        if (grouped.value("revision") == previous.value("revision") && grouped.value("ready").toBool())
            grouped["choice"] = previous.value("choice");
        for (const auto &value : remaining) {
            if (value.toObject().value("uid") == groupUid) {
                error = "conflict group identity collides with unrelated record";
                return false;
            }
        }
        remaining.append(grouped);
        state["version"]   = 2;
        state["conflicts"] = remaining;
        return writeConflictState(statePath, state, error);
    }
    bool replaced = false;
    for (int index = 0; index < conflicts.size(); ++index) {
        if (conflicts[index].toObject().value("uid").toString() != QString::fromStdString(local.uid))
            continue;
        const QJsonObject existing = conflicts[index].toObject();
        if (existing.value("kind") == "group") {
            error = "ordinary conflict identity collides with grouped record";
            return false;
        }
        const bool unchanged = existing.value("localIcs").toString().toStdString() == localRaw && existing.value("remoteIcs").toString().toStdString() == remoteRaw;
        conflicts[index]     = QJsonObject{
            {"uid", QString::fromStdString(local.uid)},
            {"local", eventJson(local)},
            {"remote", eventJson(remote)},
            {"localIcs", QString::fromStdString(localRaw)},
            {"remoteIcs", QString::fromStdString(remoteRaw)},
            {"choice", unchanged ? existing.value("choice").toString() : QString{}}};
        replaced = true;
        break;
    }
    if (!replaced) {
        conflicts.append(QJsonObject{
            {"uid", QString::fromStdString(local.uid)},
            {"local", eventJson(local)},
            {"remote", eventJson(remote)},
            {"localIcs", QString::fromStdString(localRaw)},
            {"remoteIcs", QString::fromStdString(remoteRaw)},
            {"choice", ""}});
    }
    state["conflicts"] = conflicts;
    return writeConflictState(statePath, state, error);
}

bool chooseConflict(const fs::path &statePath, const std::string &uid,
                    const std::string &choice, std::string &error) {
    CalendarLock lock(statePath.parent_path(), error);
    if (!lock.acquired())
        return false;
    if (choice != "local" && choice != "remote") {
        error = "conflict choice must be local or remote";
        return false;
    }
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
    QJsonArray conflicts = state.value("conflicts").toArray();
    if (!storedGroupOwner(state, QString::fromStdString(uid)).isEmpty()) {
        error = "whole-group conflict resolution required";
        return false;
    }
    for (int index = 0; index < conflicts.size(); ++index) {
        QJsonObject conflict = conflicts[index].toObject();
        if (conflict.value("uid").toString().toStdString() != uid)
            continue;
        bool tagged = false;
        QString group, detail;
        if (conflict.value("kind") == "group" || !seriesConflictIdentity(conflict.value("localIcs").toString().toStdString(), group, tagged, detail) || tagged || !seriesConflictIdentity(conflict.value("remoteIcs").toString().toStdString(), group, tagged, detail) || tagged) {
            error = "whole-group conflict resolution required";
            return false;
        }
        conflict["choice"] = QString::fromStdString(choice);
        conflicts[index]   = conflict;
        state["conflicts"] = conflicts;
        return writeConflictState(statePath, state, error);
    }
    error = "conflict UID was not found";
    return false;
}

bool applyConflict(const fs::path &statePath, const fs::path &localPath,
                   const fs::path &remotePath, std::string &error) {
    CalendarLock lock(statePath.parent_path(), error);
    if (!lock.acquired())
        return false;
    Event local;
    Event remote;
    std::string localRaw;
    std::string remoteRaw;
    if (!readSingleEvent(localPath, local, localRaw, error) || !readSingleEvent(remotePath, remote, remoteRaw, error))
        return false;
    bool tagged = false;
    QString group, detail;
    if (!seriesConflictIdentity(localRaw, group, tagged, detail) || tagged || !seriesConflictIdentity(remoteRaw, group, tagged, detail) || tagged) {
        error = "whole-group conflict resolution required";
        return false;
    }
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
    if (!storedGroupOwner(state, QString::fromStdString(local.uid)).isEmpty() || !storedGroupOwner(state, QString::fromStdString(remote.uid)).isEmpty()) {
        error = "whole-group conflict resolution required";
        return false;
    }
    for (const QJsonValue &value : state.value("conflicts").toArray()) {
        const QJsonObject conflict = value.toObject();
        if (conflict.value("uid").toString().toStdString() != local.uid)
            continue;
        const std::string choice   = conflict.value("choice").toString().toStdString();
        const std::string selected = choice == "local"
                                         ? conflict.value("localIcs").toString().toStdString()
                                     : choice == "remote" ? conflict.value("remoteIcs").toString().toStdString()
                                                          : "";
        if (selected.empty()) {
            error = "conflict has no selected side";
            return false;
        }
        if (localRaw != conflict.value("localIcs").toString().toStdString() || remoteRaw != conflict.value("remoteIcs").toString().toStdString()) {
            error = "conflict versions changed; reopen conflict";
            return false;
        }
        const fs::path &losingPath = choice == "local" ? remotePath : localPath;
        return writeConflictBuffer(losingPath, choice == "local" ? remoteRaw : localRaw, selected, error);
    }
    error = "conflict UID was not found";
    return false;
}

bool clearConflict(const fs::path &statePath, const std::string &uid, std::string &error) {
    CalendarLock lock(statePath.parent_path(), error);
    if (!lock.acquired())
        return false;
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
    if (!storedGroupOwner(state, QString::fromStdString(uid)).isEmpty()) {
        error = "whole-group conflict completion required";
        return false;
    }
    QJsonArray remaining;
    for (const QJsonValue &value : state.value("conflicts").toArray()) {
        const auto record = value.toObject();
        if (record.value("uid").toString().toStdString() == uid) {
            bool tagged = false;
            QString group, detail;
            if (record.value("kind") == "group" || !seriesConflictIdentity(record.value("localIcs").toString().toStdString(), group, tagged, detail) || tagged || !seriesConflictIdentity(record.value("remoteIcs").toString().toStdString(), group, tagged, detail) || tagged) {
                error = "whole-group conflict completion required";
                return false;
            }
        }
        if (value.toObject().value("uid").toString().toStdString() != uid)
            remaining.append(value);
    }
    state["conflicts"] = remaining;
    return writeConflictState(statePath, state, error);
}

namespace {

bool migrate(const fs::path &input, const fs::path &directory,
             const fs::path &output, const std::string &sourceId,
             std::string &error) {
    std::ifstream file(input, std::ios::binary);
    if (!file) {
        error = "could not open source calendar";
        return false;
    }
    const std::string source{std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
    const QByteArray text = QByteArray::fromStdString(source);
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(text, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject() || document.object().value("version").toInt() != 1 || !document.object().value("events").isArray()) {
        error = "source calendar JSON is invalid";
        return false;
    }
    std::error_code filesystemError;
    if (fs::exists(directory, filesystemError) || fs::exists(output, filesystemError)) {
        error = "migration target already exists";
        return false;
    }
    const fs::path stagingDirectory = directory.string() + ".staging";
    const fs::path stagingOutput    = output.string() + ".staging";
    if (fs::exists(stagingDirectory, filesystemError) || fs::exists(stagingOutput, filesystemError)) {
        error = "migration staging target already exists";
        return false;
    }
    fs::create_directories(stagingDirectory, filesystemError);
    if (filesystemError) {
        error = "could not create migration directory: " + filesystemError.message();
        return false;
    }

    std::vector<Event> events;
    for (const QJsonValue &value : document.object().value("events").toArray()) {
        if (!value.isObject()) {
            error = "source calendar contains an invalid event";
            fs::remove_all(stagingDirectory, filesystemError);
            return false;
        }
        Event event;
        if (!eventFromJson(value.toObject(), event, error) || std::any_of(events.begin(), events.end(), [&event](const Event &existing) {
                return existing.uid == event.uid;
            })) {
            if (error.empty())
                error = "source calendar contains duplicate event UID";
            fs::remove_all(stagingDirectory, filesystemError);
            return false;
        }
        events.push_back(event);
        if (!writeEventFile((stagingDirectory / uidFileName(event.uid)).string(), event, error)) {
            fs::remove_all(stagingDirectory, filesystemError);
            return false;
        }
    }
    if (!rebuild(stagingDirectory, stagingOutput, sourceId, error)) {
        fs::remove_all(stagingDirectory, filesystemError);
        fs::remove(stagingOutput, filesystemError);
        return false;
    }
    fs::rename(stagingDirectory, directory, filesystemError);
    if (filesystemError) {
        error = "could not install migration directory: " + filesystemError.message();
        fs::remove_all(stagingDirectory, filesystemError);
        fs::remove(stagingOutput, filesystemError);
        return false;
    }
    fs::rename(stagingOutput, output, filesystemError);
    if (filesystemError) {
        error = "could not install migration cache: " + filesystemError.message();
        fs::remove_all(directory, filesystemError);
        return false;
    }
    return true;
}

bool verifyMigration(const fs::path &input, const fs::path &sourceDirectory,
                     const fs::path &sourceOutput, const std::string &sourceId,
                     std::string &error) {
    (void)sourceDirectory;
    (void)sourceOutput;
    const auto stamp                  = std::chrono::steady_clock::now().time_since_epoch().count();
    const fs::path temporaryDirectory = fs::temp_directory_path() / ("calendar-migration-check-" + std::to_string(stamp));
    const fs::path temporaryOutput    = temporaryDirectory.string() + ".json";
    const bool migrated               = migrate(input, temporaryDirectory, temporaryOutput, sourceId, error);
    if (!migrated) {
        std::error_code cleanupError;
        fs::remove_all(temporaryDirectory, cleanupError);
        fs::remove(temporaryOutput, cleanupError);
        return false;
    }

    std::ifstream sourceFile(input, std::ios::binary);
    std::ifstream outputFile(temporaryOutput, std::ios::binary);
    const std::string sourceText{std::istreambuf_iterator<char>(sourceFile), std::istreambuf_iterator<char>()};
    const std::string outputText{std::istreambuf_iterator<char>(outputFile), std::istreambuf_iterator<char>()};
    const QJsonDocument sourceDocument = QJsonDocument::fromJson(QByteArray::fromStdString(sourceText));
    const QJsonDocument outputDocument = QJsonDocument::fromJson(QByteArray::fromStdString(outputText));
    const QJsonArray sourceEvents      = sourceDocument.object().value("events").toArray();
    const QJsonArray outputEvents      = outputDocument.object().value("events").toArray();
    bool matches                       = sourceEvents.size() == outputEvents.size();
    for (const QJsonValue &sourceValue : sourceEvents) {
        const QJsonObject sourceEvent = sourceValue.toObject();
        const QString uid             = sourceEvent.value("uid").toString();
        const auto outputMatch        = std::find_if(outputEvents.begin(), outputEvents.end(),
                                                     [&uid](const QJsonValue &value) {
                                                  return value.toObject().value("sourceUid").toString() == uid;
                                                     });
        if (outputMatch == outputEvents.end()) {
            matches = false;
            break;
        }
        const QJsonObject outputEvent = outputMatch->toObject();
        for (const char *key : {"title", "description", "location", "start", "end", "allDay"}) {
            if (sourceEvent.value(QLatin1String(key)) != outputEvent.value(QLatin1String(key)))
                matches = false;
        }
        if (QJsonDocument(sourceEvent.value("reminders").toArray()).toJson(QJsonDocument::Compact) != QJsonDocument(outputEvent.value("reminders").toArray()).toJson(QJsonDocument::Compact))
            matches = false;
    }
    std::error_code cleanupError;
    fs::remove_all(temporaryDirectory, cleanupError);
    fs::remove(temporaryOutput, cleanupError);
    if (!matches) {
        error = "migration comparison failed";
        return false;
    }
    std::cout << "migration verified: " << sourceEvents.size() << " events\n";
    return true;
}

} // namespace

int main(int argc, char **argv) {
    const auto conversionGuard = [](const QString &id) {
        QString error;
        if (CalDavBackend::conversionAllowed(CalDavBackend::paths(), id, error)) return true;
        std::cerr << error.toStdString() << '\n'; return false;
    };
    const auto conversionStateGuard = [&](const QString &path) {
        const auto name = QFileInfo(path).fileName();
        if (!name.startsWith("conflicts-") || !name.endsWith(".json")) return true;
        const auto id = name.mid(10, name.size() - 15);
        const auto expected = QFileInfo(CalDavBackend::paths().state).path() + "/conflicts-" + id + ".json";
        return QDir::cleanPath(QFileInfo(path).absoluteFilePath()) != QDir::cleanPath(expected) || conversionGuard(id);
    };
    if (argc >= 2 && std::string(argv[1]) == "caldav") {
        QCoreApplication app(argc, argv);
        return CalDavBackend::run(app.arguments().mid(2));
    }
    if (argc == 6 && std::string(argv[1]) == "refresh-cache-entry") {
        if (!conversionGuard(QString::fromUtf8(argv[4]))) return 1;
        std::string error;
        CalendarLock lock(argv[2], error);
        if (lock.acquired() && refreshSyncedCacheEntry(argv[2], argv[3], argv[4], argv[5], error)) return 0;
        std::cerr << error << '\n';
        return 1;
    }
    QCoreApplication application(argc, argv);
    if (argc == 2 && (std::string(argv[1]) == "deployment-plan" || std::string(argv[1]) == "deployment-verify"))
        return SubscriptionBackend::deploymentPlan(std::string(argv[1]) == "deployment-verify");
    if (argc >= 2 && std::string(argv[1]) == "subscriptions") {
        QStringList arguments;
        for (int index = 2; index < argc; ++index)
            arguments.append(QString::fromUtf8(argv[index]));
        return SubscriptionBackend::run(arguments);
    }
    if (argc >= 2 && QStringList{"conflict-group-select", "group-review-begin", "group-callback", "group-prepare", "group-finish", "group-cancel"}.contains(QString::fromUtf8(argv[1]))) {
        QStringList arguments;
        for (int index = 2; index < argc; ++index)
            arguments.append(QString::fromUtf8(argv[index]));
        const auto operation = QString::fromUtf8(argv[1]);
        const bool source = QStringList{"group-prepare", "group-finish", "group-cancel"}.contains(operation);
        if ((source && arguments.size() >= 3 && !conversionGuard(arguments[2]))
            || (!source && !arguments.isEmpty() && !conversionStateGuard(arguments[0]))) return 1;
        std::string error;
        bool sourceCommitted = false;
        if (!runSeriesResolution(QString::fromUtf8(argv[1]), arguments, error, sourceCommitted)) {
            std::cerr << error << '\n';
            return sourceCommitted ? 2 : 1;
        }
        return 0;
    }
    if (argc >= 2 && std::string(argv[1]) == "verify-group-guard") {
        if (argc != 4)
            return 2;
        QFile input;
        if (!input.open(stdin, QIODevice::ReadOnly))
            return 1;
        const auto text = input.readLine(65537);
        QJsonParseError error;
        const auto document   = QJsonDocument::fromJson(text, &error);
        bool valid            = text.size() <= 65536 && error.error == QJsonParseError::NoError && document.isArray();
        const auto properties = document.array();
        valid                 = valid && properties.size() == 4;
        for (const auto &property : properties)
            valid = valid && property.isObject();
        const auto conditions  = properties.size() > 0 ? properties[0].toObject() : QJsonObject{};
        const auto environment = properties.size() > 1 ? properties[1].toObject() : QJsonObject{};
        const auto files       = properties.size() > 2 ? properties[2].toObject() : QJsonObject{};
        const auto unset       = properties.size() > 3 ? properties[3].toObject() : QJsonObject{};
        valid                  = valid && conditions.value("type") == "a(sasbttttuii)" && conditions.value("data").isArray() && environment.value("type") == "as" && environment.value("data").isArray() && files.value("type") == "a(sb)" && files.value("data").isArray() && files.value("data").toArray().isEmpty() && unset.value("type") == "as" && unset.value("data").isArray();
        const QJsonArray expected{"/bin/sh", QString::fromUtf8(argv[2]), "check-recovery"};
        bool found = false;
        for (const auto &value : conditions.value("data").toArray()) {
            const auto command = value.toArray();
            if (value.isArray() && command.size() == 10 && command[0] == "/bin/sh" && command[1] == expected && command[2].isBool() && !command[2].toBool())
                found = true;
        }
        int stateAssignments = 0;
        bool stateMatches    = false;
        for (const auto &value : environment.value("data").toArray()) {
            valid = valid && value.isString();
            if (value.toString().startsWith("XDG_STATE_HOME=")) {
                ++stateAssignments;
                stateMatches = value == "XDG_STATE_HOME=" + QString::fromUtf8(argv[3]);
            }
        }
        for (const auto &value : unset.value("data").toArray()) {
            valid = valid && value.isString() && value != "XDG_STATE_HOME" && !value.toString().startsWith("XDG_STATE_HOME=");
        }
        if (!valid || !found || stateAssignments != 1 || !stateMatches) {
            std::cerr << "pimsync requires matching group-recovery condition and XDG_STATE_HOME, no EnvironmentFile or state unsetting\n";
            return 1;
        }
        return 0;
    }
    if (argc >= 2 && std::string(argv[1]) == "check-group") {
        if (argc != 6)
            return 2;
        if (!conversionGuard(QString::fromUtf8(argv[4]))) return 1;
        QString error;
        if (!QStringList{"create", "update", "delete"}.contains(QString::fromUtf8(argv[5])) || !checkSeriesTarget(argv[2], argv[3], QString::fromUtf8(argv[4]), error)) {
            std::cerr << (error.isEmpty() ? "group operation is invalid" : error.toStdString()) << '\n';
            return 1;
        }
        return 0;
    }
    if (argc >= 2 && (std::string(argv[1]) == "mutate-group" || std::string(argv[1]) == "recover-group")) {
        const bool mutation = std::string(argv[1]) == "mutate-group";
        if (mutation ? (argc != 6 && argc != 7) : (argc != 5 && argc != 6)) {
            std::cerr << "Usage: calendar-sync-helper mutate-group directory cache source-id create|update|delete\n"
                      << "       calendar-sync-helper recover-group directory cache source-id\n";
            return 2;
        }
        if (!conversionGuard(QString::fromUtf8(argv[4]))) return 1;
        QString error;
        bool committedOrSafe = false;
        bool ok              = false;
        if (!mutation) {
            ok = recoverSeriesCache(argv[2], argv[3], QString::fromUtf8(argv[4]), error, committedOrSafe, argc == 6 ? QString::fromUtf8(argv[5]) : QString{});
        } else {
            QFile input;
            if (!input.open(stdin, QIODevice::ReadOnly)) {
                std::cerr << "Could not read group request\n";
                return 1;
            }
            const auto text = input.readLine(16 * 1024 * 1024 + 1);
            QJsonParseError parseError;
            const auto document = QJsonDocument::fromJson(text, &parseError);
            if (text.size() > 16 * 1024 * 1024 || parseError.error != QJsonParseError::NoError || !document.isObject()) {
                std::cerr << "Group request JSON is invalid\n";
                return 1;
            }
            const auto event     = document.object();
            if (argc == 7 && event.value("uid").toString() != QString::fromUtf8(argv[6])) {
                std::cerr << "Group request scope changed\n";
                return 1;
            }
            const auto operation = QString::fromUtf8(argv[5]);
            QJsonObject request{{"operation", operation}, {"sourceId", QString::fromUtf8(argv[4])}, {"revision", event.value("revision")}};
            if (operation == "delete")
                request["uid"] = event.value("uid");
            else
                request["event"] = event;
            ok = mutateSeriesGroup(argv[2], argv[3], request, error, committedOrSafe);
        }
        if (!ok) {
            std::cerr << error.toStdString() << '\n';
            return committedOrSafe ? 2 : 1;
        }
        return 0;
    }
    if (argc == 2 && std::string(argv[1]) == "system-timezone") {
        const auto zone = QTimeZone::systemTimeZone();
        if (!zone.isValid()) {
            std::cerr << "Could not resolve configured system timezone\n";
            return 1;
        }
        std::cout << QJsonDocument(QJsonObject{{"timezone", QString::fromUtf8(zone.id())}}).toJson(QJsonDocument::Compact).constData() << '\n';
        return 0;
    }
    if (argc == 2 && (std::string(argv[1]) == "normalize" || std::string(argv[1]) == "expand" || std::string(argv[1]) == "group-codec")) {
        QFile input;
        if (!input.open(stdin, QIODevice::ReadOnly)) {
            std::cerr << "Could not read recurrence request\n";
            return 1;
        }
        const QByteArray text = input.readLine(16 * 1024 * 1024 + 1);
        QJsonParseError parseError;
        const auto document = QJsonDocument::fromJson(text, &parseError);
        QJsonObject result;
        QString error;
        if (text.size() > 16 * 1024 * 1024 || parseError.error != QJsonParseError::NoError || !document.isObject() || !(std::string(argv[1]) == "group-codec" ? buildSeriesGroup(document.object(), result, error) : std::string(argv[1]) == "normalize" ? normalizeRecurrenceMaster(document.object(), result, error)
                                                                                                                                                                                                                                                         : expandCalendarRange(document.object(), result, error))) {
            std::cerr << (error.isEmpty() ? "Recurrence request JSON is invalid" : error.toStdString()) << '\n';
            return 1;
        }
        std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << '\n';
        return 0;
    }
    if ((argc < 2 || argc > 6) || (std::string(argv[1]) != "rebuild" && std::string(argv[1]) != "mutate" && std::string(argv[1]) != "migrate" && std::string(argv[1]) != "verify-migration" && std::string(argv[1]) != "conflict-capture" && std::string(argv[1]) != "conflict-select" && std::string(argv[1]) != "conflict-apply" && std::string(argv[1]) != "conflict-clear")) {
        std::cerr << "Usage: calendar-sync-helper rebuild [input-directory] [output-json] [source-id]\n"
                  << "       calendar-sync-helper mutate [input-directory] [output-json] [source-id] [create|update|delete]\n"
                  << "       calendar-sync-helper migrate [source-json] [input-directory] [output-json] [source-id]\n"
                  << "       calendar-sync-helper verify-migration [source-json] [input-directory] [output-json] [source-id]\n"
                  << "       calendar-sync-helper conflict-capture [state-json] [local-ics] [remote-ics]\n"
                  << "       calendar-sync-helper conflict-select [state-json] [uid] [local|remote]\n"
                  << "       calendar-sync-helper conflict-apply [state-json] [local-ics] [remote-ics]\n"
                  << "       calendar-sync-helper conflict-clear [state-json] [uid]\n";
        return 2;
    }
    const std::string command(argv[1]);
    const int expected = command == "conflict-clear"                                                      ? 4
                         : (command == "mutate" || command == "migrate" || command == "verify-migration") ? 6
                                                                                                          : 5;
    if (argc != expected) {
        std::cerr << "Command arguments are invalid\n";
        return 2;
    }
    if ((QStringList{"mutate", "rebuild"}.contains(QString::fromStdString(command)) && !conversionGuard(QString::fromUtf8(argv[4])))
        || (QString::fromStdString(command).startsWith("conflict-") && command != "conflict-capture" && !conversionStateGuard(QString::fromUtf8(argv[2])))) return 1;
    std::string error;
    bool sourceCommitted = false;
    const bool ok        = std::string(argv[1]) == "rebuild"
                               ? rebuild(argv[2], argv[3], argv[4], error)
                           : std::string(argv[1]) == "mutate"
                               ? mutate(argv[2], argv[3], argv[4], argv[5], error, sourceCommitted)
                           : std::string(argv[1]) == "migrate"
                               ? migrate(argv[2], argv[3], argv[4], argv[5], error)
                           : std::string(argv[1]) == "verify-migration"
                               ? verifyMigration(argv[2], argv[3], argv[4], argv[5], error)
                           : std::string(argv[1]) == "conflict-capture"
                               ? captureConflict(argv[2], argv[3], argv[4], error)
                           : std::string(argv[1]) == "conflict-select"
                               ? chooseConflict(argv[2], argv[3], argv[4], error)
                           : std::string(argv[1]) == "conflict-apply"
                               ? applyConflict(argv[2], argv[3], argv[4], error)
                               : clearConflict(argv[2], argv[3], error);
    if (!ok) {
        std::cerr << error << '\n';
        if (sourceCommitted)
            return 2;
        return 1;
    }
    return 0;
}
