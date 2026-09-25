#include "calendar_json.h"
#include "helper.h"
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDate>
#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <algorithm>
#include <chrono>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <set>
#include <string>
#include <sys/file.h>
#include <system_error>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

namespace {

class CalendarLock {
  public:
    explicit CalendarLock(const fs::path &directory, std::string &error) {
        const fs::path path = directory / ".calendar-sync.lock";
        descriptor          = open(path.c_str(), O_CREAT | O_RDWR, 0600);
        if (descriptor < 0 || flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
            if (descriptor >= 0)
                close(descriptor);
            descriptor = -1;
            error      = "calendar is busy";
        }
    }

    ~CalendarLock() {
        if (descriptor >= 0) {
            flock(descriptor, LOCK_UN);
            close(descriptor);
        }
    }

    bool acquired() const { return descriptor >= 0; }

  private:
    int descriptor = -1;
};

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
    std::error_code filesystemError;
    if (!fs::is_directory(directory, filesystemError)) {
        error = "calendar directory is unavailable";
        return false;
    }

    std::vector<Event> events;
    std::vector<std::string> warnings;
    std::set<std::string> uids;
    for (const fs::directory_entry &entry : fs::directory_iterator(directory, filesystemError)) {
        if (filesystemError) {
            error = "could not scan calendar directory: " + filesystemError.message();
            return false;
        }
        if (!entry.is_regular_file(filesystemError) || entry.path().extension() != ".ics")
            continue;
        std::ifstream file(entry.path(), std::ios::binary);
        if (!file) {
            error = entry.path().string() + ": could not open file";
            return false;
        }
        const std::string source((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        const ParseResult parsed = parseCalendar(source);
        if (!parsed.error.empty()) {
            warnings.push_back(entry.path().filename().string() + ": malformed event omitted from cache");
            continue;
        }
        for (const Event &event : parsed.events) {
            if (!uids.insert(event.uid).second) {
                error = "duplicate UID: " + event.uid;
                return false;
            }
        }
        if (source.find("RRULE") != std::string::npos || source.find("RDATE") != std::string::npos) {
            warnings.push_back(entry.path().filename().string() + ": recurring event omitted from cache");
            continue;
        }
        events.insert(events.end(), parsed.events.begin(), parsed.events.end());
    }
    return writeCache(output, serializeSyncedCalendar(std::move(events), sourceId, warnings), error);
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

bool eventFromJson(const QJsonObject &object, Event &event, std::string &error) {
    for (const char *key : {"uid", "title", "description", "location", "start", "end"}) {
        if (!object.value(QLatin1String(key)).isString()) {
            error = "event fields are invalid";
            return false;
        }
    }
    if (!object.value("allDay").isBool() || !object.value("reminders").isArray()) {
        error = "event fields are invalid";
        return false;
    }
    const auto stringValue = [&object](const char *key) {
        return object.value(QLatin1String(key)).toString().toStdString();
    };
    event.uid         = stringValue("uid");
    event.summary     = stringValue("title");
    event.description = stringValue("description");
    event.location    = stringValue("location");
    event.startTime   = stringValue("start");
    event.endTime     = stringValue("end");
    event.allDay      = object.value("allDay").toBool();
    if (event.uid.empty() || event.startTime.empty() || event.endTime.empty()) {
        error = "event requires uid, start, and end";
        return false;
    }
    const QString startText       = QString::fromStdString(event.startTime);
    const QString endText         = QString::fromStdString(event.endTime);
    const QDate startDate         = event.allDay ? QDate::fromString(startText, Qt::ISODate) : QDate{};
    const QDate endDate           = event.allDay ? QDate::fromString(endText, Qt::ISODate) : QDate{};
    const QDateTime startDateTime = event.allDay ? QDateTime{} : QDateTime::fromString(startText, Qt::ISODate);
    const QDateTime endDateTime   = event.allDay ? QDateTime{} : QDateTime::fromString(endText, Qt::ISODate);
    if (event.allDay ? !startDate.isValid() || !endDate.isValid()
                     : !startDateTime.isValid() || !endDateTime.isValid()) {
        error = "event dates are invalid";
        return false;
    }
    if (event.allDay ? endDate <= startDate : endDateTime <= startDateTime) {
        error = "event end must be later than start";
        return false;
    }
    const QJsonArray reminders = object.value("reminders").toArray();
    for (const QJsonValue &value : reminders) {
        const int minutes = value.toObject().value("minutesBefore").toInt(-1);
        if (minutes < 0) {
            error = "reminders must contain nonnegative minutesBefore values";
            return false;
        }
        event.reminders.push_back(minutes);
    }
    return true;
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
    const fs::path eventPath = directory / uidFileName(uid);
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
    if (rebuildUnlocked(directory, output, sourceId, error))
        return true;
    error = "event committed but cache rebuild failed: " + error;
    return false;
}

QJsonObject eventJson(const Event &event) {
    QJsonArray reminders;
    for (const int minutes : event.reminders)
        reminders.append(QJsonObject{{"minutesBefore", minutes}});
    return QJsonObject{
        {"uid", QString::fromStdString(event.uid)},
        {"title", QString::fromStdString(event.summary)},
        {"description", QString::fromStdString(event.description)},
        {"location", QString::fromStdString(event.location)},
        {"start", QString::fromStdString(event.startTime)},
        {"end", QString::fromStdString(event.endTime)},
        {"allDay", event.allDay},
        {"reminders", reminders}};
}

bool readConflictState(const fs::path &path, QJsonObject &state, std::string &error) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        state = QJsonObject{{"version", 1}, {"conflicts", QJsonArray{}}};
        return true;
    }
    const std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(QByteArray::fromStdString(contents), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject() || document.object().value("version").toInt() != 1 || !document.object().value("conflicts").isArray()) {
        error = "conflict state is invalid";
        return false;
    }
    state = document.object();
    return true;
}

bool writeConflictState(const fs::path &path, const QJsonObject &state, std::string &error) {
    return writeCache(path, QJsonDocument(state).toJson(QJsonDocument::Compact).toStdString() + "\n", error);
}

bool readSingleEvent(const fs::path &path, Event &event, std::string &raw, std::string &error) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        error = "conflict ICS file is unavailable";
        return false;
    }
    raw.assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    const ParseResult parsed = parseCalendar(raw);
    if (!parsed.error.empty() || parsed.events.size() != 1) {
        error = "conflict ICS file must contain one valid event";
        return false;
    }
    event = parsed.events.front();
    return true;
}

bool captureConflict(const fs::path &statePath, const fs::path &localPath,
                     const fs::path &remotePath, std::string &error) {
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
    bool replaced        = false;
    for (int index = 0; index < conflicts.size(); ++index) {
        if (conflicts[index].toObject().value("uid").toString() != QString::fromStdString(local.uid))
            continue;
        const QJsonObject existing = conflicts[index].toObject();
        const bool unchanged       = existing.value("localIcs").toString().toStdString() == localRaw && existing.value("remoteIcs").toString().toStdString() == remoteRaw;
        conflicts[index]           = QJsonObject{
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
    if (choice != "local" && choice != "remote") {
        error = "conflict choice must be local or remote";
        return false;
    }
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
    QJsonArray conflicts = state.value("conflicts").toArray();
    for (int index = 0; index < conflicts.size(); ++index) {
        QJsonObject conflict = conflicts[index].toObject();
        if (conflict.value("uid").toString().toStdString() != uid)
            continue;
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
    Event local;
    Event remote;
    std::string localRaw;
    std::string remoteRaw;
    if (!readSingleEvent(localPath, local, localRaw, error) || !readSingleEvent(remotePath, remote, remoteRaw, error))
        return false;
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
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
        return writeAtomicallyFile(losingPath.string(), selected, error);
    }
    error = "conflict UID was not found";
    return false;
}

bool clearConflict(const fs::path &statePath, const std::string &uid, std::string &error) {
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
    QJsonArray remaining;
    for (const QJsonValue &value : state.value("conflicts").toArray()) {
        if (value.toObject().value("uid").toString().toStdString() != uid)
            remaining.append(value);
    }
    state["conflicts"] = remaining;
    return writeConflictState(statePath, state, error);
}

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
    QCoreApplication application(argc, argv);
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
