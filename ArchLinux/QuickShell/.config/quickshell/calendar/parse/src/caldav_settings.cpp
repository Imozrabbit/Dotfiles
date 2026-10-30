#include "caldav.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QProcess>
#include <QSet>
#include <algorithm>
#include <cmath>
#include <sys/stat.h>
#include <unistd.h>

namespace CalDavBackend {
using namespace SubscriptionBackend;
namespace {
const QByteArray unitMarker("# quickshell-calendar CalDAV runtime v1\n");
QString unitQuoted(QString value) { return quoted(value.replace("%", "%%")); }
QJsonValue profileFor(const QJsonObject &registry, const QString &id) {
    for (const auto &value : registry.value("profiles").toArray()) if (value.toObject().value("id") == id) return value;
    return QJsonValue(QJsonValue::Null);
}
bool exists(const QString &path) { return QFileInfo::exists(path) || QFileInfo(path).isSymLink(); }
bool removeFile(const QString &path, QString &error) {
    QByteArray ignored;
    if (!exists(path)) return true;
    if (!readFile(path, ignored, error, false, 64 * 1024 * 1024) || !QFile::remove(path)) {
        error = "Could not clean failed Add file: " + path; return false;
    }
    return true;
}
bool verifyDaemon(const Paths &p, QString &error) {
    const QString bus = "org.freedesktop.systemd1";
    if (!command("busctl", {"--user", "call", bus, "/org/freedesktop/systemd1", bus + ".Manager", "LoadUnit", "s", "pimsync.service"}, 10000)) {
        error = "Could not load effective calendar daemon definition"; return false;
    }
    QMap<QString, QJsonObject> properties;
    for (const auto &name : QStringList{"ExecStart", "Environment", "EnvironmentFiles", "UnsetEnvironment"}) {
        QProcess process;
        process.setStandardErrorFile(QProcess::nullDevice());
        process.start("busctl", {"--user", "--json=short", "get-property", bus, "/org/freedesktop/systemd1/unit/pimsync_2eservice", bus + ".Service", name});
        if (!process.waitForStarted(5000) || !process.waitForFinished(10000) || process.exitCode() != 0) {
            process.kill(); process.waitForFinished(5000); error = "Could not inspect effective calendar daemon routing"; return false;
        }
        const auto bytes = process.readAllStandardOutput();
        if (bytes.size() > 256 * 1024) { error = "Calendar daemon definition is too large"; return false; }
        properties[name] = QJsonDocument::fromJson(bytes).object();
    }
    const auto starts = properties["ExecStart"].value("data").toArray();
    const auto start = starts.size() == 1 ? starts.first().toArray() : QJsonArray{};
    bool valid = properties["ExecStart"].value("type") == "a(sasbttttuii)" && start.size() >= 3
        && start[0] == p.helper && start[1].toArray() == QJsonArray{p.helper, "caldav", "daemon"} && start[2].isBool() && !start[2].toBool()
        && properties["Environment"].value("type") == "as" && properties["Environment"].value("data").isArray()
        && properties["EnvironmentFiles"].value("type") == "a(sb)" && properties["EnvironmentFiles"].value("data").isArray() && properties["EnvironmentFiles"].value("data").toArray().isEmpty()
        && properties["UnsetEnvironment"].value("type") == "as" && properties["UnsetEnvironment"].value("data").isArray();
    QMap<QString, QString> expected{{"HOME", qEnvironmentVariable("HOME")}, {"XDG_CONFIG_HOME", p.units.left(p.units.size() - 13)},
        {"XDG_DATA_HOME", QFileInfo(p.data).path()}, {"XDG_STATE_HOME", QFileInfo(QFileInfo(p.state).path()).path()}};
    if (!qEnvironmentVariable("XDG_RUNTIME_DIR").isEmpty()) expected["XDG_RUNTIME_DIR"] = qEnvironmentVariable("XDG_RUNTIME_DIR");
    QSet<QString> seen;
    for (const auto &entry : properties["Environment"].value("data").toArray()) {
        const auto key = entry.toString().section('=', 0, 0);
        if (expected.contains(key)) { valid = valid && entry == key + '=' + expected[key]; seen.insert(key); }
    }
    for (const auto &key : expected.keys()) valid = valid && seen.contains(key);
    for (const auto &entry : properties["UnsetEnvironment"].value("data").toArray()) valid = valid && !expected.contains(entry.toString().section('=', 0, 0));
    if (!valid) error = "Effective calendar daemon routing differs; custom policy was preserved";
    return valid;
}
} // namespace

bool verifyManagedDaemon(const Paths &p, QString &error) { return verifyDaemon(p, error); }

QMap<QString, QByteArray> unitDefinitions(const Paths &p, const Config &config) {
    if (config.records.isEmpty()) return {};
    SubscriptionBackend::Config shared;
    shared.records.append(SubscriptionBackend::Record{"caldav", "", 300});
    const auto base = SubscriptionBackend::unitDefinitions(SubscriptionBackend::paths(), shared);
    QMap<QString, QByteArray> files;
    for (const auto &name : QStringList{"pimsync.service", "pimsync.service.d/calendar-group-recovery.conf"}) files[name] = base.value(name);
    QString env;
    const QStringList values{"HOME=" + qEnvironmentVariable("HOME"), "XDG_CONFIG_HOME=" + p.units.left(p.units.size() - 13),
        "XDG_DATA_HOME=" + QFileInfo(p.data).path(), "XDG_STATE_HOME=" + QFileInfo(QFileInfo(p.state).path()).path()};
    for (const auto &value : values) env += "Environment=" + unitQuoted(value) + '\n';
    if (!qEnvironmentVariable("XDG_RUNTIME_DIR").isEmpty()) env += "Environment=" + unitQuoted("XDG_RUNTIME_DIR=" + qEnvironmentVariable("XDG_RUNTIME_DIR")) + '\n';
    files["pimsync.service.d/calendar-caldav.conf"] = unitMarker + ("[Service]\n" + env + "ExecStart=\nExecStart=" + unitQuoted(p.helper) + " caldav daemon\n").toUtf8();
    files["quickshell-calendar-caldav@.service"] = unitMarker + ("[Unit]\nDescription=Synchronize calendar %i\n\n[Service]\nType=oneshot\nUMask=0077\n"
        + env + "ExecCondition=/bin/sh " + unitQuoted(p.broker) + " check-recovery\nExecStart=" + unitQuoted(p.helper) + " caldav sync %i\nTimeoutStartSec=240\n").toUtf8();
    for (const auto &r : config.records) files["quickshell-calendar-caldav-" + r.id + ".timer"] = unitMarker
        + ("[Unit]\nDescription=Schedule calendar " + r.id + "\n\n[Timer]\nOnBootSec=15s\nOnUnitInactiveSec=" + QString::number(r.interval)
           + "s\nAccuracySec=1s\nUnit=quickshell-calendar-caldav@" + r.id + ".service\n\n[Install]\nWantedBy=timers.target\n").toUtf8();
    return files;
}

bool settings(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease;
    Config config;
    QJsonObject registry;
    if (!lease.acquire(p, error) || !CalDavBackend::loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    if (!command("/bin/sh", {p.broker, "check-recovery"}, 10000)) { error = "Resolve the pending calendar operation before changing settings"; return false; }
    auto profile = request.value("profile").toObject();
    const auto id = profile.value("id").toString();
    if (!conversionAllowed(p, id, error)) return false;
    const auto previousProfile = profileFor(registry, id);
    const auto found = std::find_if(config.records.begin(), config.records.end(), [&](const auto &r) { return r.id == id; });
    const bool existing = found != config.records.end();
    if (!validProfile(profile) || profile.value("type") != "synced" || existing != !previousProfile.isNull()
        || (existing && previousProfile.toObject().value("type") != "synced")) {
        error = "Choose an unused calendar ID or reopen the existing synced calendar"; return false;
    }
    if (request.value("expectedRevision").toString() != revision(config.original) || !request.contains("expectedProfile")
        || request.value("expectedProfile") != previousProfile) { error = "Calendar settings changed; reopen the form before saving"; return false; }
    const double interval = request.value("intervalSeconds").toDouble(300);
    if ((request.contains("intervalSeconds") && !request.value("intervalSeconds").isDouble()) || !std::isfinite(interval)
        || std::floor(interval) != interval || interval < 300 || interval > 2147483647) {
        error = "Refresh interval must be at least 5 minutes, in whole seconds"; return false;
    }
    Record desired = recordFromJson(request);
    desired.id = id; desired.interval = static_cast<int>(interval);
    if (!validIdentity(desired)) { error = "Choose one discovered remote calendar and a valid local ID"; return false; }
    if (existing) {
        auto before = recordJson(*found), after = recordJson(desired);
        before.remove("intervalSeconds"); after.remove("intervalSeconds");
        if (before != after) { error = "Remote calendar identity cannot change; only name, color and interval are editable"; return false; }
    } else {
        if (!validateConnection(desired, error)) return false;
        for (const auto &r : config.records) if (remoteIdentity(r) == remoteIdentity(desired)) {
            error = "This remote calendar has already been added"; return false;
        }
        const auto unmanaged = QString::fromUtf8(config.prefix + config.suffix);
        if (QRegularExpression("(?m)^\\s*(?:pair|collection|collection_id|id_a|id_b|alias)\\s+\"?" + QRegularExpression::escape(id)
                + "\"?(?=\\s|[{}]|$)").match(unmanaged).hasMatch()
            || unmanaged.contains(quoted(desired.url)) || unmanaged.contains("url " + desired.url)
            || (QRegularExpression("(?m)^\\s*collections\\s+").match(unmanaged).hasMatch() && unmanaged.contains(p.data))) {
            error = "Existing manual configuration may manage this calendar; remove that overlap before Add"; return false;
        }
        QJsonArray calendars;
        if (!discover(desired, calendars, error)) return false;
        bool selected = false;
        for (const auto &value : calendars) if (value.toObject().value("id") == desired.remoteId && value.toObject().value("href") == desired.remoteHref) selected = true;
        if (!selected) { error = "Selected calendar is no longer available; connect again"; return false; }
    }
    const auto directory = p.data + '/' + id, cache = directory + ".sync.json";
    if (!existing) {
        QStringList targets{directory, cache, directory + ".json"};
        for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) targets << p.status + '/' + desired.pair() + ".status" + suffix;
        for (const auto &path : targets) if (exists(path)) { error = "Calendar ID collides with retained local files or pair state"; return false; }
    }
    Config next = config;
    next.records.erase(std::remove_if(next.records.begin(), next.records.end(), [&](const auto &r) { return r.id == id; }), next.records.end());
    next.records.append(desired);
    if (!QRegularExpression("(?m)^\\s*status_path\\s+").match(QString::fromUtf8(next.prefix + next.suffix)).hasMatch()) {
        if (!next.prefix.isEmpty() && !next.prefix.endsWith('\n')) next.prefix += '\n';
        next.prefix += ("status_path " + quoted(p.status) + '\n').toUtf8();
    } else if (!QRegularExpression("(?m)^\\s*status_path\\s+\"?" + QRegularExpression::escape(p.status) + "/?\"?\\s*$")
                .match(QString::fromUtf8(next.prefix + next.suffix)).hasMatch()) {
        error = "CalDAV Add requires the standard pimsync status directory; existing configuration was preserved"; return false;
    }
    auto definitions = CalDavBackend::unitDefinitions(p, next);
    const auto oldDefinitions = CalDavBackend::unitDefinitions(p, config);
    QMap<QString, QByteArray> before, changes;
    QMap<QString, mode_t> modes;
    QSet<QString> missing, written;
    QStringList createdDirectories;
    const auto registryPath = p.data + "/profiles.json", statusPath = p.state + "/status.json";
    changes[p.config] = renderConfig(p, next, next.records);
    for (auto it = definitions.begin(); it != definitions.end(); ++it) changes[p.units + '/' + it.key()] = it.value();
    for (const auto &path : changes.keys() + QStringList{registryPath, statusPath, cache}) {
        if (!readFile(path, before[path], error, true, 64 * 1024 * 1024)) return false;
        if (!exists(path)) missing.insert(path);
        struct stat stamp{};
        if (lstat(QFile::encodeName(path).constData(), &stamp) == 0) modes[path] = stamp.st_mode & 0777;
    }
    if (before[p.config] != config.original) { error = "Calendar configuration changed; reopen settings"; return false; }
    for (auto it = definitions.begin(); it != definitions.end(); ++it) {
        const auto path = p.units + '/' + it.key();
        const auto old = before[path];
        if (old.isEmpty()) continue;
        if (it.key() == "pimsync.service") {
            if (!old.contains("ExecStart=/usr/bin/pimsync daemon\n")) { error = "Existing daemon routing is unsupported; no units were overwritten"; return false; }
            changes[path] = old;
        } else if (it.key() == "pimsync.service.d/calendar-group-recovery.conf" && old == it.value().mid(it.value().indexOf("[Service]"))) {
            changes[path] = old;
        } else if (old != it.value() && old != oldDefinitions.value(it.key())) {
            error = "Calendar unit has custom settings; it was not overwritten"; return false;
        }
    }
    const auto timer = "quickshell-calendar-caldav-" + id + ".timer";
    const bool enabled = existing && command("systemctl", {"--user", "is-enabled", "--quiet", timer}, 10000);
    bool active = false, paused = false, activation = false, reload = false, collectionCreated = false;
    struct stat collectionIdentity{};
    auto sameCollection = [&] {
        struct stat current{};
        return lstat(QFile::encodeName(directory).constData(), &current) == 0 && S_ISDIR(current.st_mode)
            && current.st_dev == collectionIdentity.st_dev && current.st_ino == collectionIdentity.st_ino;
    };
    auto prepare = [&](const QString &path) {
        QString parent = path;
        while (!exists(parent) && parent != "/") {
            if (!createdDirectories.contains(parent)) createdDirectories.append(parent);
            parent = QFileInfo(parent).path();
        }
        return ensureDirectory(path, error);
    };
    auto publish = [&](const QString &path, const QByteArray &bytes) {
        QByteArray current;
        if (!readFile(path, current, error, true, 64 * 1024 * 1024)
            || exists(path) == missing.contains(path) || current != before.value(path)) {
            error = "Calendar file changed before publication; newer contents were preserved"; return false;
        }
        bool committed = false;
        const bool ok = writeFile(path, bytes, error, missing.contains(path), &committed);
        if (committed) written.insert(path);
        return ok;
    };
    // ponytail: ordinary failures roll back in memory; a killed Add needs manual cleanup, not a new crash journal.
    auto fail = [&] {
        const auto cause = error;
        QString cleanup;
        if (activation && !command("systemctl", {"--user", "stop", timer}, 30000)) { error = cause + "; could not stop failed calendar timer"; return false; }
        if (activation && !enabled && !command("systemctl", {"--user", "disable", timer}, 15000)) { error = cause + "; could not disable failed calendar timer"; return false; }
        for (const auto &path : written) {
            QByteArray current;
            if (!readFile(path, current, cleanup, true, 64 * 1024 * 1024) || (current != before[path] && current != changes.value(path))) {
                error = cause + "; newer file retained; inspect failed Add before retrying"; return false;
            }
        }
        for (const auto &path : written) {
            if (!(missing.contains(path) ? removeFile(path, cleanup) : writeFile(path, before[path], cleanup))) { error = cause + "; " + cleanup; return false; }
            if (!missing.contains(path) && chmod(QFile::encodeName(path).constData(), modes.value(path, 0600)) != 0) { error = cause + "; could not restore file permissions"; return false; }
        }
        if (!existing) {
            for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) if (!removeFile(p.status + '/' + desired.pair() + ".status" + suffix, cleanup)) { error = cause + "; " + cleanup; return false; }
            if (collectionCreated && (!sameCollection() || !QDir(directory).removeRecursively())) { error = cause + "; changed or failed collection retained for cleanup"; return false; }
        }
        if (reload && !command("systemctl", {"--user", "daemon-reload"}, 15000)) { error = cause + "; could not reload previous units"; return false; }
        if (activation && enabled && !command("systemctl", {"--user", "start", timer}, 15000)) { error = cause + "; could not restore timer"; return false; }
        if (paused && !resumeDaemon(active, cleanup)) { error = cause + "; " + cleanup; return false; }
        std::sort(createdDirectories.begin(), createdDirectories.end(), [](const auto &a, const auto &b) { return a.size() > b.size(); });
        for (const auto &path : createdDirectories) QDir().rmdir(path); // Never remove nonempty shared directories.
        error = cause; return false;
    };
    if (!pauseDaemon(active, error)) return false;
    paused = true;
    if (!prepare(p.status) || !prepare(p.state)) return fail();
    if (!existing) {
        if (exists(cache)) { error = "Calendar cache appeared during Add; it was not overwritten"; return fail(); }
        if (::mkdir(QFile::encodeName(directory).constData(), 0700) != 0) {
            error = "Calendar collection appeared during Add or could not be created; existing data was not adopted"; return fail();
        }
        if (lstat(QFile::encodeName(directory).constData(), &collectionIdentity) != 0 || !S_ISDIR(collectionIdentity.st_mode)) {
            error = "New calendar collection changed; inspect retained path before retrying"; return fail();
        }
        collectionCreated = true;
    }
    for (auto it = changes.begin(); it != changes.end(); ++it) {
        if (!missing.contains(it.key()) && it.value() == before[it.key()]) continue;
        if (!prepare(QFileInfo(it.key()).path())) return fail();
        if (!publish(it.key(), it.value())) return fail();
        if (it.key().startsWith(p.units + '/')) reload = true;
    }
    if (reload && !command("systemctl", {"--user", "daemon-reload"}, 15000)) { error = "Could not load calendar units"; return fail(); }
    if (!verifyDaemon(p, error)) return fail();
    if (!existing) {
        if (!sameCollection()) { error = "Calendar collection changed during Add"; return fail(); }
        written.insert(statusPath);
        const bool synced = syncRecord(p, desired, error, true, &changes[cache]);
        if (!changes[cache].isEmpty()) written.insert(cache);
        QString snapshotError;
        if (!readFile(statusPath, changes[statusPath], snapshotError, true, 64 * 1024 * 1024)) { error = snapshotError; return fail(); }
        if (!synced) return fail();
    }
    activation = true;
    if (!command("systemctl", enabled ? QStringList{"--user", "restart", timer} : QStringList{"--user", "enable", "--now", timer}, 30000)) {
        error = "Could not enable calendar synchronization timer"; return fail();
    }
    QJsonObject latest;
    QByteArray actualConfig;
    if (!loadRegistry(p, latest, error) || profileFor(latest, id) != previousProfile || !readFile(p.config, actualConfig, error)
        || actualConfig != changes[p.config] || !readFile(registryPath, before[registryPath], error)) {
        error = "Calendar settings changed during Add; newer data was preserved"; return fail();
    }
    if (QJsonDocument::fromJson(before[registryPath]).object() != latest) { error = "Profile registry changed before publication"; return fail(); }
    QJsonArray profiles;
    for (const auto &value : latest.value("profiles").toArray()) if (value.toObject().value("id") != id) profiles.append(value);
    profile["name"] = profile.value("name").toString().trimmed();
    profiles.append(profile); latest["profiles"] = profiles;
    changes[registryPath] = QJsonDocument(latest).toJson();
    if (!publish(registryPath, changes[registryPath])) return fail();
    if (!resumeDaemon(active, error)) return fail();
    paused = false;
    result = {{"ok", true}, {"id", id}, {"profile", profile}};
    return true;
}
} // namespace CalDavBackend
