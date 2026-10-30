#include "caldav.h"
#include "caldav_remote.h"
#include "calendar_json.h"
#include "calendar_lock.h"
#include "conflict_state.h"
#include "removal_files.h"
#include "recurrence.h"
#include "series_conflict.h"
#include <QCryptographicHash>
#include <QDir>
#include <QJsonDocument>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSet>
#include <QUuid>
#include <algorithm>
#include <cmath>
#include <csignal>
#include <fcntl.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

namespace CalDavBackend {
using namespace SubscriptionBackend;
namespace {
constexpr qint64 cacheLimit = 64LL * 1024 * 1024;
constexpr qint64 conflictLimit = 616LL * 1024 * 1024;
QString markerPath(const Paths &p, const QString &id) { return p.state + "/conversion-" + id + ".json"; }
bool present(const QString &path) { return QFileInfo::exists(path) || QFileInfo(path).isSymLink(); }
QString identity(const struct stat &value) { return QString::number(value.st_dev) + ':' + QString::number(value.st_ino); }
QJsonObject profileFor(const QJsonObject &registry, const QString &id) {
    for (const auto &value : registry.value("profiles").toArray()) if (value.toObject().value("id") == id) return value.toObject();
    return {};
}
bool saveObject(const QString &path, const QJsonObject &object, QString &error, bool create = false) {
    return writeFile(path, QJsonDocument(object).toJson(), error, create);
}
bool copyOwned(const QString &source, const QString &destination, QString &digest, QString &error, qint64 limit = 0) {
    const int fd = open(QFile::encodeName(source).constData(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    struct stat before{}, after{}, named{};
    if (fd < 0 || fstat(fd, &before) != 0 || !S_ISREG(before.st_mode) || before.st_uid != geteuid()
        || before.st_nlink != 1 || before.st_size < 0 || (limit && before.st_size > limit)) {
        if (fd >= 0) close(fd);
        error = "Conversion source is missing, unsafe or too large: " + source; return false;
    }
    QFile input, output(destination);
    if (!input.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) { close(fd); error = "Could not read conversion source: " + source; return false; }
    if (!destination.isEmpty() && !output.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
        error = "Could not preserve conversion source: " + destination; return false;
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    while (!input.atEnd()) {
        const auto bytes = input.read(65536);
        if (input.error() != QFileDevice::NoError || (output.isOpen() && output.write(bytes) != bytes.size())) {
            error = "Could not copy conversion source: " + source; return false;
        }
        hash.addData(bytes);
    }
    if (output.isOpen() && (!output.flush() || fsync(output.handle()) != 0)) { error = "Could not save conversion copy: " + destination; return false; }
    if (fstat(fd, &after) != 0 || lstat(QFile::encodeName(source).constData(), &named) != 0
        || identity(before) != identity(named) || before.st_size != after.st_size
        || before.st_mtim.tv_sec != after.st_mtim.tv_sec || before.st_mtim.tv_nsec != after.st_mtim.tv_nsec
        || before.st_ctim.tv_sec != after.st_ctim.tv_sec || before.st_ctim.tv_nsec != after.st_ctim.tv_nsec) {
        error = "Conversion source changed; newer contents preserved: " + source; return false;
    }
    digest = QString::fromLatin1(hash.result().toHex());
    return true;
}
bool collection(const QString &source, const QString &destination, QJsonObject &manifest, QString &error) {
    struct stat stamp{};
    if (lstat(QFile::encodeName(source).constData(), &stamp) != 0 || !S_ISDIR(stamp.st_mode) || stamp.st_uid != geteuid()
        || !ensureDirectory(source, error) || (!destination.isEmpty() && !ensureDirectory(destination, error))) {
        if (error.isEmpty()) error = "Calendar collection is missing or unsafe";
        return false;
    }
    manifest = {{"identity", identity(stamp)}};
    QJsonObject files;
    for (const auto &name : QDir(source).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDir::Name)) {
        if (name == ".calendar-sync.lock") continue;
        if (name.startsWith(".calendar-series-")) { error = "Resolve pending calendar event operation before conversion"; return false; }
        QString digest;
        if (!copyOwned(source + '/' + name, destination.isEmpty() ? QString{} : destination + '/' + name, digest, error, cacheLimit)) return false;
        files[name] = digest;
    }
    manifest["files"] = files;
    return true;
}
bool sessionData(const QJsonObject &pause, QJsonObject &data, QString &error) {
    QByteArray bytes;
    if (!readFile(pause.value("path").toString() + "/session.json", bytes, error, false, cacheLimit)
        || revision(bytes) != pause.value("revision")) {
        if (error.isEmpty()) error = "Conversion snapshot changed; inspect retained files";
        return false;
    }
    const auto doc = QJsonDocument::fromJson(bytes);
    if (!doc.isObject() || doc.object().value("id") != pause.value("id") || doc.object().value("session") != pause.value("session")) {
        error = "Conversion snapshot is invalid"; return false;
    }
    data = doc.object();
    return true;
}
bool unchangedReviewFiles(const QJsonObject &pause, const QJsonObject &data, QString &error) {
    const auto path = pause.value("path").toString();
    QJsonObject expected{{"cache.json", data.value("cacheRevision")}, {"conflicts.json", data.value("conflictRevision")},
        {"original-config", data.value("configRevision")}, {"session.json", pause.value("revision")},
        {"verified-cache.json", data.value("verifiedCacheRevision")}};
    const auto database = data.value("database").toObject();
    for (const auto &suffix : database.keys()) expected["qs_caldav_" + pause.value("id").toString() + ".status" + suffix] = database.value(suffix);
    QJsonObject original;
    if (!collection(path + "/original", {}, original, error) || original.value("files") != data.value("sources").toObject().value("files")) return false;
    auto names = QDir(path).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot);
    if (!names.removeOne("original") || names.size() != expected.size()) return false;
    for (const auto &name : names) {
        QString digest;
        if (!expected.contains(name) || !copyOwned(path + '/' + name, {}, digest, error, conflictLimit) || expected.value(name) != digest) return false;
    }
    return true;
}
bool conflictData(const QJsonObject &pause, QJsonObject &state, QString &error) {
    std::string detail;
    if (!readConflictState((pause.value("path").toString() + "/conflicts.json").toStdString(), state, detail)) {
        error = QString::fromStdString(detail); return false;
    }
    return true;
}
bool validLocalProjection(const QJsonArray &events, const QString &id, QString &error) {
    QSet<QString> seen;
    for (const auto &value : events) {
        const auto event = value.toObject();
        const auto uid = event.value("uid").toString();
        bool valid = value.isObject() && !uid.isEmpty() && !seen.contains(uid) && event.value("calendarId") == id
            && event.value("allDay").isBool() && event.value("reminders").isArray() && validateRecurrenceMaster(event, error);
        for (const auto &key : {"uid", "title", "description", "location", "start", "end"}) valid = valid && event.value(key).isString();
        if (event.contains("readOnly")) valid = valid && event.value("readOnly") == true;
        if (event.contains("ical")) valid = valid && event.value("readOnly") == true && !event.contains("timezone")
            && event.value("ical").toString().size() <= 16 * 1024 * 1024;
        QSet<double> minutes;
        for (const auto &reminder : event.value("reminders").toArray()) {
            const auto object = reminder.toObject();
            const auto number = object.value("minutesBefore");
            const auto count = number.toDouble(-1);
            valid = valid && reminder.isObject() && object.size() == 1 && number.isDouble()
                && std::isfinite(count) && count >= 0 && count <= 9007199254740991.0 && std::floor(count) == count && !minutes.contains(count);
            minutes.insert(count);
        }
        if (!valid) {
            error = "Prepared local calendar is invalid; original sources preserved"; return false;
        }
        seen.insert(uid);
    }
    return true;
}
bool retainNominalOneDaySources(const QString &directory, const QString &id, const QJsonObject &files, QJsonArray &events, QString &error) {
    QMap<QString, QByteArray> sources;
    QMap<QString, QJsonObject> expected;
    for (const auto &name : QDir(directory).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDir::Name)) {
        if (std::filesystem::path(name.toStdString()).extension() != ".ics") continue;
        QByteArray raw;
        if (!readFile(directory + '/' + name, raw, error, false, 16 * 1024 * 1024)) return false;
        if (!files.contains(name) || revision(raw) != files.value(name)) {
            error = "Staged calendar source changed; original sources preserved"; return false;
        }
        const auto parsed = parseCalendar(raw.toStdString());
        if (!parsed.error.empty() || parsed.events.empty()) {
            error = "Staged calendar source is invalid; original sources preserved"; return false;
        }
        for (const auto &event : parsed.events) {
            if (event.nominalOneDayAlarmRevision.empty()) continue;
            const auto uid = QString::fromStdString(event.uid);
            if (parsed.events.size() != 1 || sources.contains(uid) || QString::fromUtf8(raw).toUtf8() != raw) {
                error = "Nominal reminder source is shared, ambiguous or invalid; original sources preserved"; return false;
            }
            sources[uid] = raw;
            expected[uid] = QJsonDocument::fromJson(QByteArray::fromStdString(serializeSyncedCalendar({event}, id.toStdString())))
                                .object().value("events").toArray().first().toObject();
        }
    }
    QJsonArray projected;
    for (const auto &value : events) {
        auto event = value.toObject();
        const auto uid = event.value("sourceUid").toString();
        if (sources.contains(uid)) {
            if (!value.isObject() || event != expected.value(uid)) {
                error = "Nominal reminder source and staged cache differ; original sources preserved"; return false;
            }
            event["ical"] = QString::fromUtf8(sources.take(uid));
            event["readOnly"] = true;
        }
        projected.append(event);
    }
    if (!sources.isEmpty()) { error = "Nominal reminder is missing from staged cache; original sources preserved"; return false; }
    events = projected;
    return true;
}
QJsonObject describe(const QJsonObject &pause, const QJsonObject &state) {
    QJsonArray conflicts;
    for (const auto &value : state.value("conflicts").toArray()) {
        auto record = value.toObject();
        const auto uid = record.value("uid").toString();
        const auto digest = record.value("kind") == "group" ? record.value("revision").toString()
            : revision(record.value("localIcs").toString().toUtf8() + '\0' + record.value("remoteIcs").toString().toUtf8());
        record.remove("localIcs"); record.remove("remoteIcs"); record.remove("members");
        for (const auto &side : {QStringLiteral("local"), QStringLiteral("remote")}) {
            auto preview = record.value(side).toObject(); preview.remove("ical"); record[side] = preview;
        }
        record["uid"] = uid; record["revision"] = digest; record["calendarId"] = pause.value("id");
        conflicts.append(record);
    }
    return {{"ok", true}, {"id", pause.value("id")}, {"session", pause.value("session")}, {"revision", pause.value("revision")},
            {"conflicts", conflicts}, {"paused", !pause.value("disconnected").toBool()}, {"remoteAttempted", pause.value("remoteAttempted")},
            {"disconnected", pause.value("disconnected")}, {"localPath", pause.value("localPath")}, {"recoveryPaths", QJsonArray{pause.value("path")}}};
}
bool restoreScheduling(const QJsonObject &data, QString &error) {
    for (const auto &value : data.value("links").toArray()) {
        const auto link = value.toObject(); const auto path = link.value("path").toString();
        if (!ensureDirectory(QFileInfo(path).path(), error)) return false;
        if (present(path)) {
            std::error_code code;
            const auto raw = std::filesystem::read_symlink(QFile::encodeName(path).constData(), code);
            if (code || QString::fromStdString(raw.native()) != link.value("target")) { error = "Newer timer link preserved: " + path; return false; }
        } else if (symlink(QFile::encodeName(link.value("target").toString()).constData(), QFile::encodeName(path).constData()) != 0) {
            error = "Could not restore calendar timer link: " + path; return false;
        }
    }
    if (!data.value("links").toArray().isEmpty() && !command("systemctl", {"--user", "daemon-reload"}, 15000)) {
        error = "Could not reload previous calendar timer"; return false;
    }
    if (data.value("timerActive").toBool() && !command("systemctl", {"--user", "start", data.value("timer").toString()}, 30000)) {
        error = "Could not restore previous calendar timer activity"; return false;
    }
    return true;
}
bool begin(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    const auto id = request.value("id").toString();
    if (!validId(id) || !conversionAllowed(p, id, error)) return false;
    Config config; QJsonObject registry;
    if (!loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    const auto profile = profileFor(registry, id);
    if (profile.value("type") != "synced" || request.value("expectedProfile") != profile || request.value("expectedRevision") != revision(config.original)) {
        error = "Calendar settings changed; reopen conversion"; return false;
    }
    if (std::none_of(config.records.begin(), config.records.end(), [&](const auto &r) { return r.id == id; })) { error = "Managed synced calendar not found"; return false; }
    if (!remoteSyncAllowed(p, id, error)) return false;
    if (present(p.data + '/' + id + ".json")) { error = "Local calendar destination already exists; nothing overwritten"; return false; }
    QJsonObject inspected;
    if (!retireConverted(p, request, {}, inspected, error, true)) return false;
    if (!command("/bin/sh", {p.broker, "check-recovery"}, 10000)) { error = "Resolve pending calendar operation before conversion"; return false; }
    QString worker, timerState;
    const auto timer = "quickshell-calendar-caldav-" + id + ".timer";
    if (!CalendarRemoval::property("quickshell-calendar-caldav@" + id + ".service", "ActiveState", worker, error)
        || !QStringList{"inactive", "failed"}.contains(worker)
        || !CalendarRemoval::property(timer, "ActiveState", timerState, error)
        || !QStringList{"active", "inactive", "failed"}.contains(timerState)) {
        if (error.isEmpty()) error = "Calendar synchronization is active; try conversion when it finishes";
        return false;
    }
    const auto definition = p.units + '/' + timer;
    QByteArray timerBytes;
    if (!readFile(definition, timerBytes, error, true) || (!timerBytes.isEmpty() && timerBytes != unitDefinitions(p, config).value(timer))) {
        if (error.isEmpty()) error = "Calendar timer has custom settings; preserved";
        return false;
    }
    const auto dropins = definition + ".d";
    if (present(dropins) && (QFileInfo(dropins).isSymLink() || !QDir(dropins).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot).isEmpty())) {
        error = "Calendar timer has custom drop-ins; preserved"; return false;
    }
    QJsonArray links;
    QStringList roots{p.units}; const auto runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty()) roots.append(runtime + "/systemd/user");
    for (const auto &root : roots) {
        const auto link = root + "/timers.target.wants/" + timer;
        if (!present(link)) continue;
        struct stat stamp{}; std::error_code code;
        const auto raw = std::filesystem::read_symlink(QFile::encodeName(link).constData(), code);
        if (lstat(QFile::encodeName(link).constData(), &stamp) != 0 || !S_ISLNK(stamp.st_mode) || stamp.st_uid != geteuid() || code
            || QDir::cleanPath(QDir(QFileInfo(link).path()).absoluteFilePath(QString::fromStdString(raw.native()))) != definition) {
            error = "Calendar timer has custom enablement; preserved: " + link; return false;
        }
        links.append(QJsonObject{{"path", link}, {"target", QString::fromStdString(raw.native())}, {"identity", identity(stamp)}});
    }
    const auto token = QUuid::createUuid().toString(QUuid::WithoutBraces).remove('-');
    const auto path = p.data + "/.calendar-convert-" + id + '-' + token;
    if (present(path) || !ensureDirectory(path, error)) return false;
    QJsonObject pause{{"version", 1}, {"id", id}, {"session", token}, {"path", path}, {"remoteAttempted", false}, {"remoteSucceeded", false}};
    bool marked = false;
    auto failed = [&] {
        if (marked) {
            result = {{"ok", false}, {"id", id}, {"paused", true}, {"recoveryPaths", QJsonArray{path}}};
            error += "; sync paused. Recovery files: " + path;
        } else { QString ignored; CalendarRemoval::purge(path, ignored); }
        return false;
    };
    QJsonObject sources;
    QByteArray cache, conflictBytes;
    std::string detail;
    CalendarLock sourceLock((p.data + '/' + id).toStdString(), detail);
    if (!sourceLock.acquired() || !collection(p.data + '/' + id, path + "/original", sources, error)
        || !validateSyncedCache((p.data + '/' + id + ".sync.json").toStdString(), id.toStdString(), detail)
        || !readFile(p.data + '/' + id + ".sync.json", cache, error, false, cacheLimit)
        || !readFile(QFileInfo(p.state).path() + "/conflicts-" + id + ".json", conflictBytes, error, true, conflictLimit)) {
        if (error.isEmpty()) error = QString::fromStdString(detail);
        return failed();
    }
    QJsonObject verified;
    if (!rebuildSyncedCache((path + "/original").toStdString(), (path + "/verified-cache.json").toStdString(), id.toStdString(), detail, true)
        || !jsonFile(path + "/verified-cache.json", verified, error, false, cacheLimit)) {
        if (error.isEmpty()) error = QString::fromStdString(detail);
        return failed();
    }
    QJsonObject displayedEvents, sourceEvents;
    for (const auto &value : QJsonDocument::fromJson(cache).object().value("events").toArray()) displayedEvents[value.toObject().value("uid").toString()] = value;
    for (const auto &value : verified.value("events").toArray()) sourceEvents[value.toObject().value("uid").toString()] = value;
    if (displayedEvents != sourceEvents) { error = "Calendar sources and displayed cache differ; refresh and review before converting"; return failed(); }
    if (conflictBytes.isEmpty()) conflictBytes = "{\"version\":1,\"conflicts\":[]}\n";
    if (!writeFile(path + "/cache.json", cache, error, true) || !writeFile(path + "/conflicts.json", conflictBytes, error, true)
        || !writeFile(path + "/original-config", config.original, error, true)) return failed();
    QJsonObject conflicts;
    if (!conflictData(pause, conflicts, error)) return failed();
    for (const auto &value : conflicts.value("conflicts").toArray()) {
        const auto record = value.toObject();
        if (record.value("kind") == "group" && !record.value("ready").toBool()) { error = record.value("problem").toString(); return failed(); }
    }
    QJsonObject db;
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) {
        const auto source = p.status + "/qs_caldav_" + id + ".status" + suffix;
        if (!present(source) && !suffix.isEmpty()) continue;
        QString digest;
        if (!copyOwned(source, path + '/' + QFileInfo(source).fileName(), digest, error)) return failed();
        db[suffix] = digest;
    }
    QJsonObject data{{"id", id}, {"session", token}, {"profile", profile}, {"configRevision", revision(config.original)},
        {"cacheRevision", revision(cache)}, {"conflictRevision", revision(conflictBytes)}, {"sources", sources}, {"database", db},
        {"verifiedCacheRevision", revision(QJsonDocument(verified).toJson())},
        {"timer", timer}, {"timerActive", timerState == "active"}, {"timerBytes", QString::fromUtf8(timerBytes)}, {"links", links}};
    const auto bytes = QJsonDocument(data).toJson(); pause["revision"] = revision(bytes);
    if (!writeFile(path + "/session.json", bytes, error, true) || !ensureDirectory(p.state, error)
        || !saveObject(markerPath(p, id), pause, error, true)) return failed();
    marked = true;
    if (!command("systemctl", {"--user", "stop", timer}, 30000)) { error = "Could not pause calendar timer"; return failed(); }
    for (const auto &value : links) {
        const auto link = value.toObject(); const auto name = link.value("path").toString();
        struct stat stamp{}; std::error_code code;
        const auto raw = std::filesystem::read_symlink(QFile::encodeName(name).constData(), code);
        if (lstat(QFile::encodeName(name).constData(), &stamp) != 0 || !S_ISLNK(stamp.st_mode) || stamp.st_uid != geteuid()
            || identity(stamp) != link.value("identity") || code || QString::fromStdString(raw.native()) != link.value("target")) {
            error = "Newer calendar timer link preserved: " + name; return failed();
        }
        if (!CalendarRemoval::erase(name, error)) return failed();
    }
    if (!links.isEmpty() && !command("systemctl", {"--user", "daemon-reload"}, 15000)) { error = "Could not reload paused calendar timer"; return failed(); }
    result = describe(pause, conflicts);
    return true;
}
bool callback(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    QJsonObject pause;
    const auto id = request.value("id").toString(), phase = request.value("phase").toString();
    if (!readConversionPause(p, id, pause, error) || pause.isEmpty() || pause.value("session") != request.value("session")
        || !pause.value("remoteAttempted").toBool() || pause.value("jobPhase") != phase
        || pause.value("pid").toInt() <= 0 || kill(pause.value("pid").toInt(), 0) != 0) {
        if (error.isEmpty()) error = "Conversion callback does not own an active final job";
        return false;
    }
    const auto path = pause.value("path").toString();
    auto reject = [&] {
        QString ignored; writeFile(path + "/callback-error", error.toUtf8(), ignored);
        return false;
    };
    if (!QStringList{"review", "apply"}.contains(phase)) { error = "New conflict appeared during final settlement; review required"; return reject(); }
    QJsonObject pairs;
    if (!jsonFile(path + "/pairs.json", pairs, error, false, conflictLimit)) return reject();
    Event local, remote; std::string a, b, detail;
    const auto localPath = request.value("localPath").toString(), remotePath = request.value("remotePath").toString();
    if (!readSingleEvent(localPath.toStdString(), local, a, detail) || !readSingleEvent(remotePath.toStdString(), remote, b, detail)) {
        error = QString::fromStdString(detail); return reject();
    }
    const auto uid = QString::fromStdString(local.uid); const auto pair = pairs.value(uid).toObject();
    if (pair.isEmpty() || local.uid != remote.uid || pair.value("local").toString().toStdString() != a || pair.value("remote").toString().toStdString() != b) {
        error = "Conflict versions changed; reopen conversion review"; return reject();
    }
    if (phase == "apply") {
        const bool chooseLocal = pair.value("choice") == "local";
        if (!writeConflictBuffer((chooseLocal ? remotePath : localPath).toStdString(), chooseLocal ? b : a, chooseLocal ? a : b, detail)) {
            error = QString::fromStdString(detail); return reject();
        }
    }
    // ponytail: pimsync 0.5.7 invokes callbacks sequentially; lock this set if callbacks become parallel.
    QJsonObject seen;
    if (!jsonFile(path + "/seen-" + phase + ".json", seen, error)) return reject();
    seen[uid] = true;
    if (!saveObject(path + "/seen-" + phase + ".json", seen, error)) return reject();
    result = {{"ok", phase == "apply"}};
    return phase == "apply"; // Capture-only review must remain unresolved, never upload.
}
bool runJob(const Paths &p, QJsonObject &pause, const QString &phase, const QStringList &args, const QJsonObject &pairs, QString &error) {
    const auto path = pause.value("path").toString();
    pause["jobPhase"] = phase; pause["pid"] = int(getpid());
    if (!saveObject(markerPath(p, pause.value("id").toString()), pause, error)) return false;
    QProcess process;
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert("CALENDAR_CONVERSION_SESSION", pause.value("session").toString());
    environment.insert("CALENDAR_CONVERSION_PHASE", phase);
    process.setProcessEnvironment(environment);
    process.setProcessChannelMode(QProcess::MergedChannels);
    const auto log = path + '/' + phase + ".log";
    process.setStandardOutputFile(log);
    const auto parent = getpid();
    process.setChildProcessModifier([parent] {
        const rlimit core{0, 0}, memory{4ULL * 1024 * 1024 * 1024, 4ULL * 1024 * 1024 * 1024}, files{640ULL * 1024 * 1024, 640ULL * 1024 * 1024};
        if (prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent || setrlimit(RLIMIT_CORE, &core) != 0
            || setrlimit(RLIMIT_AS, &memory) != 0 || setrlimit(RLIMIT_FSIZE, &files) != 0) _exit(1);
    });
    process.start("pimsync", args);
    bool ok = process.waitForStarted(5000);
    if (ok) {
        process.write(QByteArray("y\n").repeated(pairs.size() + 16)); process.closeWriteChannel();
        ok = process.waitForFinished(90000) && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
    }
    if (!ok) { process.kill(); process.waitForFinished(5000); error = "Final synchronization failed; inspect retained copies before retrying"; return false; }
    QFile output(log);
    if (!output.open(QIODevice::ReadOnly)) { error = "Could not inspect final synchronization output"; return false; }
    while (!output.atEnd()) {
        const auto line = output.readLine(65536);
        if (phase != "review" && (line.contains("Error uploading resolved item") || line.contains("Error resolving conflict:")
            || QRegularExpression("^ERROR\\s+\\[pimsync").match(QString::fromUtf8(line)).hasMatch())) {
            error = "Final synchronization did not settle safely; inspect retained copies"; return false;
        }
    }
    if (present(path + "/callback-error")) { error = "Conflict changed or could not be applied; renewed review required"; return false; }
    if (phase != "settle") {
        QJsonObject seen;
        if (!jsonFile(path + "/seen-" + phase + ".json", seen, error) || seen.keys() != pairs.keys()) {
            if (error.isEmpty()) error = "Not every reviewed conflict was verified; no further writes attempted";
            return false;
        }
    }
    return true;
}
bool finish(const Paths &p, const QJsonObject &request, QJsonObject pause, QJsonObject &result, QString &error) {
    const auto id = pause.value("id").toString(), path = pause.value("path").toString();
    auto failed = [&] {
        result = {{"ok", false}, {"id", id}, {"paused", true}, {"remoteAttempted", pause.value("remoteAttempted")}, {"recoveryPaths", QJsonArray{path}}};
        error += "; sync paused. Recovery files: " + path; return false;
    };
    QJsonObject data, registry, state, currentSources; Config config;
    if (pause.value("remoteAttempted").toBool()) { error = "Final synchronization was already attempted; inspect recovery files, do not retry automatically"; return failed(); }
    if (!sessionData(pause, data, error) || !loadConfig(p, config, error) || !loadRegistry(p, registry, error)
        || revision(config.original) != data.value("configRevision") || profileFor(registry, id) != data.value("profile")) {
        if (error.isEmpty()) error = "Calendar settings changed; original data preserved";
        return failed();
    }
    QByteArray cache, rawConflicts;
    if (!collection(p.data + '/' + id, {}, currentSources, error) || currentSources != data.value("sources")
        || !readFile(p.data + '/' + id + ".sync.json", cache, error, false, cacheLimit) || revision(cache) != data.value("cacheRevision")
        || !readFile(QFileInfo(p.state).path() + "/conflicts-" + id + ".json", rawConflicts, error, true, conflictLimit)) {
        if (error.isEmpty()) error = "Calendar source/cache changed; original data preserved";
        return failed();
    }
    if (rawConflicts.isEmpty()) rawConflicts = "{\"version\":1,\"conflicts\":[]}\n";
    if (revision(rawConflicts) != data.value("conflictRevision") || !conflictData(pause, state, error)) {
        if (error.isEmpty()) error = "Calendar conflict state changed; review required";
        return failed();
    }
    QJsonObject database;
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) {
        const auto filename = p.status + "/qs_caldav_" + id + ".status" + suffix;
        if (!present(filename) && !suffix.isEmpty()) continue;
        QString digest;
        if (!copyOwned(filename, {}, digest, error)) return failed();
        database[suffix] = digest;
    }
    if (database != data.value("database")) { error = "Sync database changed; inspect retained copies before continuing"; return failed(); }
    if (!request.value("choices").isArray()) { error = "Conversion choices must be a list"; return failed(); }
    QMap<QString, QJsonObject> choices;
    for (const auto &value : request.value("choices").toArray()) {
        const auto choice = value.toObject(); const auto uid = choice.value("uid").toString();
        if (!value.isObject() || choice.size() != 3 || uid.isEmpty() || choices.contains(uid)
            || !QStringList{"local", "remote", "local-only"}.contains(choice.value("choice").toString())) {
            error = "Invalid or duplicate conversion choice"; return failed();
        }
        choices[uid] = choice;
    }
    const auto previews = describe(pause, state).value("conflicts").toArray();
    if (choices.size() != previews.size()) { error = "Choose a version for every conflict before converting"; return failed(); }
    for (const auto &value : previews) {
        const auto preview = value.toObject();
        if (choices.value(preview.value("uid").toString()).value("revision") != preview.value("revision")) {
            error = "Conflict choice is stale; reopen conversion review"; return failed();
        }
    }
    if (present(p.data + '/' + id + ".json") || present(path + "/local") || present(path + "/local-result.json")) {
        error = "Conversion destination is occupied; retained files were not overwritten"; return failed();
    }
    QJsonObject copiedSources;
    const auto target = std::find_if(config.records.begin(), config.records.end(), [&](const auto &record) { return record.id == id; });
    if (target == config.records.end() || !checkRemoteForSync(p, *target, error)) return failed();
    if (!collection(p.data + '/' + id, path + "/local", copiedSources, error) || copiedSources != currentSources
        || !writeFile(path + "/local-cache.json", cache, error, true)) return failed();
    QJsonObject pairs;
    auto localFiles = copiedSources.value("files").toObject();
    auto serverSources = currentSources;
    auto serverFiles = serverSources.value("files").toObject();
    serverFiles.remove("displayname"); // pimsync may create/update this collection label during settlement.
    for (const auto &value : state.value("conflicts").toArray()) {
        const auto record = value.toObject(); const auto logical = record.value("uid").toString();
        const auto choice = choices.value(logical).value("choice").toString();
        const auto members = record.value("kind") == "group" ? record.value("members").toArray() : QJsonArray{record};
        for (const auto &memberValue : members) {
            const auto member = memberValue.toObject(); const auto uid = member.value("uid").toString();
            const auto a = member.value("localIcs").toString(), b = member.value("remoteIcs").toString();
            QString filename; std::string nativePath, detail;
            if (uid.isEmpty() || pairs.contains(uid) || !syncedSourcePath((p.data + '/' + id).toStdString(), uid.toStdString(), nativePath, detail) || nativePath.empty()) {
                error = "Conflict source is missing, ambiguous or shared"; return failed();
            }
            filename = QFileInfo(QString::fromStdString(nativePath)).fileName();
            QByteArray bytes;
            if (!readFile(QString::fromStdString(nativePath), bytes, error, false, cacheLimit) || bytes != a.toUtf8()) {
                if (error.isEmpty()) error = "Local conflict version changed; review required";
                return failed();
            }
            pairs[uid] = QJsonObject{{"local", a}, {"remote", b}, {"choice", choice == "local" ? "local" : "remote"}};
            serverFiles[filename] = revision((choice == "local" ? a : b).toUtf8());
            const auto selected = (choice == "remote" ? b : a).toUtf8();
            if (!writeFile(path + "/local/" + filename, selected, error)) return failed();
            localFiles[filename] = revision(selected);
        }
        std::string detail;
        if (!refreshSyncedCacheEntry((path + "/local").toStdString(), (path + "/local-cache.json").toStdString(), id.toStdString(), logical.toStdString(), detail)) {
            error = QString::fromStdString(detail); return failed();
        }
    }
    QJsonObject local;
    if (!jsonFile(path + "/local-cache.json", local, error, false, cacheLimit)) return failed();
    QJsonObject stagedSources;
    if (!collection(path + "/local", {}, stagedSources, error) || stagedSources.value("files") != localFiles) {
        if (error.isEmpty()) error = "Staged calendar sources changed; original sources preserved";
        return failed();
    }
    QJsonObject projected;
    const auto localPath = path + "/local-result.json";
    auto localEvents = local.value("events").toArray();
    if (!retainNominalOneDaySources(path + "/local", id, localFiles, localEvents, error)
        || !makeLocalDocument(id, localEvents, projected, error)) return failed();
    const auto localBytes = QJsonDocument(projected).toJson();
    if (!writeFile(localPath, localBytes, error, true) || !saveObject(path + "/pairs.json", pairs, error, true)) return failed();
    pause["remoteAttempted"] = true;
    if (!saveObject(markerPath(p, id), pause, error)) return failed();
    const QStringList resolve{"-c", p.config, "resolve-conflicts", "qs_caldav_" + id};
    if ((!pairs.isEmpty() && (!runJob(p, pause, "review", resolve, pairs, error) || !runJob(p, pause, "apply", resolve, pairs, error)))
        || !runJob(p, pause, "settle", {"-c", p.config, "sync", "qs_caldav_" + id}, pairs, error)) return failed();
    pause["remoteSucceeded"] = true;
    QString stateError;
    saveObject(markerPath(p, id), pause, stateError); // A later metadata error is not failed server synchronization.
    QByteArray preserved;
    if (!readFile(localPath, preserved, error, false, cacheLimit) || preserved != localBytes) {
        if (error.isEmpty()) error = "Prepared local result changed; retained copies were not retired";
        return failed();
    }
    serverSources["files"] = serverFiles;
    if (!retireConverted(p, {{"id", id}, {"expectedProfile", data.value("profile")}, {"expectedRevision", data.value("configRevision")}}, localPath, result, error, false, serverSources)) return failed();
    QByteArray active;
    if (result.value("localActive").toBool()
        && (!readFile(result.value("localPath").toString(), active, stateError, false, cacheLimit) || active != localBytes)) {
        result["localActive"] = false; result["activationWarning"] = true; result["localPath"] = localPath;
        result["message"] = "Sync disconnected; local calendar changed before activation. Local data preserved: " + localPath
            + (result.contains("message") ? "\n" + result.value("message").toString() : QString{});
    }
    pause["disconnected"] = true;
    auto retained = result.value("recoveryPaths").toArray();
    auto cleanupWarning = [&](const QStringList &paths) {
        for (const auto &retainedPath : paths) retained.append(retainedPath);
        result["cleanupWarning"] = true; result["recoveryPaths"] = retained;
        const auto previous = result.value("message").toString();
        result["message"] = (previous.isEmpty() ? QString{} : previous + '\n')
            + "Calendar converted; temporary cleanup incomplete. Retained files: " + paths.join(", ");
    };
    if (!result.value("localActive").toBool()) {
        pause["localPath"] = result.value("localPath");
        saveObject(markerPath(p, id), pause, stateError);
        retained.append(path); result["recoveryPaths"] = retained;
        result["message"] = result.value("message").toString() + "; recovery files: " + path;
        return true;
    }
    if (!CalendarRemoval::erase(markerPath(p, id), stateError)) {
        saveObject(markerPath(p, id), pause, stateError);
        cleanupWarning({path, markerPath(p, id)});
        return true;
    }
    if (result.value("localActive").toBool()) {
        QString detail;
        if (!CalendarRemoval::purge(path, detail)) {
            cleanupWarning({path});
        }
    }
    QDir().rmdir(p.state);
    return true;
}
} // namespace

bool makeLocalDocument(const QString &id, const QJsonArray &source, QJsonObject &local, QString &error) {
    const QSet<QString> kept{"uid", "calendarId", "title", "description", "location", "start", "end", "allDay", "reminders", "timezone", "recurrence", "ical", "readOnly"};
    QJsonArray events;
    for (const auto &value : source) {
        if (!value.isObject()) { error = "Prepared local calendar contains a non-event"; return false; }
        auto event = value.toObject();
        for (const auto &key : event.keys()) if (!kept.contains(key)) event.remove(key);
        events.append(event);
    }
    if (!validLocalProjection(events, id, error)) return false;
    local = {{"version", 3}, {"events", events}};
    if (QJsonDocument(local).toJson().size() > cacheLimit) { error = "Prepared local calendar exceeds size limit"; return false; }
    return true;
}

bool readConversionPause(const Paths &p, const QString &id, QJsonObject &pause, QString &error) {
    pause = {};
    if (!validId(id)) { error = "Invalid conversion calendar ID"; return false; }
    const auto marker = markerPath(p, id);
    if (!present(marker)) return true;
    if (!jsonFile(marker, pause, error, false)) return false;
    const auto token = pause.value("session").toString(); const auto path = p.data + "/.calendar-convert-" + id + '-' + token;
    if (pause.value("version") != 1 || pause.value("id") != id || !QRegularExpression("^[a-f0-9]{32}$").match(token).hasMatch()
        || pause.value("path") != path || !QFileInfo(path).isDir() || QFileInfo(path).isSymLink()
        || !ensureDirectory(path, error) || !QRegularExpression("^[a-f0-9]{64}$").match(pause.value("revision").toString()).hasMatch()
        || !pause.value("remoteAttempted").isBool() || !pause.value("remoteSucceeded").isBool()) {
        if (error.isEmpty()) error = "Calendar conversion pause is unsafe; inspect retained state: " + marker;
        return false;
    }
    return true;
}
bool conversionAllowed(const Paths &p, const QString &id, QString &error) {
    if (!validId(id)) return true; // Legacy low-level source IDs cannot name a managed conversion.
    if (!remoteDeletionAllowed(p, id, error) || !attachmentAllowed(p, id, error)) return false;
    QJsonObject pause;
    if (!readConversionPause(p, id, pause, error)) return false;
    if (pause.isEmpty()) return true;
    error = "Calendar conversion is paused. Recovery files: " + pause.value("path").toString();
    return false;
}
bool conversion(const Paths &p, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error) {
    if (action == "convert-callback") return callback(p, request, result, error);
    if (action == "list") {
        QJsonArray sessions;
        for (const auto &name : QDir(p.state).entryList({"conversion-*.json"}, QDir::Files | QDir::System | QDir::Hidden)) {
            const auto id = name.mid(11, name.size() - 16); QJsonObject pause, state;
            if (!readConversionPause(p, id, pause, error) || !conflictData(pause, state, error)) return false;
            sessions.append(describe(pause, state));
        }
        result = {{"ok", true}, {"conversions", sessions}}; return true;
    }
    Lease lease;
    if (!lease.acquire(p, error)) return false;
    if (action == "convert-begin") return begin(p, request, result, error);
    const auto id = request.value("id").toString(); QJsonObject pause, data;
    if (!readConversionPause(p, id, pause, error) || pause.isEmpty() || request.value("session") != pause.value("session")
        || request.value("expectedRevision") != pause.value("revision")) {
        if (error.isEmpty()) error = "Conversion session changed; reopen it";
        return false;
    }
    if (action == "convert-finish") return finish(p, request, pause, result, error);
    if (action != "convert-cancel") { error = "Unknown conversion operation"; return false; }
    const auto path = pause.value("path").toString();
    result = {{"ok", false}, {"id", id}, {"paused", true}, {"recoveryPaths", QJsonArray{path}}};
    if (pause.value("remoteAttempted").toBool()) { error = "Remote work was attempted; sync stays paused. Recovery files: " + path; return false; }
    QByteArray timerBytes;
    QJsonObject registry;
    if (!sessionData(pause, data, error) || !loadRegistry(p, registry, error)
        || profileFor(registry, id) != data.value("profile")
        || !readFile(p.units + '/' + data.value("timer").toString(), timerBytes, error, true)
        || timerBytes != data.value("timerBytes").toString().toUtf8()
        || !restoreScheduling(data, error) || !CalendarRemoval::erase(markerPath(p, id), error)) {
        if (error.isEmpty()) error = "Calendar or timer changed; newer state preserved";
        error += "; sync paused. Recovery files: " + path; return false;
    }
    QString cleanupError;
    result = {{"ok", true}, {"id", id}, {"cancelled", true}};
    if (!unchangedReviewFiles(pause, data, cleanupError) || !CalendarRemoval::purge(path, cleanupError)) {
        result["cleanupWarning"] = true; result["recoveryPaths"] = QJsonArray{path};
        result["message"] = "Conversion cancelled; recovery files retained. Retained files: " + path;
    }
    return true;
}
} // namespace CalDavBackend
