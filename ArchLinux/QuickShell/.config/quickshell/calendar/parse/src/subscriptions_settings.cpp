#include "subscriptions.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMap>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <sys/stat.h>
#include <unistd.h>

namespace SubscriptionBackend {
namespace {
const QByteArray unitMarker("# quickshell-calendar URL runtime v1\n");
const QStringList sharedUnits{"quickshell-calendar-import.path", "quickshell-calendar-import.service", "pimsync.service"};

QString quoted(QString value) {
    return '"' + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("%", "%%") + '"';
}
QString environment(const Paths &p) {
    QString result;
    const QStringList values{"HOME=" + qEnvironmentVariable("HOME"),
        "XDG_CONFIG_HOME=" + p.units.left(p.units.size() - QString("/systemd/user").size()),
        "XDG_DATA_HOME=" + p.data.left(p.data.lastIndexOf('/')),
        "XDG_STATE_HOME=" + p.state.left(p.state.size() - QString("/quickshell-calendar/subscriptions").size())};
    for (const auto &value : values) result += "Environment=" + quoted(value) + '\n';
    return result;
}
} // namespace

QMap<QString, QByteArray> unitDefinitions(const Paths &p, const Config &config) {
    if (config.records.isEmpty()) return {};
    const auto env = environment(p);
    QMap<QString, QByteArray> files;
    files["pimsync.service"] = unitMarker + ("[Unit]\nDescription=Synchronise calendars\nDocumentation=man:pimsync\n\n[Service]\n"
        + env + "UMask=0077\nExecStart=/usr/bin/pimsync daemon\nRestart=on-failure\nRestartSec=30s\nSlice=background.slice\n\n[Install]\nWantedBy=default.target\n").toUtf8();
    files["pimsync.service.d/calendar-group-recovery.conf"] = unitMarker + ("[Service]\nEnvironment="
        + quoted("XDG_STATE_HOME=" + p.state.left(p.state.size() - QString("/quickshell-calendar/subscriptions").size()))
        + "\nExecCondition=/bin/sh " + quoted(p.broker) + " check-recovery\n").toUtf8();
    files["quickshell-calendar-import.service"] = unitMarker + ("[Unit]\nDescription=Generate calendar JSON caches\nAfter=pimsync.service\n\n[Service]\nType=oneshot\nUMask=0077\n"
        + env + "ExecCondition=/bin/sh " + quoted(p.broker) + " check-recovery\nExecStartPre=/usr/bin/sleep 1\nExecStart="
        + quoted(p.helper) + " subscriptions cache\n").toUtf8();
    QString watcher = "[Unit]\nDescription=Watch calendar collections\n\n[Path]\n";
    for (const auto &record : config.records) {
        const auto directory = QString(p.data + '/' + record.id).replace("%", "%%");
        watcher += "PathChanged=" + directory + "\nPathModified=" + directory + '\n';
    }
    watcher += "Unit=quickshell-calendar-import.service\n\n[Install]\nWantedBy=default.target\n";
    files["quickshell-calendar-import.path"] = unitMarker + watcher.toUtf8();
    return files;
}
namespace {
bool profileValid(const QJsonObject &profile) {
    const QStringList keys{"id", "name", "color", "type", "visible"};
    if (profile.size() != keys.size() || !validId(profile.value("id").toString())
        || !profile.value("name").isString() || profile.value("name").toString().trimmed().isEmpty()
        || !QRegularExpression("^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$").match(profile.value("color").toString()).hasMatch()
        || !QStringList{"local", "imported", "synced", "subscription"}.contains(profile.value("type").toString())
        || !profile.value("visible").isBool()) return false;
    for (const auto &key : keys) if (!profile.contains(key)) return false;
    return true;
}
QJsonValue profileFor(const QJsonObject &registry, const QString &id) {
    for (const auto &value : registry.value("profiles").toArray())
        if (value.toObject().value("id") == id) return value;
    return QJsonValue(QJsonValue::Null);
}
bool active(const QString &unit, bool &value, QString &error) {
    QProcess process;
    process.start("systemctl", {"--user", "show", "--property=ActiveState", "--value", unit});
    if (!process.waitForStarted(5000) || !process.waitForFinished(10000) || process.exitCode() != 0) {
        process.kill(); process.waitForFinished(5000);
        error = "Could not read calendar service state"; return false;
    }
    const auto state = process.readAllStandardOutput().trimmed();
    if (state != "active" && state != "inactive" && state != "failed") {
        error = "Calendar service is busy; try again when it finishes"; return false;
    }
    value = state == "active";
    return true;
}
bool removeFile(const QString &path, QString &error) {
    struct stat s{};
    if (lstat(QFile::encodeName(path).constData(), &s) != 0 && errno == ENOENT) return true;
    if (!S_ISREG(s.st_mode) || s.st_uid != geteuid() || s.st_nlink != 1 || !QFile::remove(path)) {
        error = "Could not remove calendar file: " + path; return false;
    }
    return true;
}
bool status(const Paths &p, const QString &id, bool ok, const QString &message, QString &error) {
    QJsonObject document;
    if (!ensureDirectory(p.state, error) || !jsonFile(p.state + "/status.json", document, error)) return false;
    if (!document.isEmpty() && (document.value("version") != 1 || !document.value("records").isObject())) {
        error = "Subscription status is malformed"; return false;
    }
    auto records = document.value("records").toObject();
    auto value = records.value(id).toObject();
    const auto now = QDateTime::currentMSecsSinceEpoch();
    value["lastAttemptMs"] = now; value["busy"] = false; value["error"] = message;
    if (ok) value["lastSuccessMs"] = now;
    records[id] = value;
    return writeFile(p.state + "/status.json", QJsonDocument(QJsonObject{{"version", 1}, {"records", records}}).toJson(), error);
}
bool convert(const Paths &p, const Record &record, QString &error) {
    if (!command(p.converter, {p.data + '/' + record.id, p.data + '/' + record.id + ".json", record.id}, 65000)) {
        error = "Could not convert downloaded calendar to JSON"; return false;
    }
    return true;
}
} // namespace

bool validProfile(const QJsonObject &profile) { return profileValid(profile); }

bool loadRegistry(const Paths &p, QJsonObject &registry, QString &error) {
    if (!jsonFile(p.data + "/profiles.json", registry, error, false)) return false;
    if (registry.size() != 2 || registry.value("version") != 1 || !registry.value("profiles").isArray()) {
        error = "Profile registry schema is unsupported"; return false;
    }
    QSet<QString> ids;
    for (const auto &value : registry.value("profiles").toArray()) {
        const auto profile = value.toObject();
        const auto id = profile.value("id").toString();
        if (!value.isObject() || !profileValid(profile) || ids.contains(id)) {
            error = "Profile registry is invalid; existing data was preserved"; return false;
        }
        ids.insert(id);
    }
    return true;
}

QStringList unitFiles(const Config &config) { return unitDefinitions(paths(), config).keys(); }
QStringList unitNames(const Config &config) { return config.records.isEmpty() ? QStringList{} : sharedUnits; }

bool installUnits(const Paths &p, const Config &config, QString &error, bool checkOnly) {
    const auto files = unitDefinitions(p, config);
    for (auto it = files.begin(); it != files.end(); ++it) {
        const auto path = p.units + '/' + it.key();
        QByteArray previous;
        if (!readFile(path, previous, error, true)) return false;
        // Preserve existing pimsync host policy; only its config routing must match.
        if (it.key() == "pimsync.service" && !previous.isEmpty()) {
            if (!previous.contains("ExecStart=/usr/bin/pimsync daemon\n") || !previous.contains(environment(p).section('\n', 1, 1).toUtf8())) {
                error = "Existing pimsync service uses different routing; it was not changed"; return false;
            }
            continue;
        }
        if (previous == it.value() || previous == it.value().mid(unitMarker.size())) continue;
        if (checkOnly || !previous.isEmpty()) { error = "Calendar service definition differs from URL settings"; return false; }
        if (!ensureDirectory(QFileInfo(path).path(), error) || !writeFile(path, it.value(), error)) return false;
    }
    return true;
}

bool cache(const Paths &p, const Config &config, QString &error) {
    Lease lease;
    QJsonObject registry;
    if (!lease.acquire(p, error, true) || !loadRegistry(p, registry, error)
        || !command("/bin/sh", {p.broker, "check-recovery"}, 10000)) return false;
    bool allOk = true;
    for (const auto &record : config.records) {
        if (profileFor(registry, record.id).toObject().value("type") != "subscription") continue;
        QString detail, statusError;
        const auto cachePath = p.data + '/' + record.id + ".json";
        QByteArray before, after;
        const bool ok = readFile(cachePath, before, detail, true, 64 * 1024 * 1024) && convert(p, record, detail)
            && readFile(cachePath, after, detail, false, 64 * 1024 * 1024);
        // ponytail: unchanged cache cannot prove recovery; use daemon sync-result signals if needed.
        if ((!ok || before != after) && !status(p, record.id, ok, detail, statusError)) detail = statusError;
        if (!detail.isEmpty()) { error = detail; allOk = false; }
    }
    return allOk;
}

bool settings(const Paths &p, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease;
    Config config;
    QJsonObject registry;
    if (!lease.acquire(p, error) || !loadConfig(p, config, error) || !loadRegistry(p, registry, error)) return false;
    if (QFileInfo::exists(p.state + "/change.json") || QFileInfo::exists(p.units + "/pimsync.service.d/calendar-subscriptions.conf")) {
        error = "Old subscription setup remains; clear it before using the shared URL backend"; return false;
    }
    if (!command("/bin/sh", {p.broker, "check-recovery"}, 10000)) {
        error = "Resolve the pending calendar event operation before starting sync"; return false;
    }
    const bool refreshing = action == "refresh";
    auto profile = request.value("profile").toObject();
    const auto id = refreshing ? request.value("id").toString() : profile.value("id").toString();
    const auto found = std::find_if(config.records.begin(), config.records.end(), [&](const auto &r) { return r.id == id; });
    const bool existing = found != config.records.end();
    const auto previousProfile = profileFor(registry, id);
    if (refreshing) profile = previousProfile.toObject();
    if (!profileValid(profile) || profile.value("type") != "subscription" || (existing != !previousProfile.isNull())
        || (existing && previousProfile.toObject().value("type") != "subscription") || (refreshing && !existing)) {
        error = "Choose an unused calendar ID or reopen the existing subscription"; return false;
    }
    if (!refreshing && (request.value("expectedRevision").toString() != revision(config.original)
        || !request.contains("expectedProfile") || request.value("expectedProfile") != previousProfile)) {
        error = "Calendar settings changed; reopen the form before saving"; return false;
    }
    const double interval = refreshing ? found->interval : request.value("intervalSeconds").toDouble(600);
    if ((!refreshing && request.contains("intervalSeconds") && !request.value("intervalSeconds").isDouble())
        || !std::isfinite(interval) || std::floor(interval) != interval || interval < 300 || interval > 2147483647) {
        error = "Refresh interval must be at least 5 minutes, in whole seconds"; return false;
    }
    Record desired{id, refreshing ? found->url : request.value("url").toString(), static_cast<int>(interval)};
    if (!validateRecord(desired, error)) return false;
    const bool sync = refreshing || !existing || found->url != desired.url;
    const auto directory = p.data + '/' + id;
    const auto cachePath = directory + ".json";
    if (!existing && (QFileInfo::exists(directory) || QFileInfo(directory).isSymLink()
        || QFileInfo::exists(cachePath) || QFileInfo(cachePath).isSymLink() || QFileInfo::exists(directory + ".sync.json")
        || QFileInfo::exists(p.status + '/' + desired.pair() + ".status") || QFileInfo(p.status + '/' + desired.pair() + ".status").isSymLink())) {
        error = "Calendar ID collides with retained local data; choose another ID"; return false;
    }
    const auto unmanaged = QString::fromUtf8(config.prefix + config.suffix);
    if (!existing && QRegularExpression("(?m)^\\s*(?:pair|collection|collection_id)\\s+\"?"
        + QRegularExpression::escape(id) + "\"?(?=\\s|[{}]|$)").match(unmanaged).hasMatch()) {
        error = "Calendar ID is already used by another configured collection"; return false;
    }
    Config next = config;
    next.records.erase(std::remove_if(next.records.begin(), next.records.end(), [&](const auto &r) { return r.id == id; }), next.records.end());
    next.records.append(desired);
    if (next.prefix.trimmed().isEmpty()) next.prefix = ("status_path \"" + p.status + "\"\n").toUtf8();
    if (!QRegularExpression("(?m)^\\s*status_path\\s+\"?" + QRegularExpression::escape(p.status) + "/?\"?\\s*$").match(QString::fromUtf8(next.prefix)).hasMatch()) {
        error = "URL calendars require the configured standard pimsync status directory"; return false;
    }
    const auto previousUnits = unitDefinitions(p, config);
    auto units = unitDefinitions(p, next);
    QMap<QString, QByteArray> before, changes;
    QSet<QString> missing, written;
    const auto registryPath = p.data + "/profiles.json";
    const auto statusPath = p.state + "/status.json";
    changes[p.config] = renderConfig(p, next, next.records);
    for (auto it = units.begin(); it != units.end(); ++it) changes[p.units + '/' + it.key()] = it.value();
    for (const auto &path : changes.keys() + QStringList{registryPath, statusPath, cachePath}) {
        QByteArray bytes;
        if (!readFile(path, bytes, error, true, path == cachePath ? 64 * 1024 * 1024 : 1024 * 1024)) return false;
        before[path] = bytes;
        if (!QFileInfo::exists(path)) missing.insert(path);
    }
    if (before[p.config] != config.original) { error = "Calendar configuration changed; reopen the form"; return false; }
    for (auto it = units.begin(); it != units.end(); ++it) {
        const auto path = p.units + '/' + it.key();
        const auto old = before[path];
        if (it.key() == "pimsync.service" && !old.isEmpty()) {
            if (!old.contains("ExecStart=/usr/bin/pimsync daemon\n") || !old.contains(environment(p).section('\n', 1, 1).toUtf8())) {
                error = "Existing pimsync service uses different routing; it was not changed"; return false;
            }
            changes[path] = old;
        } else if (!old.isEmpty() && old != previousUnits.value(it.key()) && old != it.value()
                   && old != it.value().mid(unitMarker.size())) {
            error = "Calendar unit has custom settings; it was not overwritten"; return false;
        }
    }
    QSet<QString> wasActive, wasEnabled;
    for (const auto &unit : sharedUnits) {
        bool running = false;
        if (!active(unit, running, error)) return false;
        if (running) wasActive.insert(unit);
        if (unit != "quickshell-calendar-import.service"
            && command("systemctl", {"--user", "is-enabled", "--quiet", unit}, 10000)) wasEnabled.insert(unit);
    }
    bool reload = false, activationAttempted = false;
    // ponytail: ordinary errors clean up in memory; a killed add needs manual cleanup, not a crash journal.
    auto fail = [&] {
        const auto cause = error;
        QString cleanupError;
        if (activationAttempted) {
            for (const auto &unit : sharedUnits) if (!command("systemctl", {"--user", "stop", unit}, 30000)) {
                error = cause + "; could not stop calendar jobs for failed-add cleanup"; return false;
            }
            for (const auto &unit : QStringList{"pimsync.service", "quickshell-calendar-import.path"})
                if (!wasEnabled.contains(unit) && !command("systemctl", {"--user", "disable", unit}, 15000)) {
                    error = cause + "; could not disable failed calendar setup"; return false;
                }
        }
        for (const auto &path : written) {
            QByteArray actual;
            if (!readFile(path, actual, cleanupError, true, 64 * 1024 * 1024)
                || (actual != before[path] && (!changes.contains(path) || actual != changes[path]))) {
                error = cause + "; a file changed during the operation; newer contents were not overwritten"; return false;
            }
        }
        for (const auto &path : written) {
            const bool ok = missing.contains(path) ? removeFile(path, cleanupError) : writeFile(path, before[path], cleanupError);
            if (!ok) { error = cause + "; " + cleanupError; return false; }
        }
        if (!existing) {
            for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"})
                if (!removeFile(p.status + '/' + desired.pair() + ".status" + suffix, cleanupError)) { error = cause + "; " + cleanupError; return false; }
            if (QFileInfo(directory).isSymLink() || (QFileInfo::exists(directory) && !QDir(directory).removeRecursively())) {
                error = cause + "; could not remove failed calendar collection"; return false;
            }
        }
        if (reload && !command("systemctl", {"--user", "daemon-reload"}, 15000)) {
            error = cause + "; could not reload previous calendar units"; return false;
        }
        for (const auto &unit : sharedUnits) if (wasActive.contains(unit) && !command("systemctl", {"--user", "start", "--no-block", unit}, 30000)) {
            error = cause + "; could not resume previous calendar service"; return false;
        }
        if (refreshing) { QString ignored; status(p, id, false, cause, ignored); }
        error = cause;
        return false;
    };
    for (const auto &unit : sharedUnits) if (wasActive.contains(unit) && !command("systemctl", {"--user", "stop", unit}, 30000)) {
        error = "Could not stop calendar jobs before updating URL settings"; return fail();
    }
    if (!ensureDirectory(p.status, error) || !ensureDirectory(directory, error)) return fail();
    for (auto it = changes.begin(); it != changes.end(); ++it) {
        if (it.value() == before[it.key()] && !missing.contains(it.key())) continue;
        written.insert(it.key());
        if (!ensureDirectory(QFileInfo(it.key()).path(), error) || !writeFile(it.key(), it.value(), error)) return fail();
        reload = reload || it.key().startsWith(p.units + '/');
    }
    if (reload && !command("systemctl", {"--user", "daemon-reload"}, 15000)) { error = "Could not load calendar service definitions"; return fail(); }
    if (sync) {
        if (!command("pimsync", {"-c", p.config, "check", desired.pair()})) { error = "pimsync rejected the URL calendar configuration"; return fail(); }
        if (!command("pimsync", {"-c", p.config, "sync", desired.pair()})) { error = "Could not download calendar; check the URL and network"; return fail(); }
        QJsonObject currentRegistry;
        QByteArray currentConfig;
        if (!loadRegistry(p, currentRegistry, error) || profileFor(currentRegistry, id) != previousProfile
            || !readFile(p.config, currentConfig, error) || currentConfig != changes[p.config]) {
            error = "Calendar settings changed during download; newer data was preserved"; return fail();
        }
        written.insert(cachePath);
        if (!convert(p, desired, error)) return fail();
        if (!readFile(cachePath, changes[cachePath], error, false, 64 * 1024 * 1024)) return fail();
    }
    activationAttempted = true;
    for (const auto &unit : QStringList{"pimsync.service", "quickshell-calendar-import.path"}) {
        // Starting already-enabled units preserves runtime-only enablement too.
        const auto activation = wasEnabled.contains(unit) ? QStringList{"--user", "start", unit}
            : QStringList{"--user", "enable", "--now", unit};
        if (!command("systemctl", activation, 30000)) {
            error = "Could not start shared calendar services"; return fail();
        }
    }
    if (sync) {
        written.insert(statusPath);
        if (!status(p, id, true, {}, error)) return fail();
        if (!readFile(statusPath, changes[statusPath], error)) return fail();
    }
    if (!refreshing) {
        QJsonObject latest;
        if (!loadRegistry(p, latest, error) || profileFor(latest, id) != previousProfile) {
            error = "Calendar profile changed while adding; newer metadata was preserved"; return fail();
        }
        registry = latest;
        if (!readFile(registryPath, before[registryPath], error)) return fail();
        profile["name"] = profile.value("name").toString().trimmed();
        QJsonArray profiles;
        for (const auto &value : registry.value("profiles").toArray()) if (value.toObject().value("id") != id) profiles.append(value);
        profiles.append(profile); registry["profiles"] = profiles;
        changes[registryPath] = QJsonDocument(registry).toJson();
        written.insert(registryPath);
        if (!writeFile(registryPath, changes[registryPath], error)) return fail();
    }
    result = {{"ok", true}, {"id", id}, {"profile", profile}};
    return true;
}
} // namespace SubscriptionBackend
