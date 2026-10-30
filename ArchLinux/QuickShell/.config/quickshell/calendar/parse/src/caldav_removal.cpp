#include "caldav.h"
#include "caldav_remote.h"
#include "calendar_lock.h"
#include "removal_files.h"
#include <QDir>
#include <QDirIterator>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSet>
#include <QTemporaryDir>
#include <algorithm>
#include <memory>

namespace CalDavBackend {
using namespace SubscriptionBackend;
using namespace CalendarRemoval;
namespace {
bool present(const QString &path) { return QFileInfo::exists(path) || QFileInfo(path).isSymLink(); }
bool snapshot(const QString &path, Snapshot &copy, QString &error) {
    if (!readFile(path, copy.bytes, error, true)) return false;
    struct stat stamp{};
    copy.exists = lstat(QFile::encodeName(path).constData(), &stamp) == 0;
    if (copy.exists) copy.mode = stamp.st_mode & 0777;
    return true;
}
bool matches(const QString &path, const Snapshot &copy, QString &error) {
    Snapshot current;
    if (!snapshot(path, current, error)) return false;
    if (current.bytes == copy.bytes && current.exists == copy.exists && (!copy.exists || current.mode == copy.mode)) return true;
    error = "Calendar file changed during removal; newer contents preserved: " + path;
    return false;
}
bool idle(const QString &unit, bool &active, QString &error, bool worker = false) {
    QString state;
    if (!property(unit, "ActiveState", state, error)) return false;
    active = state == "active";
    if (state != "active" && state != "inactive" && state != "failed") {
        error = "Calendar service is busy; try removal when it finishes: " + unit; return false;
    }
    if (worker && active) {
        error = "Synchronization in progress. Try removing this calendar when it finishes."; return false;
    }
    return true;
}
bool ownedResource(const QString &path, bool directory, QString &error) {
    // Reuse existing ancestor validation without creating missing target directories.
    if (present(QFileInfo(path).path()) && !ensureDirectory(QFileInfo(path).path(), error)) return false;
    struct stat stamp{};
    if (lstat(QFile::encodeName(path).constData(), &stamp) != 0) {
        if (errno == ENOENT) return true;
        error = "Could not inspect calendar resource: " + path; return false;
    }
    if (stamp.st_uid != geteuid() || (directory ? !S_ISDIR(stamp.st_mode) : (!S_ISREG(stamp.st_mode) || stamp.st_nlink != 1))) {
        error = "Calendar resource is not an owned " + QString(directory ? "directory: " : "regular file: ") + path; return false;
    }
    if (directory) {
        QDirIterator entries(path, QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (entries.hasNext()) {
            const auto child = entries.next();
            if (lstat(QFile::encodeName(child).constData(), &stamp) != 0 || stamp.st_uid != geteuid()
                || (!S_ISDIR(stamp.st_mode) && (!S_ISREG(stamp.st_mode) || stamp.st_nlink != 1))) {
                error = "Calendar contains an unsafe resource; no files were deleted: " + child; return false;
            }
        }
    }
    return true;
}
bool customDropins(const QString &unitPath, QString &error) {
    const auto directory = unitPath + ".d";
    if (!present(directory)) return false;
    if (QFileInfo(directory).isSymLink() || !QFileInfo(directory).isDir()
        || !QDir(directory).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot).isEmpty()) {
        error = "Calendar unit has custom drop-ins; inspect before removal: " + directory; return true;
    }
    return false;
}
bool structuralConfig(const QByteArray &bytes, QString &structure, QString &error) {
    // Exact managed sections are parsed by their existing loaders. Reject ambiguous
    // outer structure without evaluating storages/password commands through pimsync.
    structure = QString::fromUtf8(bytes);
    structure.remove(QRegularExpression("\"(?:[^\"\\\\]|\\\\.)*\"|#[^\\n]*|//[^\\n]*|/\\*[\\s\\S]*?\\*/"));
    int depth = 0;
    bool valid = !structure.contains('"') && !structure.contains("/*");
    for (const auto ch : structure) {
        if (ch == '{') ++depth;
        else if (ch == '}') --depth;
        if (depth < 0 || depth > 32) valid = false;
    }
    if (valid && depth == 0) return true;
    error = "Pimsync configuration structure is ambiguous; no files were deleted";
    return false;
}
} // namespace

struct RemoteRetirementPlan {
    QMap<QString, Snapshot> before;
    QMap<QString, QByteArray> writes;
    QSet<QString> deletes;
    QList<QPair<QString, bool>> resources;
    bool keepCalDav = false, keepDaemon = false, keepWatcher = false;
    bool daemonActive = false, watcherActive = false;
};

static bool retire(const Paths &p, const QJsonObject &request, const QString *localPath, bool checkOnly,
                   const QJsonObject &expectedSources, QJsonObject &result, QString &error,
                   RemoteRetirementPlan *remotePlan = nullptr, const QJsonObject *operation = nullptr) {
    Config config;
    QJsonObject registry, statuses;
    if (!CalDavBackend::loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    const auto id = request.value("id").toString();
    const auto profiles = registry.value("profiles").toArray();
    const auto selected = std::find_if(profiles.begin(), profiles.end(), [&](const auto &value) { return value.toObject().value("id") == id; });
    if (!validId(id) || selected == profiles.end() || (!operation && selected->toObject().value("type") != "synced")) {
        error = "Synced calendar not found; other calendar types are not removed here"; return false;
    }
    auto originalProfile = operation ? operation->value("profile").toObject() : QJsonObject{};
    auto localProfile = originalProfile; localProfile["type"] = "local";
    if (operation) {
        const auto target = std::find_if(config.records.begin(), config.records.end(), [&](const auto &record) { return record.id == id; });
        const bool beforeDelete = QStringList{"preparing", "review", "ready"}.contains(operation->value("phase").toString());
        if ((*selected != originalProfile && *selected != localProfile) || (beforeDelete && (target == config.records.end() || *selected != originalProfile))
            || (target != config.records.end() && recordJson(*target) != operation->value("target"))) {
            error = "Remote retirement target changed; unrelated settings preserved"; return false;
        }
    } else if (request.value("expectedRevision").toString() != revision(config.original)
        || !request.contains("expectedProfile") || request.value("expectedProfile") != *selected) {
        error = "Calendar settings changed; confirm removal again"; return false;
    }
    const auto collection = p.data + '/' + id;
    if (!command("/bin/sh", {p.broker, "check-recovery"}, 10000) || present(collection + "/.calendar-series-transaction.json")) {
        error = "Resolve the pending calendar event operation before removal"; return false;
    }
    const auto registryPath = p.data + "/profiles.json", statusPath = p.state + "/status.json";
    if (!jsonFile(statusPath, statuses, error)) return false;
    if (!statuses.isEmpty() && (statuses.size() != 2 || statuses.value("version") != 1 || !statuses.value("records").isObject())) {
        error = "Calendar synchronization status is malformed"; return false;
    }
    Config next = config, inventory = config;
    if (operation && std::none_of(inventory.records.begin(), inventory.records.end(), [&](const auto &record) { return record.id == id; }))
        inventory.records.append(recordFromJson(operation->value("target").toObject()));
    next.records.erase(std::remove_if(next.records.begin(), next.records.end(), [&](const auto &r) { return r.id == id; }), next.records.end());
    for (const auto &value : profiles) {
        const auto profile = value.toObject();
        if (profile.value("type") == "synced" && std::none_of(inventory.records.begin(), inventory.records.end(),
            [&](const auto &r) { return r.id == profile.value("id").toString(); })) {
            Record missing; missing.id = profile.value("id").toString();
            QByteArray timerBytes;
            if (!readFile(p.units + "/quickshell-calendar-caldav-" + missing.id + ".timer", timerBytes, error, true)) return false;
            const auto interval = QRegularExpression("(?m)^OnUnitInactiveSec=([0-9]+)s$").match(QString::fromUtf8(timerBytes));
            bool integer = false;
            const auto seconds = interval.captured(1).toInt(&integer);
            if (integer && seconds >= 300) missing.interval = seconds;
            inventory.records.append(missing); // Exact rendering below still rejects all custom directives.
        }
    }
    const bool keepCalDav = std::any_of(inventory.records.begin(), inventory.records.end(), [&](const auto &r) { return r.id != id; });
    auto shared = SubscriptionBackend::paths();
    SubscriptionBackend::Config subscriptions;
    if (!SubscriptionBackend::loadConfig(shared, subscriptions, error)) return false;
    if (subscriptions.original != config.original) { error = "Calendar configuration changed; confirm removal again"; return false; }
    if (std::any_of(subscriptions.records.begin(), subscriptions.records.end(), [&](const auto &r) { return r.id == id; })) {
        error = "A URL subscription still uses this calendar collection; no files were deleted"; return false;
    }
    bool keepWatcher = !subscriptions.records.isEmpty();
    for (const auto &value : profiles) keepWatcher = keepWatcher || value.toObject().value("type") == "subscription";
    auto unmanaged = renderConfig(p, config, {});
    const auto ownedUrls = subscriptions.original.mid(subscriptions.prefix.size(),
        subscriptions.original.size() - subscriptions.prefix.size() - subscriptions.suffix.size());
    if (!ownedUrls.isEmpty()) {
        const auto offset = unmanaged.indexOf(ownedUrls);
        if (offset < 0) { error = "Calendar configuration ownership is ambiguous"; return false; }
        unmanaged.remove(offset, ownedUrls.size());
    }
    QString structure;
    if (!structuralConfig(unmanaged, structure, error)) return false;
    const auto external = QString::fromUtf8(unmanaged);
    const bool selectsCollection = QRegularExpression("(?m)(?:^|[;{])\\s*(?:collection|collection_id|id_a|id_b|alias)\\s+\"?"
        + QRegularExpression::escape(id) + "\"?(?=\\s|[{};]|$)").match(external).hasMatch();
    const bool enumeratesCollections = QRegularExpression("\\bcollections\\s+").match(external).hasMatch();
    if (unmanaged.contains(("qs_caldav_local_" + id).toUtf8()) || unmanaged.contains(("qs_caldav_remote_" + id).toUtf8())
        || unmanaged.contains(collection.toUtf8()) || (unmanaged.contains(p.data.toUtf8()) && (selectsCollection || enumeratesCollections))) {
        error = "Unmanaged configuration may depend on this calendar; no files were deleted"; return false;
    }
    const bool keepDaemon = keepCalDav || keepWatcher || QRegularExpression("\\bpair\\s+").match(structure).hasMatch();
    auto oldUnits = CalDavBackend::unitDefinitions(p, inventory);
    auto watcherInventory = subscriptions;
    if (!keepWatcher) {
        QByteArray watcher;
        if (!readFile(p.units + "/quickshell-calendar-import.path", watcher, error, true)) return false;
        const auto prefix = ("PathChanged=" + QString(p.data).replace("%", "%%") + '/').toUtf8();
        QSet<QString> seen;
        for (const auto &line : watcher.split('\n')) if (line.startsWith(prefix)) {
            const auto knownId = QString::fromUtf8(line.mid(prefix.size()));
            if (validId(knownId) && !seen.contains(knownId)) { seen.insert(knownId); watcherInventory.records.append(SubscriptionBackend::Record{knownId, {}}); }
        }
    }
    if (watcherInventory.records.isEmpty()) watcherInventory.records.append(SubscriptionBackend::Record{"caldav", {}}); // Shared definitions are independent of source URL.
    const auto urlUnits = SubscriptionBackend::unitDefinitions(shared, watcherInventory);
    for (auto it = urlUnits.begin(); it != urlUnits.end(); ++it) if (!oldUnits.contains(it.key())) oldUnits[it.key()] = it.value();

    QMap<QString, Snapshot> before;
    for (const auto &path : QStringList{p.config, registryPath, statusPath} + [&] {
        QStringList paths; for (const auto &name : oldUnits.keys()) paths.append(p.units + '/' + name); return paths;
    }()) if (!snapshot(path, before[path], error)) return false;
    if (before[p.config].bytes != config.original || QJsonDocument::fromJson(before[registryPath].bytes).object() != registry) {
        error = "Calendar settings changed; confirm removal again"; return false;
    }
    // A custom daemon/retained guard may still require the derived CalDAV config.
    if (!keepCalDav) for (const auto &name : QStringList{"pimsync.service", "pimsync.service.d/calendar-group-recovery.conf"}) {
        const auto copy = before.value(p.units + '/' + name);
        const auto definition = oldUnits.value(name);
        if (copy.exists && copy.bytes != definition && copy.bytes != definition.mid(definition.indexOf('\n') + 1)) {
            error = "Calendar daemon has custom routing; inspect dependencies before removal"; return false;
        }
    }

    QMap<QString, QByteArray> writes;
    if (before[p.config].exists) writes[p.config] = renderConfig(p, next, next.records);
    auto remainingStatuses = statuses.value("records").toObject();
    remainingStatuses.remove(id);
    QSet<QString> deletes;
    if (remainingStatuses.isEmpty()) deletes.insert(statusPath);
    else { statuses["records"] = remainingStatuses; writes[statusPath] = QJsonDocument(statuses).toJson(); }
    QJsonArray remainingProfiles;
    for (const auto &value : profiles) {
        if (value.toObject().value("id") != id) remainingProfiles.append(value);
        else if (localPath) { auto profile = value.toObject(); profile["type"] = "local"; remainingProfiles.append(profile); }
    }
    registry["profiles"] = remainingProfiles;
    writes[registryPath] = QJsonDocument(registry).toJson();
    const auto timer = "quickshell-calendar-caldav-" + id + ".timer";
    for (auto it = oldUnits.begin(); it != oldUnits.end(); ++it) {
        const auto &name = it.key();
        bool needed = true;
        if (name == timer) needed = false;
        else if (name == "quickshell-calendar-caldav@.service" || name == "pimsync.service.d/calendar-caldav.conf") needed = keepCalDav;
        else if (name.startsWith("pimsync.service")) needed = keepDaemon;
        else if (name.startsWith("quickshell-calendar-import.")) needed = keepWatcher;
        if (needed) {
            if (operation && !before.value(p.units + '/' + name).exists) writes[p.units + '/' + name] = it.value();
            continue;
        }
        const auto path = p.units + '/' + name;
        const auto copy = before[path];
        const auto unmarked = it.value().mid(it.value().indexOf('\n') + 1);
        bool owned = !copy.exists || copy.bytes == it.value() || copy.bytes == unmarked;
        if (!owned && name == "quickshell-calendar-import.path")
            owned = watcherSignature(copy.bytes) == watcherSignature(it.value()) || watcherSignature(copy.bytes) == watcherSignature(unmarked);
        if (!owned) {
            error = "Calendar unit has custom settings; it was not deleted: " + name; return false;
        }
        if (name != "pimsync.service" && customDropins(path, error)) return false;
        deletes.insert(path);
    }
    if (!keepCalDav) {
        // Unknown host overrides may still reference the derived config or template.
        const QDir dropins(p.units + "/pimsync.service.d");
        for (const auto &name : dropins.entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot))
            if (name != "calendar-caldav.conf" && name != "calendar-group-recovery.conf") {
                error = "Calendar daemon has custom drop-ins; inspect dependencies before removal"; return false;
            }
        deletes.insert(p.state + "/daemon.conf");
        // Derived config is disposable; do not parse/read potentially stale contents.
    }

    QList<QPair<QString, bool>> resources{{collection, true}, {collection + ".sync.json", false},
        {QFileInfo(p.state).path() + "/conflicts-" + id + ".json", false}};
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) resources.append({p.status + "/qs_caldav_" + id + ".status" + suffix, false});
    for (const auto &path : deletes) resources.append({path, false});
    QMap<QString, struct stat> resourceStamps;
    for (const auto &resource : resources) {
        if (!ownedResource(resource.first, resource.second, error)) return false;
        struct stat stamp{};
        if (lstat(QFile::encodeName(resource.first).constData(), &stamp) != 0 && errno != ENOENT) {
            error = "Could not inspect calendar resource: " + resource.first; return false;
        }
        resourceStamps[resource.first] = stamp;
    }
    std::unique_ptr<CalendarLock> collectionLock;
    if (present(collection) && !operation) {
        std::string detail;
        collectionLock = std::make_unique<CalendarLock>(collection.toStdString(), detail);
        if (!collectionLock->acquired()) { error = "Calendar is busy; try removal when the event operation finishes"; return false; }
    }
    bool timerActive = false, daemonActive = false, workerActive = false, watcherActive = false;
    if ((!operation && (!idle("quickshell-calendar-caldav@" + id + ".service", workerActive, error, true) || !idle(timer, timerActive, error)))
        || (!keepCalDav && (!operation || before.value(p.units + "/pimsync.service").exists) && !idle("pimsync.service", daemonActive, error))) return false;
    if (!keepWatcher && (!operation || before.value(p.units + "/quickshell-calendar-import.path").exists)
        && (!idle("quickshell-calendar-import.service", workerActive, error, true) || !idle("quickshell-calendar-import.path", watcherActive, error))) return false;
    if (checkOnly) {
        // Conversion verifies retirement dependencies before making server changes.
        QStringList roots{p.units};
        const auto runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
        if (!runtime.isEmpty()) roots.append(runtime + "/systemd/user");
        for (const auto &path : deletes) if (path.startsWith(p.units + '/') && !path.contains(".service.d/")) {
            const auto name = QFileInfo(path).fileName();
            for (const auto &root : roots) {
                const auto link = root + (name.endsWith(".timer") ? "/timers.target.wants/" : "/default.target.wants/") + name;
                if (!present(link)) continue;
                struct stat stamp{}; std::error_code code;
                const auto raw = std::filesystem::read_symlink(QFile::encodeName(link).constData(), code);
                if (lstat(QFile::encodeName(link).constData(), &stamp) != 0 || !S_ISLNK(stamp.st_mode) || stamp.st_uid != geteuid() || code
                    || QDir::cleanPath(QDir(QFileInfo(link).path()).absoluteFilePath(QString::fromStdString(raw.native()))) != path) {
                    error = "Calendar enablement link has custom settings; preserved: " + link; return false;
                }
            }
        }
        if (remotePlan) *remotePlan = {before, writes, deletes, resources, keepCalDav, keepDaemon, keepWatcher, daemonActive, watcherActive};
        return true;
    }

    bool localPublished = false;
    QString activationError;
    const auto localTarget = p.data + '/' + id + ".json";
    if (localPath) {
        QByteArray bytes;
        if (!readFile(*localPath, bytes, error, false, 64 * 1024 * 1024)) return false;
        // Keep staged result even if publication fails; safe disconnection can still finish forward.
        writeFile(localTarget, bytes, activationError, true, &localPublished);
    }

    QMap<QString, QString> staging;
    QList<QPair<QString, QString>> moved;
    QStringList changed;
    bool timerStopped = false, watcherStopped = false, daemonStopped = false, daemonResumed = false, definitionsChanged = false;
    auto directoryFor = [&](const QString &parent) {
        if (!staging.contains(parent)) {
            QTemporaryDir temporary(parent + "/.calendar-remove-" + id + "-XXXXXX");
            if (!temporary.isValid()) { error = "Could not create temporary removal staging"; return QString{}; }
            temporary.setAutoRemove(false);
            staging[parent] = temporary.path();
        }
        return staging[parent];
    };
    auto stage = [&](const QString &path) {
        if (!present(path)) return true;
        const auto destination = directoryFor(QFileInfo(path).path());
        if (destination.isEmpty() || !move(path, destination + '/' + QFileInfo(path).fileName(), error)) return false;
        moved.append({path, destination + '/' + QFileInfo(path).fileName()});
        definitionsChanged = definitionsChanged || path.startsWith(p.units + '/') || path.contains("/systemd/user/");
        return true;
    };
    QString retainedSources;
    auto purgeStaging = [&] {
        QStringList failures;
        for (const auto &directory : staging) {
            if (directory == retainedSources) { failures.append("Newer calendar sources preserved: " + directory); continue; }
            QString detail; if (!purge(directory, detail)) failures.append(detail);
        }
        return failures;
    };
    auto start = [&](const QString &unit) { return command("systemctl", {"--user", "start", unit}, 30000); };
    // ponytail: ordinary-error rollback only; process/power loss requires inspecting retained staging, not a new journal.
    auto rollback = [&] {
        const auto cause = error;
        QStringList failures;
        if (daemonResumed && !command("systemctl", {"--user", "stop", "pimsync.service"}, 30000)) failures.append("Could not pause daemon for rollback");
        if (failures.isEmpty()) {
            for (auto it = changed.crbegin(); it != changed.crend(); ++it) {
                Snapshot current;
                QString detail;
                const auto &copy = before[*it];
                if (!snapshot(*it, current, detail) || (current.exists && current.bytes != writes[*it] && current.bytes != copy.bytes)) {
                    failures.append("Newer file contents preserved: " + *it); continue;
                }
                if (current.exists == copy.exists && current.bytes == copy.bytes && current.mode == copy.mode) continue;
                if (!(copy.exists ? publish(*it, copy.bytes, copy.mode, detail) : erase(*it, detail))) failures.append(detail);
            }
            for (auto it = moved.crbegin(); it != moved.crend(); ++it) {
                QString detail;
                if (!move(it->second, it->first, detail)) failures.append(detail);
            }
            if (definitionsChanged && !command("systemctl", {"--user", "daemon-reload"}, 15000)) failures.append("Could not reload previous calendar units");
            if (failures.isEmpty() && daemonStopped && daemonActive && !start("pimsync.service")) failures.append("Could not resume previous calendar daemon");
            if (failures.isEmpty() && timerStopped && timerActive && !start(timer)) failures.append("Could not resume previous calendar timer");
            if (failures.isEmpty() && watcherStopped && watcherActive && !start("quickshell-calendar-import.path")) failures.append("Could not resume previous calendar watcher");
        }
        if (failures.isEmpty()) failures = purgeStaging();
        error = cause + (failures.isEmpty() ? "; calendar restored" : "; rollback incomplete: " + failures.join("; ")
            + "; retained staging: " + QStringList(staging.values()).join(", "));
        return false;
    };
    if (timerActive) {
        timerStopped = true;
        if (!command("systemctl", {"--user", "stop", timer}, 30000)) { error = "Could not stop calendar timer"; return rollback(); }
    }
    if (watcherActive) {
        watcherStopped = true;
        if (!command("systemctl", {"--user", "stop", "quickshell-calendar-import.path"}, 30000)) { error = "Could not stop unused calendar watcher"; return rollback(); }
    }
    if (!keepCalDav && daemonActive) {
        daemonStopped = true;
        if (!command("systemctl", {"--user", "stop", "pimsync.service"}, 30000)) { error = "Could not stop calendar daemon"; return rollback(); }
    }
    // Stage only exact install links whose raw target resolves to the managed definition.
    QStringList unitRoots{p.units};
    const auto runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty()) unitRoots.append(runtime + "/systemd/user");
    for (const auto &path : deletes) if (path.startsWith(p.units + '/') && !path.contains(".service.d/")) {
        const auto name = QFileInfo(path).fileName();
        const auto target = name.endsWith(".timer") ? "timers.target.wants/" : "default.target.wants/";
        for (const auto &root : unitRoots) {
            const auto link = root + '/' + target + name;
            if (!present(link)) continue;
            if (!ensureDirectory(QFileInfo(link).path(), error)) return rollback();
            struct stat stamp{};
            std::error_code code;
            const auto raw = std::filesystem::read_symlink(QFile::encodeName(link).constData(), code);
            if (lstat(QFile::encodeName(link).constData(), &stamp) != 0 || !S_ISLNK(stamp.st_mode) || stamp.st_uid != geteuid() || code
                || QDir::cleanPath(QDir(QFileInfo(link).path()).absoluteFilePath(QString::fromStdString(raw.native()))) != path) {
                error = "Calendar enablement link has custom settings; it was not removed: " + link; return rollback();
            }
            if (!stage(link)) return rollback();
        }
    }
    for (const auto &resource : resources) {
        const auto &stamp = resourceStamps[resource.first];
        struct stat current{};
        const bool exists = lstat(QFile::encodeName(resource.first).constData(), &current) == 0;
        if (exists != (stamp.st_ino != 0) || (exists && (stamp.st_dev != current.st_dev || stamp.st_ino != current.st_ino
            || stamp.st_mode != current.st_mode || stamp.st_uid != current.st_uid || stamp.st_gid != current.st_gid
            || (!resource.second && (stamp.st_size != current.st_size || stamp.st_nlink != current.st_nlink
                || stamp.st_mtim.tv_sec != current.st_mtim.tv_sec || stamp.st_mtim.tv_nsec != current.st_mtim.tv_nsec
                || stamp.st_ctim.tv_sec != current.st_ctim.tv_sec || stamp.st_ctim.tv_nsec != current.st_ctim.tv_nsec))))) {
            error = "Calendar resource changed during removal; newer contents preserved: " + resource.first; return rollback();
        }
        if (before.contains(resource.first) && !matches(resource.first, before[resource.first], error)) return rollback();
        if (!stage(resource.first)) return rollback();
    }
    auto apply = [&](const QString &path) {
        const auto &copy = before[path];
        if (!matches(path, copy, error)) return false;
        if (copy.exists && copy.bytes == writes[path]) return true;
        const auto directory = directoryFor(QFileInfo(path).path());
        if (directory.isEmpty()) return false;
        // Small shared-file backups survive an incomplete rollback; whole collections are moved, never copied.
        if (copy.exists && !publish(directory + '/' + QFileInfo(path).fileName(), copy.bytes, copy.mode, error)) return false;
        bool published = false;
        const bool ok = writeFile(path, writes[path], error, !copy.exists, &published);
        if (published) changed.append(path);
        if (!ok) return false;
        if (chmod(QFile::encodeName(path).constData(), copy.mode) != 0) { error = "Could not preserve calendar file mode: " + path; return false; }
        return true;
    };
    for (const auto &path : writes.keys()) if (path != registryPath && !apply(path)) return rollback();
    if (definitionsChanged && !command("systemctl", {"--user", "daemon-reload"}, 15000)) { error = "Could not load updated calendar units"; return rollback(); }
    if (!localPath) {
        if (!apply(registryPath)) return rollback();
    } else if (localPublished && !apply(registryPath)) {
        activationError = error;
        error.clear();
    }
    if (daemonStopped && keepDaemon) {
        daemonResumed = true;
        if (!start("pimsync.service")) { error = "Could not resume calendar daemon"; return rollback(); }
    }
    // Commit: local data, profile and required shared runtime have settled.
    if (localPath && !expectedSources.isEmpty()) for (const auto &resource : moved) if (resource.first == collection) {
        struct stat stamp{};
        QJsonObject files;
        QString detail;
        bool unchanged = lstat(QFile::encodeName(resource.second).constData(), &stamp) == 0
            && expectedSources.value("identity") == QString::number(stamp.st_dev) + ':' + QString::number(stamp.st_ino);
        for (const auto &name : QDir(resource.second).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot)) {
            if (name == ".calendar-sync.lock" || name == "displayname") continue;
            QByteArray bytes;
            if (!readFile(resource.second + '/' + name, bytes, detail, false, 64 * 1024 * 1024)) { unchanged = false; break; }
            files[name] = revision(bytes);
        }
        if (!unchanged || files != expectedSources.value("files")) retainedSources = QFileInfo(resource.second).path();
    }
    auto failures = purgeStaging();
    // Only empty known-owned directories; nonempty shared/application directories remain.
    const QStringList emptyDirectories{p.units + "/pimsync.service.d", p.units + '/' + timer + ".d", p.units + "/quickshell-calendar-caldav@.service.d",
        p.units + "/timers.target.wants", p.units + "/default.target.wants", p.state, p.status};
    for (const auto &directory : emptyDirectories) if (QFileInfo(directory).isDir() && !QFileInfo(directory).isSymLink()) QDir().rmdir(directory);
    result = {{"ok", true}, {"id", id}, {"removed", !localPath}};
    if (localPath) {
        QJsonObject activated; QString inspectError;
        const bool registryActive = loadRegistry(p, activated, inspectError) && activated == registry;
        result["converted"] = true; result["disconnected"] = true;
        result["localActive"] = localPublished && registryActive;
        result["localPath"] = localPublished ? localTarget : *localPath;
        if (!result.value("localActive").toBool()) {
            result["activationWarning"] = true;
            result["message"] = "Sync disconnected; local calendar could not be loaded. Local data preserved: " + result.value("localPath").toString();
        } else if (!activationError.isEmpty()) {
            result["cleanupWarning"] = true;
            result["message"] = "Calendar converted; local activation reported an error: " + activationError;
        }
    }
    if (!failures.isEmpty()) {
        result["cleanupWarning"] = true;
        if (localPath) {
            QJsonArray retained;
            for (const auto &path : staging) if (present(path)) retained.append(path);
            result["recoveryPaths"] = retained;
        }
        const auto message = QString(localPath ? "Calendar converted; temporary cleanup incomplete: " : "Calendar removed; temporary cleanup incomplete: ") + failures.join("; ");
        result["message"] = result.contains("message") ? result.value("message").toString() + "; " + message : message;
    }
    return true;
}
bool remove(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease;
    return lease.acquire(p, error) && conversionAllowed(p, request.value("id").toString(), error)
        && retire(p, request, nullptr, false, {}, result, error);
}
bool retireConverted(const Paths &p, const QJsonObject &request, const QString &localPath, QJsonObject &result, QString &error,
                     bool checkOnly, const QJsonObject &expectedSources) {
    // Conversion caller already owns shared lease; never reacquire it or synchronize here.
    return retire(p, request, &localPath, checkOnly, expectedSources, result, error);
}

bool preflightRemoteRetirement(const Paths &p, const QJsonObject &operation, QString &error) {
    RemoteRetirementPlan plan;
    QJsonObject ignored;
    const QString local = p.data + '/' + operation.value("id").toString() + ".json";
    if (present(local)) { error = "Local destination already exists; nothing deleted or overwritten: " + local; return false; }
    return retire(p, {{"id", operation.value("id")}}, &local, true, {}, ignored, error, &plan, &operation);
}

bool finishRemoteRetirement(const Paths &p, QJsonObject &op, QJsonObject &result, QString &error) {
    // Caller owns lifecycle lease/source lock. Reuse inventory/rendering, never legacy rollback/staging.
    const auto id = op.value("id").toString(), stage = op.value("payloadPath").toString();
    const auto target = p.data + '/' + id + ".json", marker = p.state + "/remote-delete-" + id + ".json";
    op["phase"] = op.value("localActive").toBool() ? "cleanup" : "activating";
    if (!saveRemoteDeletion(p, op, error)) return false;
    RemoteRetirementPlan plan;
    QJsonObject ignored;
    if (!retire(p, {{"id", id}}, &target, true, {}, ignored, error, &plan, &op)) return false;
    if (present(stage)) {
        QJsonObject info;
        if (!remoteFileStamp(stage, info, error) || info.value("digest") != op.value("payloadDigest")
            || info.value("identity") != op.value("payloadIdentity")) { if (error.isEmpty()) error = "Staged local calendar changed"; return false; }
        if (!move(stage, target, error)) return false;
    }
    QByteArray localBytes; QJsonObject localInfo, canonical;
    if (!remoteFileStamp(target, localInfo, error, &localBytes, 64LL * 1024 * 1024)) return false;
    const auto local = QJsonDocument::fromJson(localBytes).object();
    if ((!op.value("localActive").toBool() && (localInfo.value("identity") != op.value("payloadIdentity") || localInfo.value("digest") != op.value("payloadDigest")))
        || local.size() != 2 || !QList<int>{1, 2, 3}.contains(local.value("version").toInt()) || !local.value("events").isArray()
        || !makeLocalDocument(id, local.value("events").toArray(), canonical, error) || canonical.value("events") != local.value("events")) {
        if (error.isEmpty()) error = "Published local calendar changed or is invalid; newer file preserved: " + target;
        return false;
    }
    op["published"] = true;
    if (!saveRemoteDeletion(p, op, error)) return false;
    if (!op.value("wiringPublished").toBool() && plan.before.value(p.units + "/pimsync.service").exists) {
        bool active = false;
        if (!idle("pimsync.service", active, error)) return false;
        op["resumeDaemon"] = op.value("resumeDaemon").toBool() || active;
        if (!saveRemoteDeletion(p, op, error)) return false;
        if (active && !command("systemctl", {"--user", "stop", "pimsync.service"}, 30000)) { error = "Could not pause shared calendar daemon for retirement"; return false; }
    }
    bool definitionsChanged = op.value("needsReload").toBool();
    const auto registryPath = p.data + "/profiles.json";
    auto publishCurrent = [&](const QString &path) {
        const auto copy = plan.before.value(path);
        if (!matches(path, copy, error)) return false;
        if (copy.exists && copy.bytes == plan.writes.value(path)) return true;
        if (path.startsWith(p.units + '/')) {
            definitionsChanged = true; op["needsReload"] = true;
            if (!saveRemoteDeletion(p, op, error)) return false;
        }
        if (!ensureDirectory(QFileInfo(path).path(), error) || !writeFile(path, plan.writes.value(path), error, !copy.exists)) return false;
        if (copy.exists && chmod(QFile::encodeName(path).constData(), copy.mode) != 0) { error = "Could not preserve file mode: " + path; return false; }
        return true;
    };
    for (const auto &path : plan.writes.keys()) if (path != registryPath && !publishCurrent(path)) return false;
    op["configRetired"] = true;
    if (!saveRemoteDeletion(p, op, error) || !publishCurrent(registryPath)) return false;
    op["localActive"] = true; op["wiringPublished"] = true; op["phase"] = "cleanup";
    if (!saveRemoteDeletion(p, op, error)) return false;

    QStringList warnings, retained;
    auto warn = [&](const QString &path, const QString &detail) { retained.append(path); warnings.append(detail.isEmpty() ? "Newer resource preserved: " + path : detail); };
    auto eraseKnown = [&](const QString &path, const QJsonValue &expected) {
        if (!present(path)) return;
        QJsonObject actual; QString detail;
        if (!expected.isObject() || !remoteFileStamp(path, actual, detail) || actual != expected.toObject() || !erase(path, detail)) warn(path, detail);
    };
    const auto sources = op.value("sources").toObject();
    const auto collection = p.data + '/' + id;
    if (present(collection)) {
        struct stat stamp{};
        if (lstat(QFile::encodeName(collection).constData(), &stamp) != 0 || !S_ISDIR(stamp.st_mode)
            || sources.value("identity") != QString::number(stamp.st_dev) + ':' + QString::number(stamp.st_ino)) warn(collection, {});
        else {
            const auto expected = sources.value("files").toObject();
            for (const auto &name : QDir(collection).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot)) {
                if (name == ".calendar-sync.lock") continue;
                eraseKnown(collection + '/' + name, expected.value(name));
            }
            auto remaining = QDir(collection).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot);
            remaining.removeOne(".calendar-sync.lock");
            if (remaining.isEmpty()) {
                QString detail;
                if (!ownedResource(collection + "/.calendar-sync.lock", false, detail) || !erase(collection + "/.calendar-sync.lock", detail)
                    || !QDir().rmdir(collection)) warn(collection, detail);
            }
        }
    }
    eraseKnown(collection + ".sync.json", sources.value("cache"));
    eraseKnown(QFileInfo(p.state).path() + "/conflicts-" + id + ".json", sources.value("conflicts"));
    const auto databases = sources.value("databases").toObject();
    for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"})
        eraseKnown(p.status + "/qs_caldav_" + id + ".status" + suffix, databases.value(suffix));
    if (!plan.keepWatcher && plan.watcherActive && !command("systemctl", {"--user", "stop", "quickshell-calendar-import.path"}, 30000))
        warn(p.units + "/quickshell-calendar-import.path", "Could not stop unused calendar watcher");
    QStringList roots{p.units};
    if (!qEnvironmentVariable("XDG_RUNTIME_DIR").isEmpty()) roots.append(qEnvironmentVariable("XDG_RUNTIME_DIR") + "/systemd/user");
    for (const auto &path : plan.deletes) {
        if (path.startsWith(p.units + '/')) {
            const auto name = QFileInfo(path).fileName();
            if (!path.contains(".service.d/")) for (const auto &root : roots) {
                const auto link = root + (name.endsWith(".timer") ? "/timers.target.wants/" : "/default.target.wants/") + name;
                if (!present(link)) continue;
                struct stat stamp{}; std::error_code code; QString detail;
                const auto raw = std::filesystem::read_symlink(QFile::encodeName(link).constData(), code);
                if (lstat(QFile::encodeName(link).constData(), &stamp) != 0 || !S_ISLNK(stamp.st_mode) || stamp.st_uid != geteuid() || code
                    || QDir::cleanPath(QDir(QFileInfo(link).path()).absoluteFilePath(QString::fromStdString(raw.native()))) != path) { warn(link, {}); continue; }
                op["needsReload"] = true; definitionsChanged = true;
                if (!saveRemoteDeletion(p, op, error)) return false;
                if (!erase(link, detail)) warn(link, detail);
            }
        }
        if (!present(path)) continue;
        QString detail;
        if ((plan.before.contains(path) && !matches(path, plan.before.value(path), detail)) || !ownedResource(path, false, detail)) { warn(path, detail); continue; }
        if (path.startsWith(p.units + '/')) {
            op["needsReload"] = true; definitionsChanged = true;
            if (!saveRemoteDeletion(p, op, error)) return false;
        }
        if (!erase(path, detail)) warn(path, detail);
    }
    if (definitionsChanged) {
        if (!command("systemctl", {"--user", "daemon-reload"}, 15000)) { error = "Could not reload retired calendar units"; return false; }
        op["needsReload"] = false;
        if (!saveRemoteDeletion(p, op, error)) return false;
    }
    if (op.value("resumeDaemon").toBool() && plan.keepDaemon) {
        if (!command("systemctl", {"--user", "start", "pimsync.service"}, 30000)) { error = "Could not resume unrelated calendar daemon"; return false; }
    }
    op["resumeDaemon"] = false;
    if (!saveRemoteDeletion(p, op, error)) return false;
    result = {{"ok", true}, {"id", id}, {"converted", true}, {"disconnected", true}, {"localActive", true}, {"localPath", target}, {"phase", "cleanup"}};
    if (!warnings.isEmpty()) {
        QJsonArray paths{marker}; for (const auto &path : retained) paths.append(path);
        result["cleanupWarning"] = true; result["recoveryPaths"] = paths;
        result["message"] = QString(op.value("preserveLocalOnly").toBool() ? "Local calendar active; no server changes attempted. Cleanup pending: "
            : "Remote calendar deleted; local calendar active. Cleanup pending: ") + warnings.join("; ");
        return true;
    }
    if (!erase(marker, error)) {
        result["cleanupWarning"] = true; result["recoveryPaths"] = QJsonArray{marker};
        result["message"] = "Local calendar active; operation record cleanup pending: " + marker;
        return true;
    }
    for (const auto &directory : QStringList{p.units + "/pimsync.service.d", p.units + "/timers.target.wants", p.units + "/default.target.wants", p.state, p.status})
        if (QFileInfo(directory).isDir() && !QFileInfo(directory).isSymLink()) QDir().rmdir(directory);
    result["completed"] = true; result["phase"] = "complete";
    return true;
}
} // namespace CalDavBackend
