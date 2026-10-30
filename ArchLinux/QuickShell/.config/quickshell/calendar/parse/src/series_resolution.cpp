#include "series_resolution.h"
#include "calendar_json.h"
#include "calendar_lock.h"
#include "conflict_state.h"
#include "series_group.h"
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QRegularExpression>
#include <cerrno>
#include <map>
#include <set>
#include <sys/stat.h>

namespace fs = std::filesystem;
namespace {
fs::path progressPath(const fs::path &state) { return state.parent_path() / "group-resolution.json"; }

bool checkResolutionTarget(const QStringList &args, const fs::path &state, std::string &error) {
    QString detail;
    if (!checkSeriesTarget(args[0].toStdString(), args[1].toStdString(), args[2], detail)) {
        error = detail.toStdString();
        return false;
    }
    std::error_code filesystemError;
    const auto cache = fs::weakly_canonical(args[1].toStdString(), filesystemError);
    if (filesystemError) {
        error = "group cache path is unavailable";
        return false;
    }
    for (const auto &reserved : {state, progressPath(state)}) {
        const auto path = fs::weakly_canonical(reserved, filesystemError);
        if (filesystemError || cache == path) {
            error = "group cache output aliases conflict/resolution state";
            return false;
        }
    }
    return true;
}

bool syncFile(const fs::path &path, bool directory, std::string &error) {
    const int fd  = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (directory ? O_DIRECTORY : 0));
    const bool ok = fd >= 0 && fsync(fd) == 0;
    if (fd >= 0)
        close(fd);
    if (!ok)
        error = "could not durably sync group resolution state";
    return ok;
}

bool readProgress(const fs::path &state, QJsonObject &result, bool required, std::string &error) {
    const auto path = progressPath(state);
    const int fd    = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        if (errno == ENOENT && !required)
            return true;
        error = "group resolution state is unavailable or unsafe";
        return false;
    }
    struct stat info{};
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size > 128 * 1024) {
        close(fd);
        error = "group resolution state exceeds limit or is unsafe";
        return false;
    }
    QFile file;
    if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
        close(fd);
        return false;
    }
    const auto text = file.read(128 * 1024 + 1);
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(text, &parseError);
    result              = document.object();
    const QStringList keys{"version", "uid", "revision", "choice", "phase", "seen", "directory", "cache", "sourceId", "selectedRevision"};
    static const QRegularExpression hash("^[a-f0-9]{64}$");
    bool valid = text.size() <= 128 * 1024 && parseError.error == QJsonParseError::NoError && document.isObject() && result.size() == keys.size();
    for (const auto &key : keys)
        valid = valid && result.contains(key);
    valid = valid && result.value("version") == 1 && result.value("uid").isString() && !result.value("uid").toString().isEmpty() && result.value("revision").isString() && hash.match(result.value("revision").toString()).hasMatch() && result.value("choice").isString() && QStringList{"local", "remote"}.contains(result.value("choice").toString()) && result.value("phase").isString() && QStringList{"review", "apply", "committed"}.contains(result.value("phase").toString()) && result.value("seen").isArray() && result.value("seen").toArray().size() <= 366;
    for (const auto &key : {"directory", "cache", "sourceId", "selectedRevision"})
        valid = valid && result.value(key).isString();
    if (result.value("phase") == "review") {
        for (const auto &key : {"directory", "cache", "sourceId", "selectedRevision"})
            valid = valid && result.value(key) == "";
    } else {
        valid = valid && !result.value("directory").toString().isEmpty() && !result.value("cache").toString().isEmpty() && !result.value("sourceId").toString().isEmpty() && hash.match(result.value("selectedRevision").toString()).hasMatch();
    }
    std::set<QString> seen;
    for (const auto &value : result.value("seen").toArray())
        valid = valid && value.isString() && !value.toString().isEmpty() && seen.insert(value.toString()).second;
    if (!valid)
        error = "group resolution state schema is invalid";
    return valid;
}

bool writeProgress(const fs::path &state, const QJsonObject &progress, std::string &error) {
    const auto path = progressPath(state);
    struct stat info{};
    const auto status = lstat(path.c_str(), &info);
    if ((status == 0 && !S_ISREG(info.st_mode)) || (status < 0 && errno != ENOENT)) {
        error = "group resolution state is unsafe";
        return false;
    }
    return writeAtomicallyFile(path.string(), QJsonDocument(progress).toJson(QJsonDocument::Compact).toStdString(), error) && syncFile(path, false, error) && syncFile(path.parent_path(), true, error);
}

bool removeProgress(const fs::path &state, std::string &error) {
    if (unlink(progressPath(state).c_str()) != 0) {
        error = "could not remove group resolution state";
        return false;
    }
    return syncFile(state.parent_path(), true, error);
}

bool findGroup(const QJsonObject &state, const QString &uid, const QString &revision, QJsonObject &record, std::string &error) {
    for (const auto &value : state.value("conflicts").toArray()) {
        const auto candidate = value.toObject();
        if (candidate.value("uid") != uid)
            continue;
        if (candidate.value("kind") != "group" || !candidate.value("ready").toBool() || candidate.value("revision") != revision) {
            error = "group conflict changed or is incomplete; reopen conflict";
            return false;
        }
        record = candidate;
        return true;
    }
    error = "group conflict was not found";
    return false;
}

bool progressMatches(const QJsonObject &progress, const QJsonObject &record, const QString &phase, std::string &error) {
    if (progress.value("uid") != record.value("uid") || progress.value("revision") != record.value("revision") || progress.value("choice") != record.value("choice") || progress.value("phase") != phase) {
        error = "group conflict review changed; no resolution authorized";
        return false;
    }
    return true;
}

bool allSeen(const QJsonObject &progress, const QJsonObject &record, std::string &error) {
    std::set<QString> expected, seen;
    for (const auto &value : record.value("members").toArray())
        expected.insert(value.toObject().value("uid").toString());
    for (const auto &value : progress.value("seen").toArray())
        seen.insert(value.toString());
    if (expected != seen) {
        error = "not every group member was reviewed/resolved; reopen conflict";
        return false;
    }
    return true;
}

void clearRecord(QJsonObject &state, const QString &uid, const QString &revision) {
    QJsonArray remaining;
    for (const auto &value : state.value("conflicts").toArray()) {
        const auto record = value.toObject();
        if (record.value("kind") != "group" || record.value("uid") != uid || record.value("revision") != revision)
            remaining.append(value);
    }
    state["conflicts"] = remaining;
}

bool rebuildResolutionCache(const QStringList &args, const QJsonObject &actual, std::string &error) {
    if (!refreshSyncedCacheEntry(args[0].toStdString(), args[1].toStdString(), args[2].toStdString(), actual.value("master").toObject().value("uid").toString().toStdString(), error))
        return false;
    QFile file(args[1]);
    if (!file.open(QIODevice::ReadOnly) || file.size() > 32 * 1024 * 1024) {
        error = "resolved group cache is unavailable or exceeds limit";
        return false;
    }
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(file.read(32 * 1024 * 1024 + 1), &parseError);
    QJsonArray members;
    std::set<QString> memberUids;
    for (const auto &value : actual.value("members").toArray()) {
        const auto member = value.toObject();
        members.append(QJsonObject{{"uid", member.value("uid")}, {"revision", member.value("revision")}});
        memberUids.insert(member.value("uid").toString());
    }
    bool found        = false;
    const auto master = actual.value("master").toObject();
    for (const auto &value : document.object().value("events").toArray()) {
        const auto event = value.toObject();
        if (memberUids.count(event.value("sourceUid").toString())) {
            error = "resolved cache still contains individual group members";
            return false;
        }
        if (event.value("sourceUid") != master.value("uid"))
            continue;
        if (found || event.value("revision") != actual.value("revision") || event.value("calendarId") != args[2] || event.value("recurrence") != master.value("recurrence") || event.value("seriesGroup").toObject().value("members") != members) {
            error = "resolved cache does not match complete reviewed group";
            return false;
        }
        found = true;
    }
    if (!found || parseError.error != QJsonParseError::NoError || !document.isObject()) {
        error = "resolved logical group is missing from cache";
        return false;
    }
    return true;
}
}

bool runSeriesResolution(const QString &command, const QStringList &args, std::string &error, bool &sourceCommitted) {
    sourceCommitted = false;
    const std::map<QString, int> counts{{"conflict-group-select", 4}, {"group-review-begin", 3}, {"group-callback", 6}, {"group-prepare", 6}, {"group-finish", 6}, {"group-cancel", 4}};
    const auto count = counts.find(command);
    if (count == counts.end() || args.size() != count->second) {
        error = "group resolution arguments are invalid";
        return false;
    }
    const bool sourceOperation = command == "group-prepare" || command == "group-finish" || command == "group-cancel";
    const fs::path statePath((sourceOperation ? args[3] : args[0]).toStdString());
    CalendarLock stateLock(statePath.parent_path(), error);
    if (!stateLock.acquired())
        return false;
    QJsonObject state;
    if (!readConflictState(statePath, state, error))
        return false;
    if (command == "group-cancel") {
        QJsonObject progress;
        if (!readProgress(statePath, progress, false, error))
            return false;
        if (progress.isEmpty())
            return true;
        if (progress.value("phase") == "review")
            return removeProgress(statePath, error);
        if (progress.value("phase") != "committed") {
            error = "group resolution interrupted; sync stays paused until calendar resources are reviewed";
            return false;
        }
        if (progress.value("directory") != args[0] || progress.value("cache") != args[1] || progress.value("sourceId") != args[2]) {
            error = "committed group recovery target differs";
            return false;
        }
        if (!checkResolutionTarget(args, statePath, error))
            return false;
        CalendarLock sourceLock(args[0].toStdString(), error);
        if (!sourceLock.acquired())
            return false;
        QJsonObject actual;
        QString detail;
        if (!inspectSeriesGroup(args[0].toStdString(), progress.value("uid").toString(), actual, detail) || actual.value("revision") != progress.value("selectedRevision")) {
            error = "committed group changed; recovery requires review: " + detail.toStdString();
            return false;
        }
        sourceCommitted = true;
        if (!rebuildResolutionCache(args, actual, error))
            return false;
        clearRecord(state, progress.value("uid").toString(), progress.value("revision").toString());
        return writeConflictState(statePath, state, error) && removeProgress(statePath, error);
    }
    const QString uid      = sourceOperation ? args[4] : args[1];
    const QString revision = sourceOperation ? args[5] : command == "conflict-group-select" ? args[3]
                                                                                            : args[2];
    QJsonObject record;
    if (!findGroup(state, uid, revision, record, error))
        return false;
    if (command == "conflict-group-select") {
        if (!QStringList{"local", "remote"}.contains(args[2])) {
            error = "group choice must be local or remote";
            return false;
        }
        QJsonObject active;
        if (!readProgress(statePath, active, false, error))
            return false;
        if (!active.isEmpty() && active.value("phase") != "review") {
            error = "group resolution recovery required";
            return false;
        }
        QJsonArray records = state.value("conflicts").toArray();
        for (int index = 0; index < records.size(); ++index)
            if (records[index].toObject().value("uid") == uid) {
                record["choice"] = args[2];
                records[index]   = record;
            }
        state["conflicts"] = records;
        return writeConflictState(statePath, state, error);
    }
    if (!QStringList{"local", "remote"}.contains(record.value("choice").toString())) {
        error = "group conflict has no reviewed choice";
        return false;
    }
    if (command == "group-review-begin") {
        QJsonObject active;
        if (!readProgress(statePath, active, false, error))
            return false;
        if (!active.isEmpty() && active.value("phase") != "review") {
            error = "group resolution recovery required";
            return false;
        }
        const QJsonObject progress{{"version", 1}, {"uid", uid}, {"revision", revision}, {"choice", record.value("choice")}, {"phase", "review"}, {"seen", QJsonArray{}}, {"directory", ""}, {"cache", ""}, {"sourceId", ""}, {"selectedRevision", ""}};
        return writeProgress(statePath, progress, error);
    }
    QJsonObject progress;
    if (!readProgress(statePath, progress, true, error))
        return false;
    const QString phase = command == "group-callback" ? args[3] : command == "group-prepare" ? "review"
                                                                                             : "apply";
    if (!progressMatches(progress, record, phase, error))
        return false;
    if (command == "group-callback") {
        if (!QStringList{"review", "apply"}.contains(phase)) {
            error = "group callback phase is invalid";
            return false;
        }
        Event local, remote;
        std::string localRaw, remoteRaw;
        if (!readSingleEvent(args[4].toStdString(), local, localRaw, error) || !readSingleEvent(args[5].toStdString(), remote, remoteRaw, error))
            return false;
        for (const auto &value : record.value("members").toArray()) {
            const auto member = value.toObject();
            if (member.value("uid").toString().toStdString() != local.uid || local.uid != remote.uid)
                continue;
            const auto expectedA = member.value("localIcs").toString().toStdString();
            const auto expectedB = member.value("remoteIcs").toString().toStdString();
            const auto selected  = record.value("choice") == "local" ? expectedA : expectedB;
            if ((localRaw != expectedA && !(phase == "apply" && localRaw == selected)) || (remoteRaw != expectedB && !(phase == "apply" && remoteRaw == selected))) {
                error = "group member versions changed; reopen conflict";
                return false;
            }
            if (phase == "apply") {
                CalendarLock sourceLock(progress.value("directory").toString().toStdString(), error);
                QString detail;
                if (!sourceLock.acquired() || !checkPreparedSeriesFiles(progress.value("directory").toString().toStdString(), detail)) {
                    if (error.empty())
                        error = detail.toStdString();
                    return false;
                }
                const auto losing = record.value("choice") == "local" ? args[5] : args[4];
                if (!writeConflictBuffer(losing.toStdString(), record.value("choice") == "local" ? remoteRaw : localRaw, selected, error))
                    return false;
            }
            auto seen = progress.value("seen").toArray();
            if (!seen.contains(QString::fromStdString(local.uid)))
                seen.append(QString::fromStdString(local.uid));
            progress["seen"] = seen;
            return writeProgress(statePath, progress, error);
        }
        error = "unrelated conflict left unchanged";
        return false;
    }
    if (!allSeen(progress, record, error))
        return false;
    QString detail;
    if (!checkResolutionTarget(args, statePath, error))
        return false;
    CalendarLock sourceLock(args[0].toStdString(), error);
    if (!sourceLock.acquired())
        return false;
    if (command == "group-prepare") {
        QJsonObject current, selectedSnapshot;
        if (!inspectSeriesGroup(args[0].toStdString(), uid, current, detail)) {
            error = detail.toStdString();
            return false;
        }
        std::map<std::string, std::string> currentSources, selectedSources;
        for (const auto &value : current.value("members").toArray()) {
            const auto member                                            = value.toObject();
            currentSources[member.value("uid").toString().toStdString()] = member.value("ical").toString().toStdString();
        }
        std::vector<SeriesFileChange> changes;
        if (currentSources.size() != static_cast<size_t>(record.value("members").toArray().size())) {
            error = "local group membership changed";
            return false;
        }
        for (const auto &value : record.value("members").toArray()) {
            const auto member    = value.toObject();
            const auto memberUid = member.value("uid").toString().toStdString();
            const auto before    = member.value("localIcs").toString().toStdString();
            if (!currentSources.count(memberUid) || currentSources[memberUid] != before) {
                error = "local group member changed; reopen conflict";
                return false;
            }
            const auto selected        = member.value(record.value("choice") == "local" ? "localIcs" : "remoteIcs").toString().toStdString();
            selectedSources[memberUid] = selected;
            changes.push_back({memberUid, before, selected});
        }
        if (!inspectSeriesSources(selectedSources, uid, selectedSnapshot, detail) || !prepareSeriesFiles(args[0].toStdString(), changes, detail)) {
            error = detail.toStdString();
            return false;
        }
        progress["phase"]            = "apply";
        progress["seen"]             = QJsonArray{};
        progress["directory"]        = args[0];
        progress["cache"]            = args[1];
        progress["sourceId"]         = args[2];
        progress["selectedRevision"] = selectedSnapshot.value("revision");
        return writeProgress(statePath, progress, error);
    }
    if (progress.value("directory") != args[0] || progress.value("cache") != args[1] || progress.value("sourceId") != args[2]) {
        error = "group completion target differs";
        return false;
    }
    if (!finishSeriesFiles(args[0].toStdString(), detail, sourceCommitted)) {
        error = detail.toStdString();
        return false;
    }
    QJsonObject actual;
    if (!inspectSeriesGroup(args[0].toStdString(), uid, actual, detail) || actual.value("revision") != progress.value("selectedRevision") || actual.value("master") != record.value(record.value("choice").toString())) {
        error = "resolved group does not match reviewed logical rule: " + detail.toStdString();
        return false;
    }
    progress["phase"] = "committed";
    if (!writeProgress(statePath, progress, error))
        return false;
    if (!rebuildResolutionCache(args, actual, error))
        return false;
    clearRecord(state, uid, revision);
    return writeConflictState(statePath, state, error) && removeProgress(statePath, error);
}
