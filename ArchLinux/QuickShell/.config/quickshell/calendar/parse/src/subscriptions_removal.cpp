#include "subscriptions.h"
#include "caldav.h"
#include "removal_files.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QTemporaryDir>
#include <algorithm>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace SubscriptionBackend {
using namespace CalendarRemoval;
namespace {
struct ServiceState {
    bool active = false;
    QString enabled;
};
} // namespace

bool removeLocal(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease;
    QJsonObject registry;
    QByteArray before;
    const auto registryPath = p.data + "/profiles.json";
    if (!lease.acquire(p, error) || !loadRegistry(p, registry, error) || !readFile(registryPath, before, error)) return false;
    if (QJsonDocument::fromJson(before).object() != registry) {
        error = "Calendar profiles changed; confirm removal again"; return false;
    }
    const auto id = request.value("id").toString();
    if (!CalDavBackend::attachmentAllowed(CalDavBackend::paths(), id, error)) return false;
    const auto type = request.value("type").toString("local");
    const auto profiles = registry.value("profiles").toArray();
    const auto selected = std::find_if(profiles.begin(), profiles.end(), [&](const auto &value) { return value.toObject().value("id") == id; });
    if (!validId(id) || (type != "local" && type != "imported") || selected == profiles.end() || selected->toObject().value("type") != type
        || request.value("expectedProfile") != *selected) {
        error = "Local calendar changed or not found; confirm removal again"; return false;
    }
    const auto source = p.data + '/' + id + ".json";
    QStringList sources{source};
    if (type == "imported") sources.prepend(p.data + '/' + id);
    QStringList present;
    for (const auto &path : sources) {
        struct stat stamp{};
        if (lstat(QFile::encodeName(path).constData(), &stamp) != 0) {
            if (errno == ENOENT) continue;
            error = "Could not inspect calendar data: " + path; return false;
        }
        const bool directory = type == "imported" && path != source;
        if (stamp.st_uid != geteuid() || (directory ? !S_ISDIR(stamp.st_mode) : (!S_ISREG(stamp.st_mode) || stamp.st_nlink != 1))) {
            error = "Local calendar data is not an owned regular file or directory: " + path; return false;
        }
        present.append(path);
    }
    QTemporaryDir staging(p.data + "/.calendar-remove-" + id + "-XXXXXX");
    if (!staging.isValid()) { error = "Could not create local removal staging"; return false; }
    QStringList moved;
    staging.setAutoRemove(false); // Never discard the only copy if restoration fails.
    auto rollback = [&] {
        const auto cause = error;
        QString detail;
        bool restored = true;
        for (auto it = moved.crbegin(); it != moved.crend(); ++it)
            if (!move(staging.path() + '/' + QFileInfo(*it).fileName(), *it, detail)) restored = false;
        if (!restored) {
            error = cause + "; rollback incomplete: " + detail + "; retained staging: " + staging.path();
        } else {
            error = cause + "; calendar restored";
            if (!purge(staging.path(), detail)) error += "; temporary cleanup incomplete: " + detail;
        }
        return false;
    };
    for (const auto &path : present) {
        if (!move(path, staging.path() + '/' + QFileInfo(path).fileName(), error)) return rollback();
        moved.append(path);
    }
    QByteArray current;
    if (!readFile(registryPath, current, error)) return rollback();
    if (current != before) { error = "Calendar profiles changed during removal"; return rollback(); }
    QJsonArray remaining;
    for (const auto &value : profiles) if (value.toObject().value("id") != id) remaining.append(value);
    registry["profiles"] = remaining;
    const auto bytes = QJsonDocument(registry).toJson();
    QSaveFile file(registryPath); // Default: no non-atomic direct-write fallback.
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
        error = "Could not update calendar profiles: " + file.errorString(); return rollback();
    }
    result = {{"ok", true}, {"id", id}, {"removed", true}};
    QString detail;
    if (!purge(staging.path(), detail)) {
        result["cleanupWarning"] = true;
        result["message"] = "Calendar removed; temporary cleanup incomplete: " + detail;
    }
    return true;
}

bool remove(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease;
    Config config;
    QJsonObject registry, statuses;
    if (!lease.acquire(p, error) || !loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    const auto id = request.value("id").toString();
    const auto records = registry.value("profiles").toArray();
    const auto selected = std::find_if(records.begin(), records.end(), [&](const auto &v) { return v.toObject().value("id") == id; });
    if (!validId(id) || selected == records.end() || selected->toObject().value("type") != "subscription") {
        error = "URL subscription not found; other calendar types are not removed here"; return false;
    }
    if (request.value("expectedRevision").toString() != revision(config.original)
        || !request.contains("expectedProfile") || request.value("expectedProfile") != *selected) {
        error = "Calendar settings changed; confirm removal again"; return false;
    }
    if (!command("/bin/sh", {p.broker, "check-recovery"}, 10000)) {
        error = "Resolve the pending calendar event operation before removal"; return false;
    }
    const auto statusPath = p.state + "/status.json";
    const auto registryPath = p.data + "/profiles.json";
    if (!jsonFile(statusPath, statuses, error)) return false;
    if (!statuses.isEmpty() && (statuses.value("version") != 1 || !statuses.value("records").isObject())) {
        error = "Subscription status is malformed"; return false;
    }
    Config next = config;
    next.records.erase(std::remove_if(next.records.begin(), next.records.end(), [&](const auto &r) { return r.id == id; }), next.records.end());
    const bool otherPairs = QRegularExpression("(?m)^\\s*pair\\s+").match(QString::fromUtf8(config.prefix + config.suffix)).hasMatch();
    const bool keepDaemon = !next.records.isEmpty() || otherPairs;
    Config inventory = config;
    // Fixed paths need only the registered ID, even when its source/config is already gone.
    for (const auto &value : records) {
        const auto profile = value.toObject();
        const auto knownId = profile.value("id").toString();
        if (profile.value("type") == "subscription" && std::none_of(inventory.records.begin(), inventory.records.end(),
            [&](const auto &record) { return record.id == knownId; })) inventory.records.append({knownId, {}});
    }
    const auto oldUnits = unitDefinitions(p, inventory);
    const auto nextUnits = unitDefinitions(p, next);
    QMap<QString, Snapshot> before;
    for (const auto &path : QStringList{p.config, registryPath, statusPath} + [&] {
        QStringList paths; for (const auto &name : oldUnits.keys()) paths.append(p.units + '/' + name); return paths;
    }()) {
        Snapshot copy;
        if (!readFile(path, copy.bytes, error, true)) return false;
        struct stat stamp{};
        copy.exists = lstat(QFile::encodeName(path).constData(), &stamp) == 0;
        if (copy.exists) copy.mode = stamp.st_mode & 0777;
        before[path] = copy;
    }
    if (before[p.config].bytes != config.original) { error = "Calendar configuration changed; confirm removal again"; return false; }
    QMap<QString, QByteArray> writes;
    if (before[p.config].exists) writes[p.config] = renderConfig(p, next, next.records);
    QSet<QString> deletes;
    for (auto it = oldUnits.begin(); it != oldUnits.end(); ++it) {
        const auto path = p.units + '/' + it.key();
        const auto &old = before[path];
        const bool daemonFile = it.key().startsWith("pimsync.service");
        const bool needed = daemonFile ? keepDaemon : !next.records.isEmpty();
        const auto unmarked = it.value().mid(it.value().indexOf('\n') + 1);
        bool matches = !old.exists || old.bytes == it.value() || old.bytes == unmarked;
        if (!matches && it.key() == "quickshell-calendar-import.path")
            matches = watcherSignature(old.bytes) == watcherSignature(it.value()) || watcherSignature(old.bytes) == watcherSignature(unmarked);
        if (!needed) {
            // An existing host-defined daemon is not ours to delete.
            if (it.key() == "pimsync.service" && !matches) continue;
            if (!matches) { error = "Calendar unit has custom settings; it was not deleted: " + it.key(); return false; }
            deletes.insert(path);
        } else if (it.key() == "quickshell-calendar-import.path") {
            if (!matches) { error = "Calendar watcher has custom settings; it was not overwritten"; return false; }
            writes[path] = nextUnits.value(it.key());
        }
    }
    auto remainingStatuses = statuses.value("records").toObject();
    remainingStatuses.remove(id);
    if (remainingStatuses.isEmpty()) deletes.insert(statusPath);
    else {
        statuses["records"] = remainingStatuses;
        writes[statusPath] = QJsonDocument(statuses).toJson();
    }
    QJsonArray remainingProfiles;
    for (const auto &value : records) if (value.toObject().value("id") != id) remainingProfiles.append(value);
    registry["profiles"] = remainingProfiles;
    writes[registryPath] = QJsonDocument(registry).toJson();

    const auto units = unitNames(inventory);
    QMap<QString, ServiceState> services;
    for (const auto &unit : units) {
        QString active;
        ServiceState state;
        if (!property(unit, "ActiveState", active, error) || !property(unit, "UnitFileState", state.enabled, error)) return false;
        if (active != "active" && active != "inactive" && active != "failed") {
            error = "Calendar service is busy; try removal when it finishes"; return false;
        }
        state.active = active == "active";
        services[unit] = state;
    }
    QMap<QString, QString> staging;
    QMap<QString, QByteArray> removedLinks;
    QList<QPair<QString, QString>> moved;
    QStringList changed, disabled;
    bool definitionsChanged = false, resumed = false;
    auto purgeStaging = [&] {
        QStringList failures;
        for (const auto &directory : staging) { QString detail; if (!purge(directory, detail)) failures.append(detail); }
        return failures;
    };
    auto start = [&](const QString &unit) {
        QStringList args{"--user", "start"};
        // The cache helper waits for this operation's lease; never wait for it here.
        if (unit == "quickshell-calendar-import.service") args.append("--no-block");
        args.append(unit);
        return command("systemctl", args, 30000);
    };
    // ponytail: in-process rollback only; no durable journal or crash recovery.
    auto rollback = [&] {
        const auto cause = error;
        QStringList failures;
        if (resumed) for (const auto &unit : units) if (services[unit].active
            && !command("systemctl", {"--user", "stop", unit}, 30000)) failures.append("Could not stop " + unit);
        if (failures.isEmpty()) {
            for (auto it = moved.crbegin(); it != moved.crend(); ++it) {
                QString detail; if (!move(it->second, it->first, detail)) failures.append(detail);
            }
            for (auto it = changed.crbegin(); it != changed.crend(); ++it) {
                const auto &copy = before[*it];
                QString detail;
                QByteArray actual;
                if (!readFile(*it, actual, detail, true)
                    || (actual != copy.bytes && actual != writes.value(*it))) {
                    failures.append("Newer file contents preserved: " + *it); continue;
                }
                if (actual == copy.bytes && QFileInfo::exists(*it) == copy.exists) continue;
                if (!(copy.exists ? publish(*it, copy.bytes, copy.mode, detail) : erase(*it, detail))) failures.append(detail);
            }
            for (const auto &unit : disabled) {
                QStringList args{"--user", "enable", "--no-reload"};
                if (services[unit].enabled == "enabled-runtime") args.append("--runtime");
                args.append(unit);
                if (!command("systemctl", args, 15000)) failures.append("Could not restore enablement: " + unit);
            }
            for (auto it = removedLinks.begin(); it != removedLinks.end(); ++it) {
                std::error_code code;
                const auto target = std::filesystem::read_symlink(QFile::encodeName(it.key()).constData(), code);
                if (!code && QByteArray::fromStdString(target.native()) == it.value()) continue;
                if (code != std::errc::no_such_file_or_directory) {
                    failures.append("Changed enablement entry preserved: " + it.key()); continue;
                }
                if (::symlink(it.value().constData(), QFile::encodeName(it.key()).constData()) != 0)
                    failures.append("Could not restore " + it.key() + ": " + QString::fromLocal8Bit(strerror(errno)));
            }
            if (definitionsChanged && !command("systemctl", {"--user", "daemon-reload"}, 15000)) failures.append("Could not reload previous calendar units");
            if (failures.isEmpty()) for (const auto &unit : units) if (services[unit].active && !start(unit)) failures.append("Could not resume " + unit);
        }
        if (failures.isEmpty()) failures = purgeStaging();
        if (failures.isEmpty()) error = cause + "; calendar restored";
        else {
            error = cause + "; rollback incomplete: " + failures.join("; ");
            if (!staging.isEmpty()) error += "; retained staging: " + QStringList(staging.values()).join(", ");
        }
        return false;
    };
    for (const auto &unit : units) if (services[unit].active && !command("systemctl", {"--user", "stop", unit}, 30000)) {
        error = "Could not stop " + unit + " before removal"; return rollback();
    }
    auto stage = [&](const QString &path, bool directory) {
        struct stat stamp{};
        if (lstat(QFile::encodeName(path).constData(), &stamp) != 0) {
            if (errno == ENOENT) return true;
            error = "Could not inspect " + path + ": " + QString::fromLocal8Bit(strerror(errno)); return false;
        }
        if (stamp.st_uid != geteuid() || (directory ? !S_ISDIR(stamp.st_mode) : (!S_ISREG(stamp.st_mode) || stamp.st_nlink != 1))) {
            error = "Calendar resource is not an owned " + QString(directory ? "directory: " : "regular file: ") + path; return false;
        }
        const auto parent = QFileInfo(path).path();
        if (!ensureDirectory(parent, error)) return false;
        if (!staging.contains(parent)) {
            QTemporaryDir temporary(parent + "/.calendar-remove-" + id + "-XXXXXX");
            if (!temporary.isValid()) { error = "Could not create temporary removal staging"; return false; }
            temporary.setAutoRemove(false); // Never discard recoverable data on a failed restore.
            staging[parent] = temporary.path();
        }
        const auto destination = staging[parent] + '/' + QFileInfo(path).fileName();
        if (!move(path, destination, error)) return false;
        moved.append({path, destination});
        return true;
    };
    if (!stage(p.data + '/' + id, true) || !stage(p.data + '/' + id + ".json", false)) return rollback();
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"})
        if (!stage(p.status + '/' + Record{id, {}}.pair() + ".status" + suffix, false)) return rollback();

    for (const auto &unit : units) {
        const auto definition = p.units + '/' + unit;
        if (!deletes.contains(definition)) continue;
        if (!before[definition].exists) {
            // disable fails for missing definitions; remove only our known install links.
            QStringList roots{p.units};
            const auto runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
            if (!runtime.isEmpty()) roots.append(runtime + "/systemd/user");
            for (const auto &root : roots) {
                const auto link = root + "/default.target.wants/" + unit;
                const QFileInfo info(link);
                struct stat stamp{};
                if (lstat(QFile::encodeName(link).constData(), &stamp) != 0) {
                    if (errno == ENOENT) continue;
                    error = "Could not read " + link + ": " + QString::fromLocal8Bit(strerror(errno)); return rollback();
                }
                if (!S_ISLNK(stamp.st_mode) || stamp.st_uid != geteuid()) continue;
                std::error_code code;
                const auto target = std::filesystem::read_symlink(QFile::encodeName(link).constData(), code);
                if (code) { error = "Could not read " + link + ": " + QString::fromStdString(code.message()); return rollback(); }
                const auto raw = QByteArray::fromStdString(target.native());
                if (QDir::cleanPath(QDir(info.path()).absoluteFilePath(QString::fromLocal8Bit(raw))) != definition) continue;
                removedLinks[link] = raw;
                definitionsChanged = true;
                if (!erase(link, error)) return rollback();
            }
            continue;
        }
        if (services[unit].enabled != "enabled" && services[unit].enabled != "enabled-runtime") continue;
        disabled.append(unit);
        if (!command("systemctl", {"--user", "disable", "--no-reload", unit}, 15000)) {
            error = "Could not disable unused " + unit; return rollback();
        }
    }
    auto apply = [&](const QString &path) {
        const auto &copy = before[path];
        QByteArray actual;
        if (!readFile(path, actual, error, true) || actual != copy.bytes || QFileInfo::exists(path) != copy.exists) {
            error = "Calendar file changed during removal; newer contents preserved: " + path; return false;
        }
        const bool deleting = deletes.contains(path);
        if (deleting ? !copy.exists : (copy.exists && actual == writes[path])) return true;
        changed.append(path);
        definitionsChanged = definitionsChanged || path.startsWith(p.units + '/');
        return deleting ? erase(path, error) : publish(path, writes[path], copy.mode, error);
    };
    for (const auto &path : writes.keys() + deletes.values()) if (path != registryPath && !apply(path)) return rollback();
    if (definitionsChanged && !command("systemctl", {"--user", "daemon-reload"}, 15000)) {
        error = "Could not load updated calendar units"; return rollback();
    }
    if (!apply(registryPath)) return rollback();
    resumed = true;
    for (const auto &unit : units) {
        const bool needed = unit == "pimsync.service" ? keepDaemon : !next.records.isEmpty();
        if (needed && services[unit].active && !start(unit)) { error = "Could not resume " + unit; return rollback(); }
    }
    // Commit: source data and shared runtime are settled before irreversible purge.
    const auto failures = purgeStaging();
    result = {{"ok", true}, {"id", id}, {"removed", true}};
    if (!failures.isEmpty()) {
        result["cleanupWarning"] = true;
        result["message"] = "Calendar removed; temporary cleanup incomplete: " + failures.join("; ");
    }
    return true;
}
} // namespace SubscriptionBackend
