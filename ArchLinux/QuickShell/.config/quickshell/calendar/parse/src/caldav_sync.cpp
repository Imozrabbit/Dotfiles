#include "caldav.h"
#include "caldav_remote.h"
#include "calendar_json.h"
#include "calendar_lock.h"
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QFile>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <csignal>
#include <cerrno>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace CalDavBackend {
using namespace SubscriptionBackend;
namespace {
bool localState(const Paths &p, const Record &r, bool initial, QString &error) {
    const auto directory = p.data + '/' + r.id;
    if (!QFileInfo(directory).isDir() || QFileInfo(directory).isSymLink() || !ensureDirectory(directory, error)
        || !QFileInfo(p.status).isDir() || !ensureDirectory(p.status, error)) {
        error = "Local collection or sync state is missing or unsafe; no server changes attempted"; return false;
    }
    QDirIterator files(directory, QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot);
    while (files.hasNext()) {
        const auto path = files.next();
        struct stat stamp{};
        if (lstat(QFile::encodeName(path).constData(), &stamp) != 0 || !S_ISREG(stamp.st_mode)
            || stamp.st_uid != geteuid() || stamp.st_nlink != 1 || stamp.st_size < 0 || stamp.st_size > 64 * 1024 * 1024) {
            error = "Managed calendar contains an unsafe resource; no server changes attempted"; return false;
        }
    }
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) {
        const auto path = p.status + '/' + r.pair() + ".status" + suffix;
        struct stat stamp{};
        if (lstat(QFile::encodeName(path).constData(), &stamp) != 0) {
            if (errno == ENOENT && (initial || !suffix.isEmpty())) continue;
            error = "Calendar sync database is missing; inspect state before synchronizing"; return false;
        }
        if (!S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid() || stamp.st_nlink != 1) {
            error = "Calendar sync database is unsafe; no server changes attempted"; return false;
        }
    }
    return true;
}

bool status(const Paths &p, const Record &r, bool busy, bool success, const QString &message, QString &error, const QString &availability = {}) {
    QJsonObject document;
    if (!ensureDirectory(p.state, error) || !jsonFile(p.state + "/status.json", document, error)) return false;
    if (!document.isEmpty() && (document.size() != 2 || document.value("version") != 1 || !document.value("records").isObject())) {
        error = "Calendar synchronization status is invalid"; return false;
    }
    auto records = document.value("records").toObject();
    auto value = records.value(r.id).toObject();
    value["lastAttemptMs"] = QDateTime::currentMSecsSinceEpoch();
    value["busy"] = busy; value["pid"] = busy ? int(getpid()) : 0; value["error"] = message;
    if (availability == "available" || success) {
        value.remove("remoteState"); value.remove("remoteTarget");
    } else if (!availability.isEmpty()) {
        value["remoteState"] = availability; value["remoteTarget"] = availabilityTarget(r);
    }
    if (success) value["lastSuccessMs"] = QDateTime::currentMSecsSinceEpoch();
    records[r.id] = value;
    return writeFile(p.state + "/status.json", QJsonDocument(QJsonObject{{"version", 1}, {"records", records}}).toJson(), error);
}
} // namespace

QString availabilityTarget(const Record &record) {
    auto target = recordJson(record);
    target.remove("intervalSeconds");
    return revision(QJsonDocument(target).toJson(QJsonDocument::Compact));
}
bool unavailableStatus(const Paths &p, const Record &record, QJsonObject &out, QString &error) {
    out = {};
    QJsonObject document;
    if (!jsonFile(p.state + "/status.json", document, error)) return false;
    if (!document.isEmpty() && (document.size() != 2 || document.value("version") != 1 || !document.value("records").isObject())) {
        error = "Calendar synchronization status is invalid"; return false;
    }
    const auto saved = document.value("records").toObject().value(record.id).toObject();
    if (!saved.contains("remoteState")) return true;
    if (!QStringList{"deleted", "unavailable"}.contains(saved.value("remoteState").toString())
        || !QRegularExpression("^[a-f0-9]{64}$").match(saved.value("remoteTarget").toString()).hasMatch()) {
        error = "Remote availability status is invalid; local calendar preserved"; return false;
    }
    if (saved.value("remoteTarget") == availabilityTarget(record)) out = saved;
    return true;
}
bool remoteSyncAllowed(const Paths &p, const QString &id, QString &error) {
    Config config;
    if (!loadConfig(p, config, error)) return false;
    for (const auto &record : config.records) if (record.id == id) {
        QJsonObject saved;
        if (!unavailableStatus(p, record, saved, error)) return false;
        if (!saved.isEmpty()) {
            error = saved.value("error").toString() + " Check again, keep as local, or delete from this device.";
            return false;
        }
    }
    return true;
}
bool checkRemoteForSync(const Paths &p, const Record &record, QString &error, bool recheck) {
    QJsonObject saved;
    if (!unavailableStatus(p, record, saved, error)) return false;
    if (!saved.isEmpty() && !recheck) {
        error = saved.value("error").toString() + " Check again, keep as local, or delete from this device.";
        return false;
    }
    const auto availability = remoteAvailability(record, error);
    if (availability == RemoteAvailability::Available && !recheck) return true;
    const auto message = error;
    QString stored;
    const auto state = availability == RemoteAvailability::Available ? QString("available")
        : availability == RemoteAvailability::Deleted ? QString("deleted") : availability == RemoteAvailability::Unavailable ? QString("unavailable") : QString{};
    if (!status(p, record, false, false, message, stored, state)) { error = stored; return false; }
    return availability == RemoteAvailability::Available;
}
bool recheckRemote(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease; Config config; QJsonObject registry;
    const auto id = request.value("id").toString();
    result = {{"ok", false}, {"id", id}};
    if (!lease.acquire(p, error) || !conversionAllowed(p, id, error) || !loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    QJsonObject profile;
    for (const auto &value : registry.value("profiles").toArray()) if (value.toObject().value("id") == id) profile = value.toObject();
    if (profile.value("type") != "synced" || profile != request.value("expectedProfile") || request.value("expectedRevision") != revision(config.original)) {
        error = "Calendar settings changed; reopen availability check"; return false;
    }
    for (const auto &record : config.records) if (record.id == id) {
        const bool ok = checkRemoteForSync(p, record, error, true);
        result["ok"] = ok; result["available"] = ok;
        return ok;
    }
    error = "Managed synced calendar not found"; return false;
}

bool pauseDaemon(bool &wasActive, QString &error) {
    QProcess process;
    process.start("systemctl", {"--user", "show", "--property=ActiveState", "--value", "pimsync.service"});
    if (!process.waitForStarted(5000) || !process.waitForFinished(10000) || process.exitCode() != 0) {
        process.kill(); process.waitForFinished(5000); error = "Could not inspect calendar daemon"; return false;
    }
    const auto state = process.readAllStandardOutput().trimmed();
    if (state != "active" && state != "inactive" && state != "failed") {
        error = "Calendar daemon is changing state; retry shortly"; return false;
    }
    wasActive = state == "active";
    if (wasActive && !command("systemctl", {"--user", "stop", "pimsync.service"}, 30000)) {
        error = "Could not stop calendar daemon"; return false;
    }
    return true;
}
bool resumeDaemon(bool wasActive, QString &error) {
    if (wasActive && !command("systemctl", {"--user", "start", "--no-block", "pimsync.service"}, 30000)) {
        error = "Could not resume calendar daemon"; return false;
    }
    return true;
}

namespace {
bool syncRecordImpl(const Paths &p, const Record &r, QString &error, bool initial, QByteArray *publishedCache,
                    const QString &attachmentSession, bool *started) {
    if (publishedCache) publishedCache->clear();
    if (attachmentSession.isEmpty()) {
        if (!conversionAllowed(p, r.id, error)) return false;
    } else {
        QJsonObject pause;
        if (!attachmentOwnsSync(p, r, attachmentSession, error) || !remoteDeletionAllowed(p, r.id, error)
            || !readConversionPause(p, r.id, pause, error) || !pause.isEmpty()) return false;
    }
    QJsonObject unavailable;
    if (!unavailableStatus(p, r, unavailable, error)) return false;
    if (!unavailable.isEmpty()) { error = unavailable.value("error").toString(); return false; }
    const bool recovered = command("/bin/sh", {p.broker, "check-recovery"}, 10000);
    if (!recovered) error = "Resolve the pending calendar operation before syncing";
    auto connection = r;
    if (!recovered || !validateConnection(connection, error) || !localState(p, r, initial, error)) {
        QString statusError;
        if (!status(p, r, false, false, error, statusError)) error += "; " + statusError;
        return false;
    }
    if (!status(p, r, true, false, {}, error)) return false;
    if (!checkRemoteForSync(p, r, error)) return false;
    bool ok;
    if (attachmentSession.isEmpty()) ok = command("pimsync", {"-c", p.config, "sync", r.pair()});
    else {
        QProcess process;
        const auto parent = getpid();
        process.setChildProcessModifier([parent] { if (prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent) _exit(1); });
        process.setStandardOutputFile(QProcess::nullDevice()); process.setStandardErrorFile(QProcess::nullDevice());
        process.start("pimsync", {"-c", p.config, "sync", r.pair()});
        if (!process.waitForStarted(5000)) { error = "Could not start initial synchronization"; return false; }
        *started = true;
        ok = process.waitForFinished(90000) && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
        if (!ok) { process.kill(); process.waitForFinished(5000); }
    }
    if (!ok) error = "Synchronization failed; previous cache retained. Check connection or calendar conflicts";
    if (!ok) {
        // ponytail: 0.5.7 uses exit 1 for conflicts and I/O; one capture-only pass on failure, use distinct exit codes when available.
        command("/usr/bin/env", {"CALENDAR_ID=" + r.id, "CALENDAR_CAPTURE_ONLY=1", "/bin/sh", p.broker, "capture", r.pair()}, 60000, true);
    }
    if (ok) {
        QJsonObject conflicts;
        ok = jsonFile(QFileInfo(p.state).path() + "/conflicts-" + r.id + ".json", conflicts, error, true, 616LL * 1024 * 1024);
        if (ok && !conflicts.value("conflicts").toArray().isEmpty()) {
            ok = false; error = "Resolve calendar conflicts before publishing a new cache";
        }
    }
    if (ok) {
        std::string detail;
        CalendarLock lock((p.data + '/' + r.id).toStdString(), detail);
        QTemporaryDir staging(p.state + "/cache-XXXXXX");
        const auto output = staging.path() + "/calendar.sync.json";
        QByteArray bytes;
        ok = lock.acquired() && staging.isValid()
            && rebuildSyncedCache((p.data + '/' + r.id).toStdString(), output.toStdString(), r.id.toStdString(), detail, true)
            && readFile(output, bytes, error, false, 64 * 1024 * 1024);
        if (ok) {
            bool published = false;
            ok = writeFile(p.data + '/' + r.id + ".sync.json", bytes, error, initial, &published);
            if (published && publishedCache) *publishedCache = bytes;
        }
        if (!ok && error.isEmpty()) error = QString::fromStdString(detail.empty() ? "Could not publish complete calendar cache" : detail);
    }
    QString statusError;
    if (!status(p, r, false, ok, error, statusError)) {
        error = statusError; return false;
    }
    return ok;
}
} // namespace
bool syncRecord(const Paths &p, const Record &r, QString &error, bool initial, QByteArray *publishedCache) {
    return syncRecordImpl(p, r, error, initial, publishedCache, {}, nullptr);
}
bool syncAttachmentRecord(const Paths &p, const Record &r, const QString &session, bool &started, QString &error) {
    started = false;
    return syncRecordImpl(p, r, error, false, nullptr, session, &started);
}

bool synchronize(const Paths &p, const QString &id, QJsonObject &result, QString &error) {
    Lease lease;
    Config config;
    if (!lease.acquire(p, error) || !CalDavBackend::loadConfig(p, config, error)) return false;
    for (const auto &r : config.records) if (r.id == id) {
        // Setup verified that this pair is absent from daemon.conf; unrelated feeds stay running.
        const bool ok = syncRecord(p, r, error);
        result = {{"ok", ok}, {"id", id}};
        return ok;
    }
    error = "Synced calendar not found"; return false;
}

int daemon(const Paths &p) {
    Config config;
    QString error;
    if (!CalDavBackend::loadConfig(p, config, error) || !ensureDirectory(p.state, error)) return 1;
    // Native pimsync handles all unmanaged pairs; timer-managed pairs are absent.
    const auto snapshot = p.state + "/daemon.conf";
    if (!writeFile(snapshot, renderConfig(p, config, {}), error)) return 1;
    QProcess process;
    const auto parent = getpid();
    process.setChildProcessModifier([parent] { if (prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent) _exit(1); });
    process.setStandardOutputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
    process.start("pimsync", {"-c", snapshot, "daemon"});
    if (!process.waitForStarted(5000) || !process.waitForFinished(-1)) return 1;
    return process.exitStatus() == QProcess::NormalExit ? process.exitCode() : 1;
}
} // namespace CalDavBackend
