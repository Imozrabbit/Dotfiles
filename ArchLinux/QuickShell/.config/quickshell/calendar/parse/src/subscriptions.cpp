#include "subscriptions.h"
#include "caldav.h"
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <iostream>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

namespace SubscriptionBackend {
Lease::~Lease() { if (descriptor >= 0) close(descriptor); }
bool Lease::acquire(const Paths &location, QString &error, bool wait) {
    const QString parent = location.lock.left(location.lock.lastIndexOf('/'));
    if (!ensureDirectory(parent, error)) return false;
    descriptor = open(QFile::encodeName(location.lock).constData(), O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    struct stat stamp{};
    if (descriptor < 0 || fstat(descriptor, &stamp) != 0 || !S_ISREG(stamp.st_mode)
        || stamp.st_uid != geteuid() || stamp.st_nlink != 1 || flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) != 0) {
        error = "Another calendar sync operation is running or the runtime lock is unsafe";
        return false;
    }
    return true;
}

bool Lease::inherit(const Paths &location, QString &error) {
    struct stat inherited{}, expected{};
    if (fstat(9, &inherited) != 0 || lstat(QFile::encodeName(location.lock).constData(), &expected) != 0
        || !S_ISREG(expected.st_mode) || inherited.st_uid != geteuid() || inherited.st_nlink != 1
        || inherited.st_dev != expected.st_dev || inherited.st_ino != expected.st_ino || flock(9, LOCK_EX | LOCK_NB) != 0) {
        error = "Updater did not pass the verified shared calendar lock"; return false;
    }
    descriptor = fcntl(9, F_DUPFD_CLOEXEC, 10);
    return descriptor >= 0;
}

bool command(const QString &program, const QStringList &arguments, int timeout, bool conflictSnapshots) {
    QProcess process;
    const pid_t parent = getpid();
    process.setChildProcessModifier([parent, conflictSnapshots] {
        const struct rlimit noCore{0, 0};
        // Group callbacks initialize Qt/timezones and can publish bounded 616-MiB snapshots.
        const rlim_t memoryLimit = conflictSnapshots ? 4ULL * 1024 * 1024 * 1024 : 512ULL * 1024 * 1024;
        const rlim_t fileLimit = conflictSnapshots ? 640ULL * 1024 * 1024 : 64ULL * 1024 * 1024;
        const struct rlimit memory{memoryLimit, memoryLimit};
        const struct rlimit fileBytes{fileLimit, fileLimit};
        if (prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent || setrlimit(RLIMIT_CORE, &noCore) != 0
            || setrlimit(RLIMIT_AS, &memory) != 0 || setrlimit(RLIMIT_FSIZE, &fileBytes) != 0)
            _exit(1);
    });
    process.setStandardOutputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
    process.start(program, arguments);
    if (!process.waitForStarted(5000) || !process.waitForFinished(timeout)) {
        process.kill(); process.waitForFinished(5000); return false;
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

bool jsonFile(const QString &path, QJsonObject &object, QString &error, bool optional, qint64 limit) {
    QByteArray bytes;
    if (!readFile(path, bytes, error, optional, limit)) return false;
    if (bytes.isEmpty() && optional) { object = {}; return true; }
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(bytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        error = "Subscription metadata is malformed; inspect it before continuing"; return false;
    }
    object = document.object();
    return true;
}

int run(const QStringList &arguments) {
    umask(0077);
    QString error;
    Config config;
    QJsonObject result;
    const Paths location = paths();
    if (arguments == QStringList{"initialize-registry"}) {
        QByteArray existing;
        const auto path = location.data + "/profiles.json";
        bool ok = ensureDirectory(location.data, error) && readFile(path, existing, error, true);
        if (ok && !QFileInfo::exists(path)) ok = writeFile(path, "{\"version\":1,\"profiles\":[]}\n", error, true);
        result = {{"ok", ok}};
    } else if (arguments.size() == 2 && arguments[0] == "initialize-local") {
        QJsonObject registry;
        const auto id = arguments[1];
        Lease lease;
        bool ok = validId(id) && lease.acquire(location, error) && CalDavBackend::attachmentAllowed(CalDavBackend::paths(), id, error)
            && loadRegistry(location, registry, error);
        bool local = false;
        if (ok) for (const auto &value : registry.value("profiles").toArray())
            if (value.toObject().value("id") == id && value.toObject().value("type") == "local") local = true;
        if (!local && error.isEmpty()) error = "Local calendar not found; no event file was created";
        ok = ok && local && writeFile(location.data + '/' + id + ".json", "{\"version\":1,\"events\":[]}\n", error, true);
        result = {{"ok", ok}};
    } else if (arguments == QStringList{"list"} && loadConfig(location, config, error)) {
        QJsonArray records;
        QJsonObject statuses;
        const bool statusOk = jsonFile(location.state + "/status.json", statuses, error);
        for (const Record &record : config.records) {
            QJsonObject value = recordJson(location, record);
            QJsonObject status = statuses.value("records").toObject().value(record.id).toObject();
            if (status.value("busy").toBool() && (status.value("pid").toInt() <= 0 || kill(status.value("pid").toInt(), 0) != 0)) {
                status["busy"] = false;
                status["error"] = "Previous refresh was interrupted; cached calendar retained";
            }
            value["status"] = status;
            records.append(value);
        }
        result = {{"ok", statusOk}, {"revision", revision(config.original)}, {"records", records}};
    } else if (arguments.size() == 2 && QStringList{"trigger", "refresh"}.contains(arguments[0])) {
        settings(location, "refresh", QJsonObject{{"id", arguments[1]}}, result, error);
    } else if (arguments == QStringList{"cache"} && loadConfig(location, config, error)) {
        const bool ok = cache(location, config, error);
        result = {{"ok", ok}};
    } else if (arguments.size() == 1 && QStringList{"save", "remove", "remove-local", "remove-imported", "import-local", "read-imported"}.contains(arguments[0])) {
        QFile input;
        QByteArray bytes;
        if (input.open(stdin, QIODevice::ReadOnly)) bytes = input.readLine(65537);
        QJsonParseError parse;
        const auto request = QJsonDocument::fromJson(bytes, &parse);
        if (bytes.size() > 65536 || parse.error != QJsonParseError::NoError || !request.isObject())
            error = "Subscription request is invalid or too large";
        else if (arguments[0] == "import-local") importLocal(location, request.object(), result, error);
        else if (arguments[0] == "read-imported") readImported(location, request.object(), result, error);
        else if (arguments[0] == "remove-local" || arguments[0] == "remove-imported") {
            auto removal = request.object();
            removal["type"] = arguments[0] == "remove-local" ? "local" : "imported";
            removeLocal(location, removal, result, error);
        }
        else if (arguments[0] == "remove") remove(location, request.object(), result, error);
        else settings(location, "save", request.object(), result, error);
    } else if ((arguments == QStringList{"units"} || arguments == QStringList{"units", "--locked"}
                || arguments == QStringList{"runtime"}) && loadConfig(location, config, error)) {
        const bool checkOnly = arguments[0] == "runtime";
        Lease lease;
        const bool locked = checkOnly || (arguments.size() == 2 ? lease.inherit(location, error) : lease.acquire(location, error));
        const bool ok = locked && installUnits(location, config, error, checkOnly);
        result = {{"ok", ok}, {"files", QJsonArray::fromStringList(unitFiles(config))}, {"units", QJsonArray::fromStringList(unitNames(config))}};
    }
    if (!result.value("ok").toBool())
        result = {{"ok", false}, {"field", "storage"}, {"message", error.isEmpty() ? QString("Unknown subscription operation") : error}};
    std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << '\n';
    return result.value("ok").toBool() ? 0 : 1;
}
} // namespace SubscriptionBackend
