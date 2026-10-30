#include "caldav_remote.h"
#include "calendar_json.h"
#include "removal_files.h"
#include "series_group.h"
#include "synced_recurrence.h"
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QUuid>
#include <algorithm>
#include <cmath>
#include <csignal>
#include <limits>
#include <sys/prctl.h>

namespace CalDavBackend {
using namespace SubscriptionBackend;
namespace {
constexpr qint64 dataLimit = 64LL * 1024 * 1024, reviewLimit = 616LL * 1024 * 1024;
bool present(const QString &path) { return QFileInfo::exists(path) || QFileInfo(path).isSymLink(); }
QString markerPath(const Paths &p, const QString &id) { return p.state + "/attachment-" + id + ".json"; }
QString stagePath(const Paths &p, const QJsonObject &op) { return p.data + "/.calendar-attach-" + op.value("id").toString() + '-' + op.value("session").toString(); }
QJsonObject describe(const Paths &p, const QJsonObject &op, const QJsonObject &review);
QJsonObject profileFor(const QJsonObject &registry, const QString &id) {
    for (const auto &value : registry.value("profiles").toArray()) if (value.toObject().value("id") == id) return value.toObject();
    return {};
}
bool save(const Paths &p, QJsonObject &op, QString &error, bool createOnly = false) {
    return ensureDirectory(p.state, error) && writeFile(markerPath(p, op.value("id").toString()), QJsonDocument(op).toJson(), error, createOnly);
}
bool privateJson(const QString &path, QJsonObject &object, QString &error, qint64 limit) {
    struct stat info{};
    if (lstat(QFile::encodeName(path).constData(), &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != geteuid()
        || info.st_nlink != 1 || (info.st_mode & 0777) != 0600) {
        error = "Attachment recovery file is missing or unsafe: " + path; return false;
    }
    return jsonFile(path, object, error, false, limit);
}
bool readReview(const Paths &p, const QJsonObject &op, QJsonObject &review, QString &error) {
    const auto path = stagePath(p, op) + "/review.json";
    if (!privateJson(path, review, error, reviewLimit)) return false;
    const auto digest = revision(QJsonDocument(review).toJson());
    if ((digest != op.value("revision") && digest != op.value("pendingRevision")) || review.value("id") != op.value("id")) {
        error = "Attachment snapshot changed; recovery files preserved"; return false;
    }
    return true;
}
bool saveReview(const Paths &p, QJsonObject &op, const QJsonObject &review, QString &error) {
    const auto bytes = QJsonDocument(review).toJson();
    op["pendingRevision"] = revision(bytes);
    if (!save(p, op, error) || !writeFile(stagePath(p, op) + "/review.json", bytes, error)) return false;
    op["revision"] = op.take("pendingRevision");
    return save(p, op, error);
}
bool clearStage(const Paths &p, QJsonObject &op, QString &error) {
    const auto directory = stagePath(p, op);
    if (!present(directory) && op.value("cleanupReady").toBool())
        return CalendarRemoval::erase(markerPath(p, op.value("id").toString()), error);
    // Never sweep unexpected files supplied by another actor, even in a private session.
    for (const auto &name : QDir(directory).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot)) {
        QByteArray bytes;
        if (QStringList{"seed-data", "seed-status"}.contains(name)) {
            struct stat info{};
            if (lstat(QFile::encodeName(directory + '/' + name).constData(), &info) != 0 || !S_ISDIR(info.st_mode)
                || info.st_uid != geteuid() || (info.st_mode & 0777) != 0700) { error = "Unsafe staging directory retained"; return false; }
            continue;
        }
        const auto expected = op.value("stageFiles").toObject().value(name).toString();
        if (!QStringList{"original.json", "original-live.json", "review.json", "activation.json", "seed.conf", "cache.json"}.contains(name)
            || !readFile(directory + '/' + name, bytes, error, false, reviewLimit)
            || (name == "original.json" && revision(bytes) != op.value("original").toObject().value("digest"))) {
            error = "Unexpected or changed attachment file retained: " + directory + '/' + name; return false;
        }
        if (name == "original-live.json" && revision(bytes) != op.value("original").toObject().value("digest")) {
            error = "Original attachment data changed; retained: " + directory + '/' + name; return false;
        }
        if (name == "review.json" && revision(bytes) != op.value("revision") && revision(bytes) != op.value("pendingRevision")) {
            error = "Changed review retained during cleanup"; return false;
        }
        if (name != "original.json" && name != "original-live.json" && name != "review.json" && (expected.isEmpty() || revision(bytes) != expected)) {
            error = "Attachment staging changed; retained: " + directory + '/' + name; return false;
        }
    }
    const auto files = op.value("stageFiles").toObject();
    for (const auto &root : {QString("seed-data"), QString("seed-status")}) {
        if (!present(directory + '/' + root)) continue;
        QDirIterator entries(directory + '/' + root, QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (entries.hasNext()) {
            const auto path = entries.next(); const auto relative = QDir(directory).relativeFilePath(path);
            struct stat info{};
            if (lstat(QFile::encodeName(path).constData(), &info) != 0 || info.st_uid != geteuid()
                || (!S_ISREG(info.st_mode) && !S_ISDIR(info.st_mode))) { error = "Unsafe attachment staging retained: " + path; return false; }
            if (S_ISDIR(info.st_mode)) {
                if (relative != "seed-data/" + op.value("id").toString()) { error = "Unexpected attachment directory retained: " + path; return false; }
            } else {
                QByteArray bytes;
                if (!files.contains(relative) || !readFile(path, bytes, error, false, dataLimit) || revision(bytes) != files.value(relative)) {
                    error = "Changed attachment staging retained: " + path; return false;
                }
            }
        }
    }
    if (!op.value("syncAttempted").toBool() && !op.value("cleanupReady").toBool()) {
        op["phase"] = "discarding"; op["cleanupReady"] = true;
        if (!save(p, op, error)) return false;
    }
    if (!CalendarRemoval::purge(directory, error)) return false;
    if (!CalendarRemoval::erase(markerPath(p, op.value("id").toString()), error)) return false;
    QDir().rmdir(p.state);
    return true;
}
bool captureStageFiles(const Paths &p, QJsonObject &op, QString &error) {
    const auto directory = stagePath(p, op), id = op.value("id").toString();
    QJsonObject files;
    QDirIterator entries(directory, QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (entries.hasNext()) {
        const auto path = entries.next(), relative = QDir(directory).relativeFilePath(path);
        struct stat info{};
        if (lstat(QFile::encodeName(path).constData(), &info) != 0 || info.st_uid != geteuid() || S_ISLNK(info.st_mode)) {
            error = "Unsafe attachment file: " + path; return false;
        }
        if (S_ISDIR(info.st_mode)) {
            if (!QStringList{"seed-data", "seed-data/" + id, "seed-status"}.contains(relative)) { error = "Unexpected attachment directory: " + path; return false; }
            continue;
        }
        const bool source = relative.startsWith("seed-data/" + id + '/')
            && (QFileInfo(relative).fileName() == "displayname" || relative.endsWith(".ics"));
        bool database = false;
        for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"})
            database = database || relative == "seed-status/qs_caldav_" + id + ".status" + suffix;
        if (!source && !database && !QStringList{"original.json", "original-live.json", "review.json", "activation.json", "seed.conf", "cache.json"}.contains(relative)) {
            error = "Unexpected attachment file: " + path; return false;
        }
        QByteArray bytes;
        if (!S_ISREG(info.st_mode) || info.st_nlink != 1 || (info.st_mode & 0777) != 0600 || !readFile(path, bytes, error, false, reviewLimit)) return false;
        files[relative] = revision(bytes);
    }
    op["stageFiles"] = files;
    return save(p, op, error);
}
bool seededRemote(const Paths &p, QJsonObject &op, RemoteSnapshot &snapshot, QString &error) {
    const auto directory = stagePath(p, op);
    Paths seed = p; seed.data = directory + "/seed-data"; seed.status = directory + "/seed-status"; seed.config = directory + "/seed.conf";
    const auto target = recordFromJson(op.value("target").toObject());
    if (!ensureDirectory(seed.data, error) || !ensureDirectory(seed.status, error)
        || !writeFile(seed.config, renderReadOnlyConfig(seed, target), error)) return false;
    QProcess process;
    const auto parent = getpid();
    process.setChildProcessModifier([parent] { if (prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent) _exit(1); });
    process.setStandardOutputFile(QProcess::nullDevice()); process.setStandardErrorFile(QProcess::nullDevice());
    process.start("pimsync", {"-c", seed.config, "sync", target.pair()});
    bool ok = process.waitForStarted(5000) && process.waitForFinished(90000) && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
    if (!ok) { process.kill(); process.waitForFinished(5000); }
    if (!captureStageFiles(p, op, error)) return false;
    if (!ok) { error = "Read-only remote preparation failed; original local calendar unchanged"; return false; }
    const auto sources = seed.data + '/' + target.id;
    if (!QFileInfo(sources).isDir() || !present(seed.status + '/' + target.pair() + ".status")) { error = "Remote collection is unavailable; original local calendar unchanged"; return false; }
    QJsonObject encoded;
    for (const auto &name : QDir(sources).entryList({"*.ics"}, QDir::Files)) {
        QByteArray raw;
        if (!readFile(sources + '/' + name, raw, error, false, 16 * 1024 * 1024)) return false;
        snapshot.resources[name] = raw;
        encoded[name] = QString::fromLatin1(raw.toBase64());
    }
    snapshot.fingerprint = revision(QJsonDocument(encoded).toJson());
    return true;
}
QString inode(const struct stat &value) { return QString::number(value.st_dev) + ':' + QString::number(value.st_ino); }
bool unchangedFile(const QString &path, const QString &digest, QString &error) {
    QByteArray bytes;
    if (!readFile(path, bytes, error, false, reviewLimit) || revision(bytes) != digest) {
        error = "Changed attachment resource preserved: " + path; return false;
    }
    return true;
}
bool activationData(const Paths &p, const QJsonObject &op, QJsonObject &data, QString &error) {
    if (!privateJson(stagePath(p, op) + "/activation.json", data, error, reviewLimit)
        || revision(QJsonDocument(data).toJson()) != op.value("activationDigest")) {
        if (error.isEmpty()) error = "Attachment activation record changed";
        return false;
    }
    const QSet<QString> units{"pimsync.service", "pimsync.service.d/calendar-group-recovery.conf", "pimsync.service.d/calendar-caldav.conf",
        "quickshell-calendar-caldav@.service", "quickshell-calendar-caldav-" + op.value("id").toString() + ".timer"};
    for (const auto &name : data.value("units").toObject().keys()) if (!units.contains(name)) { error = "Attachment unit record is invalid"; return false; }
    for (const auto &suffix : data.value("databases").toObject().keys()) if (!QStringList{"", "-wal", "-shm", "-journal"}.contains(suffix)) {
        error = "Attachment database record is invalid"; return false;
    }
    return true;
}
bool restoreProfile(const Paths &p, const QJsonObject &op, const QJsonObject &data, QString &error) {
    QJsonObject registry;
    if (!loadRegistry(p, registry, error)) return false;
    auto original = op.value("profile").toObject(), synced = original; synced["type"] = "synced";
    const auto actual = profileFor(registry, original.value("id").toString());
    if (actual != original && actual != synced) { error = "Newer calendar profile preserved; recovery required"; return false; }
    if (actual == original) return true;
    QJsonArray profiles;
    for (const auto &value : registry.value("profiles").toArray()) profiles.append(value.toObject().value("id") == original.value("id") ? QJsonValue(original) : value);
    registry["profiles"] = profiles;
    const auto before = QByteArray::fromBase64(data.value("registryBefore").toString().toLatin1());
    if (QJsonDocument::fromJson(before).object() == registry) return writeFile(p.data + "/profiles.json", before, error);
    return writeFile(p.data + "/profiles.json", QJsonDocument(registry).toJson(), error);
}
bool rollback(const Paths &p, QJsonObject &op, QString &error) {
    if (op.value("syncAttempted").toBool()) { error = "Synchronization may have started; local rollback refused"; return false; }
    QJsonObject data;
    if (!activationData(p, op, data, error)) return false;
    const auto id = op.value("id").toString(), stage = stagePath(p, op), active = p.data + '/' + id;
    const auto digest = op.value("original").toObject().value("digest").toString();
    if (present(p.data + '/' + id + ".json")) {
        if (!unchangedFile(p.data + '/' + id + ".json", digest, error)) return false;
    } else if (!unchangedFile(stage + "/original-live.json", digest, error)
        || !CalendarRemoval::move(stage + "/original-live.json", p.data + '/' + id + ".json", error)) return false;
    if (!restoreProfile(p, op, data, error)) return false;
    Config config;
    if (!loadConfig(p, config, error)) return false;
    const auto before = QByteArray::fromBase64(data.value("configBefore").toString().toLatin1());
    const auto after = QByteArray::fromBase64(data.value("configAfter").toString().toLatin1());
    if (config.original == after) {
        if (data.value("configExisted").toBool()) {
            if (!writeFile(p.config, before, error)) return false;
        } else if (!CalendarRemoval::erase(p.config, error)) return false;
    } else if (config.original != before) {
        auto records = config.records;
        for (int i = records.size() - 1; i >= 0; --i) if (records[i].id == id) {
            if (recordJson(records[i]) != op.value("target")) { error = "Changed sync target preserved during rollback"; return false; }
            records.removeAt(i);
        }
        if (!writeFile(p.config, renderConfig(p, config, records), error)) return false;
    }
    const auto definitions = data.value("units").toObject();
    for (auto it = definitions.begin(); it != definitions.end(); ++it) {
        const auto path = p.units + '/' + it.key();
        const auto entry = it.value().toObject();
        const auto old = QByteArray::fromBase64(entry.value("before").toString().toLatin1());
        QByteArray actual;
        if (!readFile(path, actual, error, true, dataLimit)) return false;
        if (present(path) && (!entry.value("existed").toBool() || actual != old) && revision(actual) != entry.value("after")) {
            error = "Newer unit preserved: " + path; return false;
        }
        if (present(path) && revision(actual) == entry.value("after")) {
            if (entry.value("existed").toBool()) {
                if (!CalendarRemoval::publish(path, old, mode_t(entry.value("mode").toInt()), error)) return false;
            } else if (!CalendarRemoval::erase(path, error)) return false;
        }
    }
    if (present(active)) {
        struct stat info{};
        if (lstat(QFile::encodeName(active).constData(), &info) != 0 || !S_ISDIR(info.st_mode) || inode(info) != data.value("directoryIdentity")) {
            error = "Changed canonical collection preserved during rollback"; return false;
        }
        const auto files = data.value("sources").toObject();
        for (const auto &name : QDir(active).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot)) {
            if (!files.contains(name) || !unchangedFile(active + '/' + name, files.value(name).toString(), error)) return false;
        }
        if (!CalendarRemoval::purge(active, error)) return false;
    }
    const auto cache = p.data + '/' + id + ".sync.json";
    if (present(cache) && (!unchangedFile(cache, data.value("cacheDigest").toString(), error) || !CalendarRemoval::erase(cache, error))) return false;
    const auto databases = data.value("databases").toObject();
    for (auto it = databases.begin(); it != databases.end(); ++it) {
        const auto path = p.status + "/qs_caldav_" + id + ".status" + it.key();
        if (present(path) && (!unchangedFile(path, it.value().toString(), error) || !CalendarRemoval::erase(path, error))) return false;
    }
    QJsonObject status;
    if (!jsonFile(p.state + "/status.json", status, error)) return false;
    if (!status.isEmpty()) {
        auto records = status.value("records").toObject();
        if (data.value("statusBefore").isObject()) records[id] = data.value("statusBefore"); else records.remove(id);
        if (records.isEmpty() && !data.value("statusExisted").toBool()) {
            if (!CalendarRemoval::erase(p.state + "/status.json", error)) return false;
        } else { status["records"] = records; if (!writeFile(p.state + "/status.json", QJsonDocument(status).toJson(), error)) return false; }
    }
    if (!command("systemctl", {"--user", "daemon-reload"}, 15000) || !resumeDaemon(data.value("daemonActive").toBool(), error)) {
        if (error.isEmpty()) error = "Could not restore scheduling after attachment failure";
        return false;
    }
    return clearStage(p, op, error);
}
bool install(const Paths &p, QJsonObject &op, QJsonObject &review, QString &error) {
    const auto id = op.value("id").toString(), stage = stagePath(p, op), mirror = stage + "/seed-data/" + id;
    const auto target = recordFromJson(op.value("target").toObject());
    QMap<QString, QByteArray> selected;
    if (!projectRemoteSources(id, review, op.value("choices").toArray(), selected, error)) return false;
    QMap<QString, QString> names;
    for (const auto &name : QDir(mirror).entryList({"*.ics"}, QDir::Files)) {
        QByteArray raw;
        if (!readFile(mirror + '/' + name, raw, error, false, 16 * 1024 * 1024)) return false;
        const auto parsed = parseCalendar(raw.toStdString());
        if (!parsed.error.empty() || parsed.events.size() != 1) { error = "Read-only baseline contains invalid ICS"; return false; }
        const auto uid = QString::fromStdString(parsed.events.front().uid);
        if (names.contains(uid)) { error = "Read-only baseline has duplicate event identity"; return false; }
        names[uid] = name;
        if (!selected.contains(uid) && !CalendarRemoval::erase(mirror + '/' + name, error)) return false;
    }
    for (auto it = selected.begin(); it != selected.end(); ++it) {
        const auto name = names.value(it.key(), revision(it.key().toUtf8()) + ".ics");
        QByteArray current;
        if (!readFile(mirror + '/' + name, current, error, true, 16 * 1024 * 1024)) return false;
        std::string detail;
        if (current != it.value() && !writeAtomicallyFile((mirror + '/' + name).toStdString(), it.value().toStdString(), detail)) {
            error = QString::fromStdString(detail); return false;
        }
    }
    std::string detail;
    if (!rebuildSyncedCache(mirror.toStdString(), (stage + "/cache.json").toStdString(), id.toStdString(), detail, true)
        || !validateSyncedCache((stage + "/cache.json").toStdString(), id.toStdString(), detail)) {
        error = QString::fromStdString(detail); return false;
    }
    if (!captureStageFiles(p, op, error)) return false;
    Config config; QJsonObject registry, statuses;
    if (!loadConfig(p, config, error) || !loadRegistry(p, registry, error) || !jsonFile(p.state + "/status.json", statuses, error)) return false;
    if (revision(config.original) != op.value("configRevision")) { error = "Calendar configuration changed; reopen attachment"; return false; }
    if (profileFor(registry, id) != op.value("profile")) { error = "Local profile changed before activation"; return false; }
    for (const auto &record : config.records) if (record.id == id || remoteIdentity(record) == remoteIdentity(target)) {
        error = "Remote calendar was added while conversion was under review"; return false;
    }
    Config next = config; next.records.append(target);
    const auto statusLine = "status_path " + quoted(p.status) + '\n';
    if (!QRegularExpression("(?m)^\\s*status_path\\s+").match(QString::fromUtf8(next.prefix + next.suffix)).hasMatch()) {
        if (!next.prefix.isEmpty() && !next.prefix.endsWith('\n')) next.prefix += '\n';
        next.prefix += statusLine.toUtf8();
    } else if (!QRegularExpression("(?m)^\\s*status_path\\s+\"?" + QRegularExpression::escape(p.status) + "/?\"?\\s*$")
                   .match(QString::fromUtf8(next.prefix + next.suffix)).hasMatch()) {
        error = "Attachment requires standard pimsync status directory; custom policy preserved"; return false;
    }
    const auto definitions = unitDefinitions(p, next), oldDefinitions = unitDefinitions(p, config);
    QJsonObject units, sources, databases;
    for (auto it = definitions.begin(); it != definitions.end(); ++it) {
        const auto path = p.units + '/' + it.key();
        QByteArray before;
        if (!readFile(path, before, error, true, dataLimit)) return false;
        if (before == it.value()) continue;
        if (present(path)) {
            if (it.key() == "pimsync.service" && before.contains("ExecStart=/usr/bin/pimsync daemon\n")) continue;
            if (it.key() == "pimsync.service.d/calendar-group-recovery.conf" && before == it.value().mid(it.value().indexOf("[Service]"))) continue;
            if (before != oldDefinitions.value(it.key())) { error = "Custom unit preserved: " + path; return false; }
        }
        struct stat info{};
        const auto mode = lstat(QFile::encodeName(path).constData(), &info) == 0 ? int(info.st_mode & 0777) : 0600;
        units[it.key()] = QJsonObject{{"before", QString::fromLatin1(before.toBase64())}, {"existed", present(path)},
            {"mode", mode}, {"after", revision(it.value())}};
    }
    struct stat directoryInfo{};
    if (lstat(QFile::encodeName(mirror).constData(), &directoryInfo) != 0 || !S_ISDIR(directoryInfo.st_mode)) return false;
    for (const auto &name : QDir(mirror).entryList(QDir::Files | QDir::Hidden)) {
        QByteArray bytes;
        if (!readFile(mirror + '/' + name, bytes, error, false, dataLimit)) return false;
        sources[name] = revision(bytes);
    }
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) {
        const auto from = stage + "/seed-status/" + target.pair() + ".status" + suffix;
        if (!present(from)) continue;
        QByteArray bytes;
        if (!readFile(from, bytes, error, false, dataLimit) || present(p.status + '/' + target.pair() + ".status" + suffix)) {
            error = "Sync database destination is occupied or unsafe"; return false;
        }
        databases[suffix] = revision(bytes);
    }
    if (!databases.contains("")) { error = "Read-only sync baseline database is missing"; return false; }
    QString daemonState;
    if (!CalendarRemoval::property("pimsync.service", "ActiveState", daemonState, error)) return false;
    if (daemonState != "active" && daemonState != "inactive" && daemonState != "failed") { error = "Calendar daemon is busy; retry conversion"; return false; }
    QByteArray registryBytes;
    if (!readFile(p.data + "/profiles.json", registryBytes, error, false, dataLimit) || QJsonDocument::fromJson(registryBytes).object() != registry) {
        error = "Calendar registry changed before activation"; return false;
    }
    const bool configExisted = present(p.config);
    QJsonObject data{{"configBefore", QString::fromLatin1(config.original.toBase64())}, {"configExisted", configExisted}, {"registryBefore", QString::fromLatin1(registryBytes.toBase64())},
        {"configAfter", QString::fromLatin1(renderConfig(p, next, next.records).toBase64())}, {"units", units}, {"sources", sources},
        {"directoryIdentity", inode(directoryInfo)}, {"databases", databases}, {"daemonActive", daemonState == "active"},
        {"cacheDigest", op.value("stageFiles").toObject().value("cache.json")}, {"statusExisted", present(p.state + "/status.json")},
        {"statusBefore", statuses.value("records").toObject().value(id)}};
    const auto bytes = QJsonDocument(data).toJson();
    if (!writeFile(stage + "/activation.json", bytes, error, true)) return false;
    op["activationDigest"] = revision(bytes);
    if (!captureStageFiles(p, op, error)) return false;
    op["phase"] = "activating";
    if (!save(p, op, error)) return false;
    bool wasActive = false;
    if (!pauseDaemon(wasActive, error)) return false;
    if (!ensureDirectory(p.status, error)) return false;
    for (auto it = units.begin(); it != units.end(); ++it) {
        const auto path = p.units + '/' + it.key();
        QByteArray actual;
        if (!readFile(path, actual, error, true, dataLimit) || actual != QByteArray::fromBase64(it.value().toObject().value("before").toString().toLatin1())) {
            error = "Unit changed during activation; newer data retained"; return false;
        }
        if (!ensureDirectory(QFileInfo(path).path(), error) || !writeFile(path, definitions.value(it.key()), error, !it.value().toObject().value("existed").toBool())) return false;
    }
    QByteArray currentConfig;
    if (!readFile(p.config, currentConfig, error, true, dataLimit) || currentConfig != config.original || present(p.config) != configExisted) {
        error = "Calendar configuration changed before activation"; return false;
    }
    if (!ensureDirectory(QFileInfo(p.config).path(), error) || !writeFile(p.config, renderConfig(p, next, next.records), error, !configExisted)
        || !CalendarRemoval::move(mirror, p.data + '/' + id, error)
        || !CalendarRemoval::move(stage + "/cache.json", p.data + '/' + id + ".sync.json", error)) return false;
    for (auto it = databases.begin(); it != databases.end(); ++it)
        if (!CalendarRemoval::move(stage + "/seed-status/" + target.pair() + ".status" + it.key(), p.status + '/' + target.pair() + ".status" + it.key(), error)) return false;
    if (!command("systemctl", {"--user", "daemon-reload"}, 15000) || !verifyManagedDaemon(p, error)) {
        if (error.isEmpty()) error = "Could not load activated calendar units";
        return false;
    }
    if (!unchangedFile(p.data + '/' + id + ".json", op.value("original").toObject().value("digest").toString(), error)
        || !CalendarRemoval::move(p.data + '/' + id + ".json", stage + "/original-live.json", error)) return false;
    QJsonObject latest;
    if (!loadRegistry(p, latest, error) || profileFor(latest, id) != op.value("profile")) { error = "Profile changed during activation"; return false; }
    auto synced = op.value("profile").toObject(); synced["type"] = "synced";
    QJsonArray profiles;
    for (const auto &value : latest.value("profiles").toArray()) profiles.append(value.toObject().value("id") == id ? QJsonValue(synced) : value);
    latest["profiles"] = profiles;
    if (!writeFile(p.data + "/profiles.json", QJsonDocument(latest).toJson(), error)) return false;
    op["activated"] = true;
    return save(p, op, error);
}
bool finishCleanup(const Paths &p, QJsonObject &op, const QJsonObject &review, QJsonObject &result, QString &error) {
    const auto id = op.value("id").toString(), syncError = op.value("syncError").toString();
    const bool synced = op.value("syncSucceeded").toBool();
    QString cleanup;
    bool ready = true;
    if (!op.value("cleanupReady").toBool()) {
        QJsonObject data;
        if (!activationData(p, op, data, error)) return false;
        const auto timer = "quickshell-calendar-caldav-" + id + ".timer";
        ready = command("systemctl", {"--user", "enable", "--now", timer}, 30000);
        if (!ready) cleanup = "Could not enable calendar timer";
        QString daemonError;
        if (!resumeDaemon(data.value("daemonActive").toBool(), daemonError)) {
            ready = false;
            cleanup += (cleanup.isEmpty() ? "" : "; ") + daemonError;
        }
        std::string detail;
        if (ready && !validateSyncedCache((p.data + '/' + id + ".sync.json").toStdString(), id.toStdString(), detail)) { ready = false; cleanup = QString::fromStdString(detail); }
        if (ready) {
            op["cleanupReady"] = true;
            if (!save(p, op, cleanup)) ready = false;
        }
    }
    if (ready && !clearStage(p, op, cleanup)) ready = false;
    result = {{"ok", synced && ready}, {"id", id}, {"kind", "local-to-synced"}, {"converted", true}, {"syncAttempted", true},
        {"completed", ready}, {"syncError", !synced}};
    if (!ready) {
        result = describe(p, op, review); result["ok"] = false; result["converted"] = true;
        error = (syncError.isEmpty() ? QString("Calendar activated") : syncError) + "; cleanup pending: " + cleanup;
    } else if (!synced) error = syncError + "; calendar remains synced. Refresh to retry; review conflicts if shown.";
    else error.clear();
    return synced && ready;
}
bool complete(const Paths &p, QJsonObject op, QJsonObject review, QJsonObject &result, QString &error) {
    const bool previouslyAttempted = op.value("syncAttempted").toBool();
    auto fail = [&](const QString &cause) {
        QString cleanup;
        bool cleaned;
        if (op.contains("activationDigest")) cleaned = rollback(p, op, cleanup);
        else cleaned = clearStage(p, op, cleanup);
        if (!cleaned && op.contains("activationDigest")) {
            Config current; QJsonObject data; QString restoreError;
            if (loadConfig(p, current, restoreError) && activationData(p, op, data, restoreError)
                && std::none_of(current.records.begin(), current.records.end(), [&](const auto &record) { return record.id == op.value("id").toString(); })) {
                if (!command("systemctl", {"--user", "daemon-reload"}, 15000) || !resumeDaemon(data.value("daemonActive").toBool(), restoreError))
                    cleanup += "; unrelated daemon restoration pending: " + restoreError;
            }
        }
        result = describe(p, op, review); result["ok"] = false;
        if (cleaned) { result["cancelled"] = true; result["recoveryPaths"] = QJsonArray{}; }
        error = cause + (cleaned ? "" : "; cleanup pending: " + cleanup);
        return false;
    };
    if (!op.value("activated").toBool() && !install(p, op, review, error)) return fail(error);
    const auto target = recordFromJson(op.value("target").toObject());
    op["phase"] = "syncing"; op["syncAttempted"] = true; op["pid"] = int(getpid());
    if (!save(p, op, error)) {
        if (!previouslyAttempted) { op["syncAttempted"] = false; return fail(error); }
        result = describe(p, op, review); result["ok"] = false; result["converted"] = true;
        return false;
    }
    bool started = false;
    const bool synced = syncAttachmentRecord(p, target, op.value("session").toString(), started, error);
    if (!started && !previouslyAttempted) {
        op["syncAttempted"] = false; op["phase"] = "activating";
        QString ignored; save(p, op, ignored);
        return fail(error.isEmpty() ? "Could not start initial synchronization" : error);
    }
    const auto syncError = error;
    op["phase"] = "cleanup"; op["syncSucceeded"] = synced; op["syncError"] = syncError; op["pid"] = 0;
    if (!save(p, op, error)) {
        result = describe(p, op, review); result["ok"] = false; result["converted"] = true;
        return false;
    }
    return finishCleanup(p, op, review, result, error);
}
bool decodeSources(const QJsonObject &encoded, QMap<QString, QByteArray> &sources, QString &error) {
    qint64 total = 0;
    for (auto it = encoded.begin(); it != encoded.end(); ++it) {
        const auto decoded = QByteArray::fromBase64Encoding(it.value().toString().toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
        total += decoded.decoded.size();
        if (!it.value().isString() || !decoded || decoded.decoded.isEmpty() || decoded.decoded.size() > 16 * 1024 * 1024 || total > dataLimit) {
            error = "Attachment ICS snapshot is invalid or too large"; return false;
        }
        sources[it.key()] = decoded.decoded;
    }
    return true;
}
bool localSources(const QString &id, const QJsonObject &document, QMap<QString, QByteArray> &sources, QString &error) {
    const auto version = document.value("version");
    if (document.size() != 2 || !QList<int>{1, 2, 3}.contains(version.toInt()) || version.toDouble() != version.toInt()
        || !document.value("events").isArray()) { error = "Local calendar schema is unsupported"; return false; }
    QSet<QString> logicalIds, sourceIds;
    std::vector<Event> parsed;
    QMap<QString, QJsonObject> originals;
    qint64 total = 0;
    for (const auto &value : document.value("events").toArray()) {
        auto event = value.toObject();
        const QSet<QString> required{"uid", "calendarId", "title", "description", "location", "start", "end", "allDay", "reminders"};
        auto allowed = required;
        if (version.toInt() >= 2) allowed.unite({"timezone", "recurrence"});
        if (version.toInt() == 3) allowed.unite({"ical", "readOnly"});
        for (const auto &key : event.keys()) if (!allowed.contains(key)) { error = "Local calendar event schema is invalid"; return false; }
        for (const auto &key : required) if (!event.contains(key)) { error = "Local event field is missing"; return false; }
        for (const auto &key : {"uid", "calendarId", "title", "description", "location", "start", "end"})
            if (!event.value(key).isString()) { error = "Local event text fields are invalid"; return false; }
        const auto originalUid = event.value("uid").toString();
        auto uid = originalUid.startsWith(id + ':') ? originalUid.mid(id.size() + 1) : originalUid;
        if (event.value("calendarId") != id || !event.value("allDay").isBool() || !event.value("reminders").isArray()
            || !QRegularExpression("^[A-Za-z0-9@_.:-]{1,256}$").match(uid).hasMatch() || logicalIds.contains(uid)
            || event.contains("readOnly") != event.contains("ical")
            || (event.contains("readOnly") && event.value("readOnly") != true)
            || (event.contains("timezone") && !event.value("timezone").isString())) {
            error = "Local event identity or metadata is invalid or ambiguous"; return false;
        }
        QSet<int> reminders;
        for (const auto &reminder : event.value("reminders").toArray()) {
            const auto object = reminder.toObject(); const auto number = object.value("minutesBefore");
            const auto count = number.toDouble(-1);
            if (!reminder.isObject() || object.size() != 1 || !number.isDouble() || !std::isfinite(count) || count < 0
                || count > std::numeric_limits<int>::max() || count != std::floor(count) || reminders.contains(int(count))) {
                error = "Local reminders must contain unique nonnegative whole minutes"; return false;
            }
            reminders.insert(int(count));
        }
        event["uid"] = uid;
        QMap<QString, QByteArray> members;
        if (event.contains("ical")) {
            const auto raw = event.value("ical").toString().toUtf8();
            const auto decoded = parseCalendar(raw.toStdString());
            if (!event.value("ical").isString() || event.value("readOnly") != true || event.contains("recurrence") || event.contains("timezone")
                || raw.size() > 16 * 1024 * 1024 || !decoded.error.empty() || decoded.events.size() != 1) {
                error = "Local opaque ICS is invalid"; return false;
            }
            const auto actual = QString::fromStdString(decoded.events.front().uid);
            if (originalUid != actual && originalUid != id + ':' + actual) { error = "Local opaque ICS identity differs from its wrapper"; return false; }
            uid = actual;
            if (logicalIds.contains(uid)) { error = "Local ICS identity collides after mapping"; return false; }
            event["uid"] = uid;
            members[uid] = raw;
        } else if (event.value("recurrence").toObject().value("frequency") == "yearly"
            && event.value("recurrence").toObject().value("pattern").toObject().value("dates").toArray().size() > 1) {
            QJsonObject built;
            if (!buildSeriesGroup(event, built, error)) return false;
            for (const auto &member : built.value("members").toArray())
                members[member.toObject().value("uid").toString()] = member.toObject().value("ical").toString().toUtf8();
        } else {
            Event generated; std::string detail;
            if (!syncedEventFromJson(event, generated, detail)) { error = QString::fromStdString(detail); return false; }
            members[uid] = QByteArray::fromStdString(serializeEvent(generated));
        }
        logicalIds.insert(uid);
        event["uid"] = id + ':' + uid;
        originals[uid] = event;
        for (auto it = members.begin(); it != members.end(); ++it) {
            total += it.value().size();
            if (sourceIds.contains(it.key()) || total > dataLimit) { error = "Local source identities collide or exceed size limit"; return false; }
            sourceIds.insert(it.key());
            const auto result = parseCalendar(it.value().toStdString());
            if (!result.error.empty() || result.events.size() != 1) { error = "Local ICS export cannot be read back"; return false; }
            parsed.insert(parsed.end(), result.events.begin(), result.events.end());
            sources[it.key()] = it.value();
        }
    }
    const auto cache = QJsonDocument::fromJson(QByteArray::fromStdString(serializeSyncedCalendar(parsed, id.toStdString()))).object();
    if (!cache.value("warnings").toArray().isEmpty() || cache.value("events").toArray().size() != originals.size()) {
        error = "Local ICS export cannot preserve every event"; return false;
    }
    for (const auto &value : cache.value("events").toArray()) {
        auto restored = value.toObject(); const auto uid = restored.value("sourceUid").toString();
        auto original = originals.value(uid);
        for (const auto &key : {"sourceUid", "revision", "seriesGroup"}) restored.remove(key);
        // Opaque bytes are retained verbatim; their modeled preview must still agree.
        for (const auto &key : {"ical", "readOnly"}) { restored.remove(key); original.remove(key); }
        if (!original.value("allDay").toBool()) for (const auto &key : {"start", "end"}) {
            static const QRegularExpression nonzeroFraction("[.,][0-9]*[1-9]");
            const auto beforeText = original.value(key).toString();
            const auto before = QDateTime::fromString(beforeText, Qt::ISODate);
            const auto after = QDateTime::fromString(restored.value(key).toString(), Qt::ISODate);
            if (before.isValid() && after.isValid() && before == after && !beforeText.contains(nonzeroFraction)) original[key] = restored.value(key);
        }
        if (restored != original) { error = "Local event cannot round-trip to ICS without changing data: " + uid; return false; }
    }
    return true;
}
QJsonObject describe(const Paths &p, const QJsonObject &op, const QJsonObject &review) {
    return {{"ok", true}, {"kind", "local-to-synced"}, {"id", op.value("id")}, {"session", op.value("session")},
        {"phase", op.value("phase")}, {"revision", op.value("revision")}, {"profile", op.value("profile")},
        {"conflicts", review.value("conflicts").toArray()}, {"choices", op.value("choices")}, {"syncAttempted", op.value("syncAttempted")},
        {"recoveryPaths", QJsonArray{markerPath(p, op.value("id").toString()), stagePath(p, op)}}};
}
bool begin(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    const auto id = request.value("id").toString();
    result = {{"ok", false}, {"id", id}};
    Config config; QJsonObject registry, stamp;
    if (!validId(id) || !conversionAllowed(p, id, error) || !attachmentAllowed(p, id, error)
        || !loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    const auto profile = profileFor(registry, id);
    if (profile.value("type") != "local" || profile != request.value("expectedProfile") || revision(config.original) != request.value("expectedRevision")) {
        error = "Local calendar settings changed; reopen conversion"; return false;
    }
    QByteArray bytes;
    if (!remoteFileStamp(p.data + '/' + id + ".json", stamp, error, &bytes, dataLimit)) return false;
    QJsonParseError parse;
    const auto document = QJsonDocument::fromJson(bytes, &parse);
    QMap<QString, QByteArray> sources;
    if (parse.error != QJsonParseError::NoError || !document.isObject() || !localSources(id, document.object(), sources, error)) {
        if (error.isEmpty()) error = "Local calendar JSON is malformed";
        return false;
    }
    Record target = recordFromJson(request); target.id = id;
    if (request.contains("createRemote") && !request.value("createRemote").isBool()) {
        error = "Remote creation intent must be explicit"; return false;
    }
    const bool creating = request.value("createRemote").toBool();
    const auto home = request.value("homeHref").toString();
    const auto name = request.value("remoteName").toString(), identifier = request.value("collectionId").toString();
    if (creating) {
        if (!validId(identifier) || !validRemoteName(name)) {
            error = "Use a valid collection identifier and single-line remote name (maximum 512 characters)"; return false;
        }
        target.remoteId = identifier;
        target.remoteHref = home + identifier + '/';
    }
    const auto interval = request.value("intervalSeconds");
    if (!interval.isDouble() || interval.toDouble() != interval.toInt(-1) || interval.toInt() < 300 || !validIdentity(target)) {
        error = "Choose a discovered remote calendar and an interval of at least 5 minutes"; return false;
    }
    if (creating && !validateConnection(target, error)) return false;
    for (const auto &record : config.records) if (record.id == id || remoteIdentity(record) == remoteIdentity(target)) {
        error = "Remote calendar has already been added"; return false;
    }
    const auto unmanaged = QString::fromUtf8(config.prefix + config.suffix);
    if (unmanaged.contains(quoted(target.url)) || unmanaged.contains("url " + target.url)
        || QRegularExpression("(?m)^\\s*(?:pair|collection|collection_id|id_a|id_b|alias)\\s+\"?" + QRegularExpression::escape(id) + "\"?(?=\\s|[{}]|$)").match(unmanaged).hasMatch()
        || (QRegularExpression("(?m)^\\s*collections\\s+").match(unmanaged).hasMatch() && unmanaged.contains(p.data))) {
        error = "Manual configuration may already manage this calendar"; return false;
    }
    for (const auto &path : QStringList{p.data + '/' + id, p.data + '/' + id + ".sync.json", p.status + '/' + target.pair() + ".status"})
        if (present(path)) { error = "Retained sync resources collide with local conversion"; return false; }
    if (creating) {
        const auto outcome = createRemoteCollection(target, home, name, identifier, error);
        result["remoteId"] = target.remoteId; result["remoteHref"] = target.remoteHref; result["homeHref"] = home;
        if (outcome == RemoteOutcome::Refused) return false;
        if (outcome == RemoteOutcome::Uncertain) {
            result["creationUncertain"] = true;
            error = "Remote creation outcome is uncertain; local calendar is unchanged. Connect and select the exact remote calendar before attachment; do not repeat creation automatically.";
            return false;
        }
        result["remoteCreated"] = true;
    }
    RemoteSnapshot remote; QJsonObject review; QJsonArray conflicts;
    if (!snapshotRemote(target, remote, error) || !buildRemoteReview(target, sources, remote, review, conflicts, error)) return false;
    QJsonObject op{{"version", 1}, {"kind", "local-to-synced"}, {"id", id}, {"session", QUuid::createUuid().toString(QUuid::Id128)},
        {"phase", "review"}, {"profile", profile}, {"target", recordJson(target)}, {"configRevision", revision(config.original)},
        {"original", stamp}, {"revision", revision(QJsonDocument(review).toJson())}, {"choices", QJsonArray{}}, {"syncAttempted", false}};
    const auto directory = stagePath(p, op);
    if (::mkdir(QFile::encodeName(directory).constData(), 0700) != 0) { error = "Could not create private attachment staging"; return false; }
    if (!writeFile(directory + "/original.json", bytes, error, true) || !writeFile(directory + "/review.json", QJsonDocument(review).toJson(), error, true)
        || !save(p, op, error, true)) {
        QString cleanup;
        if (!CalendarRemoval::purge(directory, cleanup)) error += "; retained staging: " + cleanup;
        return false;
    }
    result = describe(p, op, review);
    if (creating) {
        result["remoteCreated"] = true;
        result["remoteId"] = target.remoteId; result["remoteHref"] = target.remoteHref; result["homeHref"] = home;
    }
    return true;
}
bool finish(const Paths &p, const QJsonObject &request, QJsonObject op, QJsonObject review, QJsonObject &result, QString &error) {
    const auto id = op.value("id").toString();
    QJsonObject registry, current;
    if (!loadRegistry(p, registry, error)) return false;
    if (!remoteFileStamp(p.data + '/' + id + ".json", current, error, nullptr, dataLimit) || current != op.value("original")
        || profileFor(registry, id) != op.value("profile")) {
        const auto cause = QString("Local calendar changed; conversion cancelled without overwriting newer data");
        QString cleanup;
        if (!clearStage(p, op, cleanup)) { result = describe(p, op, review); result["ok"] = false; error = cause + "; " + cleanup; }
        else { error = cause; result["cancelled"] = true; result["recoveryPaths"] = QJsonArray{}; }
        return false;
    }
    QMap<QString, QByteArray> selected, local;
    if (!request.value("choices").isArray() || !projectRemoteSources(id, review, request.value("choices").toArray(), selected, error)
        || !decodeSources(review.value("localSources").toObject(), local, error)) return false;
    RemoteSnapshot remote; QJsonObject next; QJsonArray conflicts;
    remote.homeHref = review.value("homeHref").toString();
    if (!seededRemote(p, op, remote, error)
        || !buildRemoteReview(recordFromJson(op.value("target").toObject()), local, remote, next, conflicts, error)) {
        const auto cause = error; QString cleanup;
        result = describe(p, op, review); result["ok"] = false;
        if (!clearStage(p, op, cleanup)) error = cause + "; cleanup pending: " + cleanup;
        else { result["cancelled"] = true; result["recoveryPaths"] = QJsonArray{}; }
        return false;
    }
    QJsonArray retained;
    for (const auto &value : request.value("choices").toArray()) {
        const auto choice = value.toObject();
        for (const auto &conflict : conflicts) if (conflict.toObject().value("uid") == choice.value("uid") && conflict.toObject().value("revision") == choice.value("revision"))
            retained.append(choice);
    }
    const bool changed = next != review;
    op["choices"] = retained;
    if (!saveReview(p, op, next, error)) return false;
    result = describe(p, op, next);
    result["reviewChanged"] = changed;
    if (retained.size() != conflicts.size()) return true;
    return complete(p, op, next, result, error);
}
} // namespace

bool readAttachment(const Paths &p, const QString &id, QJsonObject &op, QString &error) {
    op = {};
    if (!validId(id)) { error = "Invalid attachment ID"; return false; }
    const auto marker = markerPath(p, id);
    if (!present(marker)) {
        if (!QDir(p.data).entryList({".calendar-attach-" + id + '-' + QString(32, '?')}, QDir::AllEntries | QDir::Hidden | QDir::System).isEmpty()) {
            error = "Attachment recovery marker is missing; retained staging requires inspection"; return false;
        }
        return true;
    }
    if (!privateJson(marker, op, error, dataLimit)) return false;
    struct stat info{};
    if (op.value("version") != 1 || op.value("kind") != "local-to-synced" || op.value("id") != id
        || !QRegularExpression("^[a-f0-9]{32}$").match(op.value("session").toString()).hasMatch()
        || !QRegularExpression("^[a-f0-9]{64}$").match(op.value("revision").toString()).hasMatch()
        || !QStringList{"review", "activating", "syncing", "cleanup", "discarding"}.contains(op.value("phase").toString())
        || !op.value("syncAttempted").isBool() || op.value("profile").toObject().value("id") != id
        || op.value("profile").toObject().value("type") != "local" || recordFromJson(op.value("target").toObject()).id != id
        || !validIdentity(recordFromJson(op.value("target").toObject()))
        || ((!op.value("cleanupReady").toBool() || present(stagePath(p, op)))
            && (lstat(QFile::encodeName(stagePath(p, op)).constData(), &info) != 0
                || !S_ISDIR(info.st_mode) || info.st_uid != geteuid() || (info.st_mode & 0777) != 0700))
        || (op.value("cleanupReady").toBool() && !(op.value("phase") == "cleanup" && op.value("syncAttempted").toBool() && op.value("activated").toBool())
            && !(op.value("phase") == "discarding" && !op.value("syncAttempted").toBool()))) {
        error = "Attachment recovery record is invalid; data preserved"; return false;
    }
    QJsonObject review;
    return op.value("cleanupReady").toBool() || readReview(p, op, review, error);
}
bool attachmentOwnsSync(const Paths &p, const Record &record, const QString &session, QString &error) {
    QJsonObject op, registry; Config config;
    if (!readAttachment(p, record.id, op, error) || op.isEmpty() || op.value("session") != session
        || op.value("target") != recordJson(record) || op.value("phase") != "syncing" || !op.value("syncAttempted").toBool()
        || !op.value("activated").toBool() || op.value("pid").toInt() != int(getpid())
        || !loadRegistry(p, registry, error) || !loadConfig(p, config, error)) {
        if (error.isEmpty()) error = "Initial sync does not own the active attachment";
        return false;
    }
    auto synced = op.value("profile").toObject(); synced["type"] = "synced";
    if (profileFor(registry, record.id) != synced) { error = "Activated calendar profile changed"; return false; }
    for (const auto &actual : config.records) if (recordJson(actual) == recordJson(record)) return true;
    error = "Attachment sync target changed"; return false;
}
bool attachmentAllowed(const Paths &p, const QString &id, QString &error) {
    QJsonObject op;
    if (!validId(id)) return true;
    if (!readAttachment(p, id, op, error)) return false;
    if (op.isEmpty()) return true;
    error = "Calendar attachment is paused. Recovery files: " + stagePath(p, op); return false;
}
bool attachment(const Paths &p, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error) {
    if (action == "list") {
        QJsonArray sessions;
        for (const auto &name : QDir(p.state).entryList({"attachment-*.json"}, QDir::Files | QDir::Hidden | QDir::System)) {
            QJsonObject op, review;
            if (!readAttachment(p, name.mid(11, name.size() - 16), op, error)
                || (!op.value("cleanupReady").toBool() && !readReview(p, op, review, error))) return false;
            sessions.append(describe(p, op, review));
        }
        result = {{"ok", true}, {"conversions", sessions}}; return true;
    }
    Lease lease;
    if (!lease.acquire(p, error)) return false;
    if (action == "attach-begin") {
        const bool ok = begin(p, request, result, error);
        if (!ok && result.value("remoteCreated").toBool())
            error = "Remote calendar created; local calendar is unchanged. Select the created remote and retry attachment, not creation. " + error;
        return ok;
    }
    QJsonObject op, review;
    if (!readAttachment(p, request.value("id").toString(), op, error) || op.isEmpty() || op.value("session") != request.value("session")
        || op.value("revision") != request.value("expectedRevision")
        || (!op.value("cleanupReady").toBool() && !readReview(p, op, review, error))) {
        if (error.isEmpty()) error = "Attachment session changed; reopen conversion";
        return false;
    }
    result = describe(p, op, review);
    result["ok"] = false;
    if (op.value("phase") == "discarding" || (action == "attach-cancel" && !op.value("syncAttempted").toBool() && op.value("phase") == "review")) {
        if (!clearStage(p, op, error)) { result = describe(p, op, review); result["ok"] = false; return false; }
        result = {{"ok", true}, {"id", op.value("id")}, {"kind", "local-to-synced"}, {"cancelled", true}}; return true;
    }
    if (action == "attach-finish" && op.value("phase") == "review") return finish(p, request, op, review, result, error);
    if (action == "attach-retry") {
        if (op.value("phase") == "cleanup") return finishCleanup(p, op, review, result, error);
        if (op.value("syncAttempted").toBool() && op.value("activated").toBool()) return complete(p, op, review, result, error);
        if (op.value("phase") == "activating" && rollback(p, op, error)) {
            result = {{"ok", true}, {"id", op.value("id")}, {"kind", "local-to-synced"}, {"cancelled", true}};
            return true;
        }
    }
    error = "Attachment action is not available in this phase"; return false;
}
} // namespace CalDavBackend
