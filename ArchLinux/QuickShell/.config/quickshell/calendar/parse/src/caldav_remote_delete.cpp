#include "caldav_remote.h"
#include "calendar_json.h"
#include "calendar_lock.h"
#include "conflict_state.h"
#include "removal_files.h"
#include <QCryptographicHash>
#include <QDir>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QUuid>
#include <algorithm>
#include <fcntl.h>
#include <memory>
#include <sys/stat.h>
#include <unistd.h>

namespace CalDavBackend {
using namespace SubscriptionBackend;
namespace {
constexpr qint64 localLimit = 64LL * 1024 * 1024, reviewLimit = 616LL * 1024 * 1024;
bool present(const QString &path) { return QFileInfo::exists(path) || QFileInfo(path).isSymLink(); }
QString markerPath(const Paths &p, const QString &id) { return p.state + "/remote-delete-" + id + ".json"; }
QString payloadPath(const Paths &p, const QJsonObject &op) { return p.data + "/.calendar-remote-delete-" + op.value("id").toString() + '-' + op.value("session").toString() + ".json"; }
QStringList payloadNames(const Paths &p, const QString &id) {
    return QDir(p.data).entryList({".calendar-remote-delete-" + id + '-' + QString(32, '?') + ".json"}, QDir::AllEntries | QDir::System | QDir::Hidden | QDir::NoDotAndDotDot);
}
QString identity(const struct stat &stamp) { return QString::number(stamp.st_dev) + ':' + QString::number(stamp.st_ino); }
bool digest(const QJsonValue &value) { return value.isString() && QRegularExpression("^[a-f0-9]{64}$").match(value.toString()).hasMatch(); }
bool validStamp(const QJsonValue &value) {
    const auto info = value.toObject();
    const auto mode = info.value("mode");
    return value.isObject() && info.size() == 3 && digest(info.value("digest"))
        && QRegularExpression("^[0-9]+:[0-9]+$").match(info.value("identity").toString()).hasMatch()
        && mode.isDouble() && mode.toDouble() == mode.toInt(-1) && mode.toInt(-1) >= 0 && mode.toInt() <= 0777;
}
bool validManifest(const QJsonObject &manifest) {
    if (manifest.size() != 5 || !manifest.value("files").isObject() || !manifest.value("databases").isObject()
        || !QRegularExpression("^[0-9]+:[0-9]+$").match(manifest.value("identity").toString()).hasMatch()
        || !validStamp(manifest.value("cache")) || (!manifest.value("conflicts").isNull() && !validStamp(manifest.value("conflicts")))) return false;
    const auto files = manifest.value("files").toObject(), databases = manifest.value("databases").toObject();
    for (auto it = files.begin(); it != files.end(); ++it) {
        const auto name = it.key();
        if (name.isEmpty() || name.toUtf8().size() > 255 || name.contains('/') || name.contains('\\')
            || name.contains(QRegularExpression("[\\x00-\\x1f\\x7f]")) || name.startsWith(".calendar-")
            || (name != "displayname" && !name.endsWith(".ics")) || !validStamp(it.value())) return false;
    }
    if (!databases.contains("")) return false;
    for (auto it = databases.begin(); it != databases.end(); ++it)
        if (!QStringList{"", "-wal", "-shm", "-journal"}.contains(it.key()) || !validStamp(it.value())) return false;
    return true;
}
QJsonObject profileFor(const QJsonObject &registry, const QString &id) {
    for (const auto &value : registry.value("profiles").toArray()) if (value.toObject().value("id") == id) return value.toObject();
    return {};
}
bool owned(const QString &path, QJsonObject &info, QString &error, QByteArray *bytes = nullptr, qint64 limit = 0) {
    if (!ensureDirectory(QFileInfo(path).path(), error)) return false;
    const int fd = open(QFile::encodeName(path).constData(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    struct stat before{}, after{}, named{};
    if (fd < 0 || fstat(fd, &before) != 0 || !S_ISREG(before.st_mode) || before.st_uid != geteuid() || before.st_nlink != 1
        || before.st_size < 0 || (limit && before.st_size > limit)) {
        if (fd >= 0) close(fd);
        error = "Calendar file is missing, unsafe or too large: " + path; return false;
    }
    QFile file;
    if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) { close(fd); error = "Could not read calendar file: " + path; return false; }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (bytes) {
        *bytes = file.read(limit + 1);
        if (file.error() != QFileDevice::NoError || bytes->size() > limit) { error = "Could not read bounded calendar file: " + path; return false; }
        hash.addData(*bytes);
    } else if (!hash.addData(&file)) { error = "Could not fingerprint calendar file: " + path; return false; }
    if (fstat(fd, &after) != 0 || lstat(QFile::encodeName(path).constData(), &named) != 0 || identity(before) != identity(named)
        || before.st_size != after.st_size || before.st_mtim.tv_sec != after.st_mtim.tv_sec || before.st_mtim.tv_nsec != after.st_mtim.tv_nsec
        || before.st_ctim.tv_sec != after.st_ctim.tv_sec || before.st_ctim.tv_nsec != after.st_ctim.tv_nsec) {
        error = "Calendar file changed while reading; newer contents preserved: " + path; return false;
    }
    info = {{"digest", QString::fromLatin1(hash.result().toHex())}, {"identity", identity(before)}, {"mode", int(before.st_mode & 0777)}};
    return true;
}
bool privateBytes(const QString &path, QByteArray &bytes, QString &error, qint64 limit) {
    struct stat stamp{};
    if (lstat(QFile::encodeName(path).constData(), &stamp) != 0 || !S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid()
        || stamp.st_nlink != 1 || (stamp.st_mode & 0777) != 0600) {
        error = "Pending deletion file must be an owned private regular file: " + path; return false;
    }
    return readFile(path, bytes, error, false, limit);
}
bool loadPayload(const Paths &p, const QJsonObject &op, QJsonObject &payload, QString &error) {
    QByteArray bytes;
    const bool activated = !present(payloadPath(p, op)) && op.value("payloadKind") == "local"
        && QStringList{"remote-gone", "activating", "cleanup"}.contains(op.value("phase").toString());
    if (activated) {
        const auto path = p.data + '/' + op.value("id").toString() + ".json";
        QJsonObject info, canonical;
        if (!owned(path, info, error, &bytes, localLimit)) return false;
        const auto doc = QJsonDocument::fromJson(bytes).object();
        if ((!op.value("localActive").toBool() && (info.value("identity") != op.value("payloadIdentity") || info.value("digest") != op.value("payloadDigest")))
            || doc.size() != 2 || !QList<int>{1, 2, 3}.contains(doc.value("version").toInt()) || !doc.value("events").isArray()
            || !makeLocalDocument(op.value("id").toString(), doc.value("events").toArray(), canonical, error) || canonical.value("events") != doc.value("events")) {
            if (error.isEmpty()) error = "Published local calendar changed before activation; newer file preserved: " + path;
            return false;
        }
        payload = doc;
        return true;
    }
    if (!privateBytes(payloadPath(p, op), bytes, error, reviewLimit)) return false;
    const auto hash = revision(bytes);
    if (hash != op.value("payloadDigest") && hash != op.value("pendingDigest")) {
        error = "Preserved deletion payload changed; inspect retained copy: " + payloadPath(p, op); return false;
    }
    QJsonParseError parsed;
    const auto doc = QJsonDocument::fromJson(bytes, &parsed);
    const auto kind = hash == op.value("pendingDigest") ? op.value("pendingKind").toString() : op.value("payloadKind").toString();
    if (parsed.error != QJsonParseError::NoError || !doc.isObject()
        || (kind == "review" ? doc.object().value("version") != 1 || doc.object().value("id") != op.value("id")
            || !doc.object().value("conflicts").isArray() : kind != "local" || doc.object().value("version") != 3 || !doc.object().value("events").isArray())) {
        error = "Preserved deletion payload is malformed: " + payloadPath(p, op); return false;
    }
    payload = doc.object();
    return true;
}
bool publishPayload(const Paths &p, QJsonObject &op, const QJsonObject &payload, const QString &kind, const QString &phase, QString &error) {
    const auto bytes = QJsonDocument(payload).toJson();
    if (bytes.size() > (kind == "local" ? localLimit : reviewLimit)) { error = "Preserved deletion payload exceeds size limit"; return false; }
    op["pendingDigest"] = revision(bytes); op["pendingKind"] = kind;
    if (!saveRemoteDeletion(p, op, error) || !writeFile(payloadPath(p, op), bytes, error, !present(payloadPath(p, op)))) return false;
    QJsonObject info;
    if (!owned(payloadPath(p, op), info, error) || info.value("digest") != op.value("pendingDigest")) return false;
    op["payloadDigest"] = op.value("pendingDigest"); op["payloadIdentity"] = info.value("identity"); op["payloadKind"] = kind;
    if (kind == "review") op["reviewRevision"] = op.value("pendingDigest");
    op.remove("pendingDigest"); op.remove("pendingKind"); op["phase"] = phase;
    return saveRemoteDeletion(p, op, error);
}
bool localSources(const Paths &p, const QString &id, QMap<QString, QByteArray> &sources, QJsonObject &manifest, QString &error) {
    const auto directory = p.data + '/' + id;
    struct stat stamp{};
    if (lstat(QFile::encodeName(directory).constData(), &stamp) != 0 || !S_ISDIR(stamp.st_mode) || stamp.st_uid != geteuid()
        || !ensureDirectory(directory, error)) { error = "Canonical calendar collection is missing or unsafe"; return false; }
    QJsonObject files;
    std::vector<Event> events;
    qint64 total = 0;
    for (const auto &name : QDir(directory).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDir::Name)) {
        if (name == ".calendar-sync.lock") continue;
        if (name != "displayname" && (!name.endsWith(".ics") || name.startsWith(".calendar-"))) {
            error = "Calendar contains unexpected or pending source data: " + directory + '/' + name; return false;
        }
        QByteArray bytes; QJsonObject info;
        if (!owned(directory + '/' + name, info, error, &bytes, 16LL * 1024 * 1024)) return false;
        files[name] = info;
        if (name == "displayname") continue;
        total += bytes.size();
        const auto parsed = parseCalendar(bytes.toStdString());
        if (total > localLimit || !parsed.error.empty() || parsed.events.size() != 1) { error = "Canonical calendar source is incomplete or too large"; return false; }
        sources[name] = bytes;
        events.insert(events.end(), parsed.events.begin(), parsed.events.end());
    }
    QByteArray cache; QJsonObject cacheInfo;
    std::string detail;
    if (!validateSyncedCache((directory + ".sync.json").toStdString(), id.toStdString(), detail)
        || !owned(directory + ".sync.json", cacheInfo, error, &cache, localLimit)) {
        if (error.isEmpty()) error = QString::fromStdString(detail);
        return false;
    }
    const auto rebuilt = QJsonDocument::fromJson(QByteArray::fromStdString(serializeSyncedCalendar(events, id.toStdString()))).object();
    if (!rebuilt.value("warnings").toArray().isEmpty() || rebuilt.value("events") != QJsonDocument::fromJson(cache).object().value("events")) {
        error = "Canonical sources and displayed cache differ; refresh/review before remote deletion"; return false;
    }
    QJsonObject databases;
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) {
        const auto path = p.status + "/qs_caldav_" + id + ".status" + suffix;
        if (!present(path) && !suffix.isEmpty()) continue;
        QJsonObject info;
        if (!owned(path, info, error)) return false;
        databases[suffix] = info;
    }
    QJsonValue conflicts(QJsonValue::Null);
    const auto conflictPath = QFileInfo(p.state).path() + "/conflicts-" + id + ".json";
    if (present(conflictPath)) {
        QJsonObject info;
        if (!owned(conflictPath, info, error, nullptr, reviewLimit)) return false;
        conflicts = info;
    }
    manifest = {{"identity", identity(stamp)}, {"files", files}, {"cache", cacheInfo}, {"databases", databases}, {"conflicts", conflicts}};
    return true;
}
bool storedConflictSources(const Paths &p, const Record &target, const QMap<QString, QByteArray> &sources, RemoteSnapshot &remote, QString &error) {
    const auto path = QFileInfo(p.state).path() + "/conflicts-" + target.id + ".json";
    if (!present(path)) return true;
    QJsonObject info, state;
    if (!owned(path, info, error, nullptr, reviewLimit)) return false;
    std::string detail;
    if (!readConflictState(path.toStdString(), state, detail)) { error = QString::fromStdString(detail); return false; }
    QJsonObject currentInfo;
    if (!owned(path, currentInfo, error) || currentInfo != info) { error = "Stored conflict versions changed; nothing discarded"; return false; }
    QMap<QString, QByteArray> canonical, original;
    for (const auto &source : sources) {
        const auto parsed = parseCalendar(source.toStdString());
        if (!parsed.error.empty() || parsed.events.size() != 1) { error = "Canonical conflict source is invalid"; return false; }
        canonical[QString::fromStdString(parsed.events.front().uid)] = source;
    }
    qint64 total = 0;
    for (const auto &value : state.value("conflicts").toArray()) {
        const auto conflict = value.toObject();
        const auto pairs = conflict.value("kind") == "group" ? conflict.value("members").toArray() : QJsonArray{conflict};
        for (const auto &member : pairs) {
            const auto pair = member.toObject(); const auto uid = pair.value("uid").toString();
            const auto local = pair.value("localIcs").toString().toUtf8(), other = pair.value("remoteIcs").toString().toUtf8();
            total += local.size() + other.size();
            if (!canonical.contains(uid) || original.contains(uid) || local.size() > 16 * 1024 * 1024 || other.size() > 16 * 1024 * 1024 || total > localLimit) {
                error = "Stored conflict is stale, ambiguous or too large; nothing discarded"; return false;
            }
            for (const auto &raw : {local, other}) {
                const auto parsed = parseCalendar(raw.toStdString());
                if (!parsed.error.empty() || parsed.events.size() != 1 || QString::fromStdString(parsed.events.front().uid) != uid) {
                    error = "Stored conflict identity is invalid; nothing discarded"; return false;
                }
            }
            original[uid] = local;
            remote.resources[uid] = other;
        }
    }
    QMap<QString, QByteArray> current;
    for (auto it = original.begin(); it != original.end(); ++it) current[it.key()] = canonical.value(it.key());
    RemoteSnapshot previous; previous.resources = original;
    QJsonObject verified; QJsonArray differences;
    if (!buildRemoteReview(target, current, previous, verified, differences, error)) return false;
    if (!differences.isEmpty()) { error = "Local conflict versions changed since capture; inspect retained copies before preserving"; return false; }
    return true;
}
QStringList unitRoots(const Paths &p) {
    QStringList roots{p.units};
    if (!qEnvironmentVariable("XDG_RUNTIME_DIR").isEmpty()) roots.append(qEnvironmentVariable("XDG_RUNTIME_DIR") + "/systemd/user");
    return roots;
}
bool validLinks(const Paths &p, const QJsonObject &op, QString &error) {
    const auto timer = "quickshell-calendar-caldav-" + op.value("id").toString() + ".timer";
    QStringList seen;
    for (const auto &value : op.value("links").toArray()) {
        const auto link = value.toObject(); const auto path = link.value("path").toString();
        bool expected = false;
        for (const auto &root : unitRoots(p)) expected = expected || path == root + "/timers.target.wants/" + timer;
        if (!expected || seen.contains(path) || link.value("target").toString().isEmpty()
            || QDir::cleanPath(QDir(QFileInfo(path).path()).absoluteFilePath(link.value("target").toString())) != p.units + '/' + timer) {
            error = "Pending deletion has unsafe scheduling metadata"; return false;
        }
        seen.append(path);
    }
    return true;
}
bool scheduling(const Paths &p, const Config &config, QJsonObject &op, QString &error) {
    const auto id = op.value("id").toString(), timer = "quickshell-calendar-caldav-" + id + ".timer";
    QString worker, active, enabled;
    if (!CalendarRemoval::property("quickshell-calendar-caldav@" + id + ".service", "ActiveState", worker, error)
        || !QStringList{"inactive", "failed"}.contains(worker)
        || !CalendarRemoval::property(timer, "ActiveState", active, error) || !QStringList{"active", "inactive", "failed"}.contains(active)
        || !CalendarRemoval::property(timer, "UnitFileState", enabled, error) || !QStringList{"enabled", "enabled-runtime", "disabled"}.contains(enabled)) {
        if (error.isEmpty()) error = "Calendar synchronization is active or has custom scheduling; try when it finishes";
        return false;
    }
    QByteArray bytes; QJsonObject info;
    if (!owned(p.units + '/' + timer, info, error, &bytes, 1024 * 1024) || bytes != unitDefinitions(p, config).value(timer)) {
        if (error.isEmpty()) error = "Calendar timer has custom settings; preserved";
        return false;
    }
    QJsonArray links;
    for (const auto &root : unitRoots(p)) {
        const auto path = root + "/timers.target.wants/" + timer;
        if (!present(path)) continue;
        struct stat stamp{}; std::error_code code;
        const auto raw = std::filesystem::read_symlink(QFile::encodeName(path).constData(), code);
        if (lstat(QFile::encodeName(path).constData(), &stamp) != 0 || !S_ISLNK(stamp.st_mode) || stamp.st_uid != geteuid() || code) {
            error = "Calendar timer has custom enablement; preserved: " + path; return false;
        }
        links.append(QJsonObject{{"path", path}, {"target", QString::fromStdString(raw.native())}, {"identity", identity(stamp)}});
    }
    op["links"] = links; op["timerInfo"] = info; op["timerActive"] = active == "active"; op["timerEnablement"] = enabled;
    return validLinks(p, op, error);
}
QString phaseFor(const QJsonObject &op) { return op.contains("pendingDigest") ? "preparing" : op.value("phase").toString(); }
QJsonObject describe(const Paths &p, const QJsonObject &op, const QJsonObject &payload = {}) {
    const auto phase = phaseFor(op);
    const bool attempted = !op.value("preserveLocalOnly").toBool() && !QStringList{"preparing", "review", "ready", "rollback"}.contains(op.value("phase").toString());
    const auto saved = !present(payloadPath(p, op)) && op.value("payloadKind") == "local"
        ? p.data + '/' + op.value("id").toString() + ".json" : payloadPath(p, op);
    return {{"ok", true}, {"kind", op.value("preserveLocalOnly").toBool() ? "local-preserve" : "remote-delete"}, {"id", op.value("id")}, {"session", op.value("session")},
        {"revision", op.value("reviewRevision")}, {"phase", phase}, {"conflicts", payload.value("conflicts").toArray()},
        {"target", op.value("target")}, {"profile", op.value("profile")}, {"paused", true}, {"remoteAttempted", attempted},
        {"disconnected", op.value("localActive").toBool()}, {"localActive", op.value("localActive").toBool()}, {"localPath", p.data + '/' + op.value("id").toString() + ".json"},
        {"recoveryPaths", QJsonArray{saved, markerPath(p, op.value("id").toString())}}};
}
bool rollback(const Paths &p, QJsonObject &op, QJsonObject &result, QString &error) {
    const auto id = op.value("id").toString(), timer = "quickshell-calendar-caldav-" + id + ".timer";
    const bool attempted = !QStringList{"preparing", "review", "ready", "rollback"}.contains(op.value("phase").toString());
    QJsonObject registry, timerInfo; Config config;
    if (!loadRegistry(p, registry, error) || profileFor(registry, id) != op.value("profile") || !loadConfig(p, config, error)
        || std::none_of(config.records.begin(), config.records.end(), [&](const auto &record) { return recordJson(record) == op.value("target"); })
        || !owned(p.units + '/' + timer, timerInfo, error) || timerInfo.value("digest") != op.value("timerInfo").toObject().value("digest")) {
        if (error.isEmpty()) error = "Calendar or timer changed; newer state preserved";
        return false;
    }
    op["phase"] = "rollback";
    if (!saveRemoteDeletion(p, op, error)) return false;
    for (const auto &value : op.value("links").toArray()) {
        const auto link = value.toObject();
        const auto path = link.value("path").toString();
        if (!ensureDirectory(QFileInfo(path).path(), error)) return false;
        if (present(path)) {
            std::error_code code;
            const auto raw = std::filesystem::read_symlink(QFile::encodeName(path).constData(), code);
            if (code || QString::fromStdString(raw.native()) != link.value("target")) { error = "Newer timer link preserved: " + path; return false; }
        } else if (symlink(QFile::encodeName(link.value("target").toString()).constData(), QFile::encodeName(path).constData()) != 0) {
            error = "Could not restore timer enablement: " + path; return false;
        }
    }
    if (!command("systemctl", {"--user", "daemon-reload"}, 15000)
        || (op.value("timerActive").toBool() && !command("systemctl", {"--user", "start", timer}, 30000))) {
        error = "Could not restore previous calendar scheduling"; return false;
    }
    if (present(payloadPath(p, op))) {
        QJsonObject payload;
        if (!loadPayload(p, op, payload, error) || !CalendarRemoval::erase(payloadPath(p, op), error)) return false;
    }
    if (!CalendarRemoval::erase(markerPath(p, id), error)) return false;
    QDir().rmdir(p.state);
    result = {{"ok", true}, {"kind", op.value("preserveLocalOnly").toBool() ? "local-preserve" : "remote-delete"}, {"id", id}, {"session", op.value("session")}, {"revision", op.value("reviewRevision")},
        {"phase", "rollback"}, {"paused", false}, {"remoteAttempted", attempted}, {"recoveryPaths", QJsonArray{}}, {"rolledBack", true}};
    return true;
}
bool begin(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error, bool preserveLocalOnly) {
    const auto id = request.value("id").toString();
    Config config; QJsonObject registry;
    if (!validId(id) || !conversionAllowed(p, id, error) || !loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    const auto profile = profileFor(registry, id);
    const auto selected = std::find_if(config.records.begin(), config.records.end(), [&](const auto &record) { return record.id == id; });
    if (profile.value("type") != "synced" || request.value("expectedProfile") != profile || selected == config.records.end()
        || request.value("expectedRevision") != revision(config.original)) { error = "Calendar settings changed; reopen remote deletion"; return false; }
    if (preserveLocalOnly) {
        QJsonObject unavailable;
        if (!unavailableStatus(p, *selected, unavailable, error)) return false;
        if (unavailable.isEmpty()) { error = "Remote calendar is not paused as unavailable; reopen calendar manager"; return false; }
    } else if (!remoteSyncAllowed(p, id, error)) return false;
    if (present(p.data + '/' + id + ".json")) { error = "Local destination already exists; nothing overwritten"; return false; }
    QJsonObject inspected;
    if (!retireConverted(p, request, {}, inspected, error, true) || !command("/bin/sh", {p.broker, "check-recovery"}, 10000)) return false;
    const auto token = QUuid::createUuid().toString(QUuid::WithoutBraces).remove('-');
    QJsonObject op{{"version", 1}, {"kind", "remote-delete"}, {"id", id}, {"session", token}, {"phase", "preparing"},
        {"profile", profile}, {"target", recordJson(*selected)}, {"configRevision", revision(config.original)}, {"reviewRevision", revision(token.toUtf8())}};
    if (preserveLocalOnly) op["preserveLocalOnly"] = true;
    op["payloadPath"] = payloadPath(p, op);
    std::string detail;
    CalendarLock lock((p.data + '/' + id).toStdString(), detail);
    QMap<QString, QByteArray> sources; QJsonObject manifest;
    if (!lock.acquired() || !localSources(p, id, sources, manifest, error) || !scheduling(p, config, op, error)) {
        if (error.isEmpty()) error = QString::fromStdString(detail);
        return false;
    }
    op["sources"] = manifest;
    if (!saveRemoteDeletion(p, op, error)) return false;
    auto fail = [&] {
        const auto cause = error;
        QString restoreError;
        if (!rollback(p, op, result, restoreError)) {
            result = describe(p, op); result["ok"] = false;
            error = cause + "; sync paused. " + restoreError + ". Recovery files: " + payloadPath(p, op) + ", " + markerPath(p, id);
        } else { result["ok"] = false; error = cause; }
        return false;
    };
    const auto timer = "quickshell-calendar-caldav-" + id + ".timer";
    if (!command("systemctl", {"--user", "stop", timer}, 30000)) { error = "Could not pause calendar timer"; return fail(); }
    for (const auto &value : op.value("links").toArray()) {
        const auto link = value.toObject(); const auto path = link.value("path").toString();
        struct stat stamp{}; std::error_code code;
        const auto raw = std::filesystem::read_symlink(QFile::encodeName(path).constData(), code);
        if (lstat(QFile::encodeName(path).constData(), &stamp) != 0 || identity(stamp) != link.value("identity") || code
            || QString::fromStdString(raw.native()) != link.value("target") || !CalendarRemoval::erase(path, error)) {
            if (error.isEmpty()) error = "Newer timer link preserved: " + path;
            return fail();
        }
    }
    if (!op.value("links").toArray().isEmpty() && !command("systemctl", {"--user", "daemon-reload"}, 15000)) {
        error = "Could not reload paused calendar scheduling"; return fail();
    }
    RemoteSnapshot remote;
    QJsonObject payload; QJsonArray conflicts;
    if ((preserveLocalOnly ? !storedConflictSources(p, *selected, sources, remote, error) : !snapshotRemote(*selected, remote, error))
        || !buildRemoteReview(*selected, sources, remote, payload, conflicts, error)) return fail();
    op["homeHref"] = remote.homeHref; op["remoteFingerprint"] = remote.fingerprint;
    if (!publishPayload(p, op, payload, "review", "review", error)) return fail();
    result = describe(p, op, payload);
    return true;
}
bool currentReviewSources(const Paths &p, const QJsonObject &op, QMap<QString, QByteArray> &sources, QString &error) {
    Config config; QJsonObject registry, manifest;
    const auto id = op.value("id").toString();
    if (!loadConfig(p, config, error) || revision(config.original) != op.value("configRevision")
        || !loadRegistry(p, registry, error) || profileFor(registry, id) != op.value("profile")
        || !localSources(p, id, sources, manifest, error) || manifest != op.value("sources")) {
        if (error.isEmpty()) error = "Calendar settings or canonical sources changed; nothing deleted. Cancel or reopen review";
        return false;
    }
    return true;
}
bool refreshReview(const Paths &p, QJsonObject &op, const QMap<QString, QByteArray> &sources, const RemoteSnapshot &remote,
                   QJsonObject &result, QString &error) {
    QJsonObject payload; QJsonArray conflicts;
    if (!buildRemoteReview(recordFromJson(op.value("target").toObject()), sources, remote, payload, conflicts, error)) return false;
    op["homeHref"] = remote.homeHref; op["remoteFingerprint"] = remote.fingerprint;
    if (!publishPayload(p, op, payload, "review", "review", error)) return false;
    result = describe(p, op, payload); result["reviewChanged"] = true;
    result["message"] = op.value("preserveLocalOnly").toBool()
        ? "Local preservation was interrupted. Confirm the current local copy again; no server changes attempted."
        : "Remote calendar changed or review was interrupted. Review the current versions and confirm again; nothing deleted.";
    return true;
}
bool finishForward(const Paths &p, QJsonObject &op, QJsonObject &result, QString &error) {
    QJsonObject completed;
    const bool ok = finishRemoteRetirement(p, op, completed, error);
    result = describe(p, op);
    for (auto it = completed.begin(); it != completed.end(); ++it) result[it.key()] = it.value();
    result["ok"] = ok;
    if (!ok) {
        result["localActive"] = op.value("localActive").toBool();
        if (op.value("localActive").toBool()) result["cleanupWarning"] = true;
        error = QString(op.value("preserveLocalOnly").toBool() ? "Offline preservation: " : "Remote calendar deleted; ")
            + QString(op.value("localActive").toBool() ? "local calendar active, cleanup pending. " : "local activation pending; preserved data retained. ") + error;
    }
    return ok;
}
bool markGone(const Paths &p, QJsonObject &op, QJsonObject &result, QString &error) {
    op["phase"] = "remote-gone";
    if (!saveRemoteDeletion(p, op, error)) return false;
    return finishForward(p, op, result, error);
}
bool verifyOutcome(const Paths &p, QJsonObject &op, QJsonObject &result, QString &error) {
    const auto cause = error;
    RemoteSnapshot remote; QString inspected;
    const auto presence = inspectRemote(recordFromJson(op.value("target").toObject()), op.value("homeHref").toString(), remote, inspected);
    if (presence == RemotePresence::Absent) { error.clear(); return markGone(p, op, result, error); }
    if (presence == RemotePresence::Present && remote.fingerprint == op.value("remoteFingerprint") && !op.value("conservative").toBool()) {
        if (!rollback(p, op, result, error)) return false;
        result["ok"] = false;
        error = "Remote calendar remains unchanged; previous synchronization restored. " + cause;
        return false;
    }
    op["phase"] = "uncertain";
    if (!saveRemoteDeletion(p, op, error)) return false;
    result = describe(p, op); result["ok"] = false;
    error = "Remote deletion outcome is uncertain; sync stays paused and preserved events remain available. "
        + (presence == RemotePresence::Present ? QString("Present collection is changed or may still be deleted asynchronously. ") : inspected + ' ')
        + "Retry performs one read-only check, never another DELETE.";
    return false;
}
bool safePredeleteFailure(const Paths &p, QJsonObject &op, QJsonObject &result, QString &error) {
    const auto cause = error;
    QString restored;
    if (rollback(p, op, result, restored)) {
        result["ok"] = false;
        error = "Remote deletion not attempted; previous synchronization restored. " + cause;
    } else error = cause + "; synchronization remains paused. " + restored;
    return false;
}
bool finish(const Paths &p, const QJsonObject &request, QJsonObject &op, QJsonObject &result, QString &error) {
    if (op.value("phase") != "review" || op.contains("pendingDigest") || op.value("payloadKind") != "review" || !request.value("choices").isArray()) {
        error = "Remote deletion requires current review and explicit confirmation"; return false;
    }
    QJsonObject payload, local;
    QMap<QString, QByteArray> sources;
    const auto id = op.value("id").toString();
    if (!loadPayload(p, op, payload, error) || !projectRemoteReview(id, payload, request.value("choices").toArray(), local, error)) return false;
    if (!currentReviewSources(p, op, sources, error) || !preflightRemoteRetirement(p, op, error)) return safePredeleteFailure(p, op, result, error);
    RemoteSnapshot remote;
    const auto target = recordFromJson(op.value("target").toObject());
    const bool localOnly = op.value("preserveLocalOnly").toBool();
    if (!localOnly && (!snapshotRemote(target, remote, error) || remote.homeHref != op.value("homeHref"))) {
        if (error.isEmpty()) error = "Calendar home changed; reconnect before deleting";
        return safePredeleteFailure(p, op, result, error);
    }
    if (!localOnly && remote.fingerprint != op.value("remoteFingerprint")) {
        if (refreshReview(p, op, sources, remote, result, error)) return true;
        return safePredeleteFailure(p, op, result, error);
    }
    if (!publishPayload(p, op, local, "local", "ready", error) || !loadPayload(p, op, payload, error)
        || payload != local || !preflightRemoteRetirement(p, op, error)) return safePredeleteFailure(p, op, result, error);
    sources.clear();
    if (!currentReviewSources(p, op, sources, error)) return safePredeleteFailure(p, op, result, error);
    if (localOnly) return markGone(p, op, result, error); // Commit local preservation only; never probe, resolve, upload or DELETE.
    op["phase"] = "deleting";
    op["conservative"] = true; // A crash before response classification cannot rule out queued acceptance.
    if (!saveRemoteDeletion(p, op, error)) return false;
    bool conservative = false;
    const auto outcome = deleteRemoteCollection(target, op.value("homeHref").toString(), error, &conservative);
    op["conservative"] = conservative;
    if (outcome == RemoteOutcome::Succeeded) return markGone(p, op, result, error);
    if (outcome == RemoteOutcome::Refused) {
        const auto cause = error;
        if (!rollback(p, op, result, error)) return false;
        result["ok"] = false; error = "Remote deletion refused; previous synchronization restored. " + cause;
        return false;
    }
    if (!saveRemoteDeletion(p, op, error)) return false;
    return verifyOutcome(p, op, result, error);
}
bool retry(const Paths &p, QJsonObject &op, QJsonObject &result, QString &error) {
    const auto phase = op.value("phase").toString();
    if (QStringList{"remote-gone", "activating", "cleanup"}.contains(phase)) return finishForward(p, op, result, error);
    if (phase == "deleting" || phase == "uncertain") return verifyOutcome(p, op, result, error);
    if (phase == "rollback") return rollback(p, op, result, error);
    QMap<QString, QByteArray> sources;
    RemoteSnapshot remote;
    const auto target = recordFromJson(op.value("target").toObject());
    if (!currentReviewSources(p, op, sources, error)
        || (op.value("preserveLocalOnly").toBool() ? !storedConflictSources(p, target, sources, remote, error) : !snapshotRemote(target, remote, error))) return safePredeleteFailure(p, op, result, error);
    if (refreshReview(p, op, sources, remote, result, error)) return true; // Never implicitly resumes a destructive request.
    return safePredeleteFailure(p, op, result, error);
}
}

bool remoteFileStamp(const QString &path, QJsonObject &info, QString &error, QByteArray *bytes, qint64 limit) {
    return owned(path, info, error, bytes, limit);
}

bool saveRemoteDeletion(const Paths &p, const QJsonObject &op, QString &error) {
    const auto id = op.value("id").toString(), token = op.value("session").toString();
    if (!validId(id) || !QRegularExpression("^[a-f0-9]{32}$").match(token).hasMatch() || op.value("payloadPath") != payloadPath(p, op)
        || !ensureDirectory(p.state, error)) { if (error.isEmpty()) error = "Unsafe pending deletion identity"; return false; }
    const auto path = markerPath(p, id);
    if (present(path)) {
        QByteArray before;
        if (!privateBytes(path, before, error, 1024 * 1024) || QJsonDocument::fromJson(before).object().value("session") != token) {
            if (error.isEmpty()) error = "Another pending deletion owns this calendar";
            return false;
        }
    }
    const auto bytes = QJsonDocument(op).toJson();
    if (bytes.size() > 1024 * 1024) { error = "Pending deletion metadata exceeds size limit"; return false; }
    return writeFile(path, bytes, error, !present(path));
}
bool readRemoteDeletion(const Paths &p, const QString &id, QJsonObject &op, QString &error) {
    op = {};
    if (!validId(id)) { error = "Invalid pending deletion ID"; return false; }
    const auto path = markerPath(p, id);
    if (!present(path)) {
        if (!payloadNames(p, id).isEmpty()) {
            error = "Pending deletion record is missing; preserved payload requires inspection"; return false;
        }
        return true;
    }
    QByteArray bytes;
    if (!privateBytes(path, bytes, error, 1024 * 1024)) return false;
    QJsonParseError parsed;
    const auto doc = QJsonDocument::fromJson(bytes, &parsed);
    op = doc.object();
    const auto phase = op.value("phase").toString(), token = op.value("session").toString();
    const auto target = recordFromJson(op.value("target").toObject());
    if (parsed.error != QJsonParseError::NoError || !doc.isObject() || op.value("version") != 1 || op.value("kind") != "remote-delete"
        || op.value("id") != id || !QRegularExpression("^[a-f0-9]{32}$").match(token).hasMatch() || op.value("payloadPath") != payloadPath(p, op)
        || !QStringList{"preparing", "review", "ready", "deleting", "remote-gone", "activating", "cleanup", "uncertain", "rollback"}.contains(phase)
        || !validIdentity(target) || target.id != id || op.value("target") != recordJson(target) || !validProfile(op.value("profile").toObject())
        || op.value("profile").toObject().value("id") != id || op.value("profile").toObject().value("type") != "synced"
        || !digest(op.value("configRevision")) || !digest(op.value("reviewRevision")) || !op.value("links").isArray()
        || !op.value("timerActive").isBool() || !validManifest(op.value("sources").toObject()) || !validStamp(op.value("timerInfo"))
        || !QStringList{"enabled", "enabled-runtime", "disabled"}.contains(op.value("timerEnablement").toString()) || !validLinks(p, op, error)
        || (op.contains("payloadDigest") && !digest(op.value("payloadDigest")))
        || (op.contains("preserveLocalOnly") && (!op.value("preserveLocalOnly").isBool()
            || (op.value("preserveLocalOnly").toBool() && QStringList{"deleting", "uncertain"}.contains(phase))))
        || (op.contains("pendingDigest") && (!digest(op.value("pendingDigest")) || !QStringList{"local", "review"}.contains(op.value("pendingKind").toString())))) {
        if (error.isEmpty()) error = "Pending remote deletion state is malformed; inspect " + path;
        return false;
    }
    if (!present(payloadPath(p, op)) && QStringList{"preparing", "rollback"}.contains(phase) && !op.contains("payloadDigest")) return true;
    if (!present(payloadPath(p, op)) && phase == "rollback") return true;
    QJsonObject payload;
    return loadPayload(p, op, payload, error);
}
bool remoteDeletionAllowed(const Paths &p, const QString &id, QString &error) {
    if (!validId(id)) return true;
    // A malformed/missing record must block too; ordinary writes never parse the large payload.
    if (!present(markerPath(p, id)) && payloadNames(p, id).isEmpty()) return true;
    error = "Remote calendar deletion is paused. Recovery files: " + markerPath(p, id);
    return false;
}
bool remoteDeletion(const Paths &p, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error) {
    if (action == "list") {
        QJsonArray sessions;
        for (const auto &name : QDir(p.data).entryList({".calendar-remote-delete-*.json"}, QDir::AllEntries | QDir::System | QDir::Hidden | QDir::NoDotAndDotDot)) {
            const auto match = QRegularExpression("^\\.calendar-remote-delete-([a-z0-9][a-z0-9_-]*)-([a-f0-9]{32})\\.json$").match(name);
            QJsonObject op;
            if (!match.hasMatch() || !readRemoteDeletion(p, match.captured(1), op, error) || op.isEmpty()
                || op.value("session") != match.captured(2)) {
                if (error.isEmpty()) error = "Pending deletion payload has no matching operation record: " + p.data + '/' + name;
                return false;
            }
        }
        for (const auto &name : QDir(p.state).entryList({"remote-delete-*.json"}, QDir::Files | QDir::System | QDir::Hidden)) {
            QJsonObject op, payload;
            const auto id = name.mid(14, name.size() - 19);
            if (!readRemoteDeletion(p, id, op, error)) return false;
            if (present(payloadPath(p, op)) && !loadPayload(p, op, payload, error)) return false;
            sessions.append(describe(p, op, payload));
        }
        result = {{"ok", true}, {"conversions", sessions}};
        return true;
    }
    result = {{"ok", false}, {"id", request.value("id")}};
    Lease lease;
    if (!lease.acquire(p, error)) return false;
    if (action == "remote-delete-begin" || action == "local-preserve-begin") return begin(p, request, result, error, action == "local-preserve-begin");
    QJsonObject op;
    const auto id = request.value("id").toString();
    if (!readRemoteDeletion(p, id, op, error) || op.isEmpty() || op.value("session") != request.value("session")
        || op.value("reviewRevision") != request.value("expectedRevision")) {
        if (error.isEmpty()) error = "Remote deletion session changed; reopen it";
        return false;
    }
    result = describe(p, op); result["ok"] = false;
    if (action == "remote-delete-finish" || action == "remote-delete-retry") {
        std::unique_ptr<CalendarLock> lock;
        const auto collection = p.data + '/' + id;
        if (present(collection)) {
            std::string detail;
            lock = std::make_unique<CalendarLock>(collection.toStdString(), detail);
            if (!lock->acquired()) { error = "Calendar source is busy; nothing changed"; return false; }
        }
        const bool ok = action == "remote-delete-finish" ? finish(p, request, op, result, error) : retry(p, op, result, error);
        if (!ok && !result.value("rolledBack").toBool()) {
            const auto partial = result;
            QJsonObject payload; QString ignored;
            loadPayload(p, op, payload, ignored);
            result = describe(p, op, payload); result["ok"] = false;
            for (const auto &key : {"cleanupWarning", "activationWarning", "converted", "completed"})
                if (partial.contains(key)) result[key] = partial.value(key);
            QStringList paths;
            for (const auto &path : result.value("recoveryPaths").toArray()) paths.append(path.toString());
            error += " Recovery files: " + paths.join(", ");
        }
        return ok;
    }
    if (action != "remote-delete-cancel" || !QStringList{"preparing", "review", "ready", "rollback"}.contains(op.value("phase").toString())) {
        error = "Remote deletion requires renewed review or read-only recovery"; return false;
    }
    if (!rollback(p, op, result, error)) return false;
    result["cancelled"] = true;
    return true;
}
}
