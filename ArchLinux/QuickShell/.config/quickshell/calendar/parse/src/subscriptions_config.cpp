#include "subscriptions.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>
#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>

namespace SubscriptionBackend {
namespace {
const QByteArray beginMarker("# BEGIN quickshell-calendar subscriptions v1\n");
const QByteArray endMarker("# END quickshell-calendar subscriptions v1\n");
QString homePath(const char *variable, const QString &fallback) {
    const QString value = qEnvironmentVariable(variable);
    const QString path = value.isEmpty() ? qEnvironmentVariable("HOME") + fallback : value;
    const QString canonical = QDir(path).canonicalPath();
    return canonical.isEmpty() ? QDir::cleanPath(path) : canonical;
}
bool safeAncestors(QString path, QString &error) {
    if (!QDir::isAbsolutePath(path) || path != QDir::cleanPath(path) || QRegularExpression("[\\x00-\\x1f\\x7f]").match(path).hasMatch()) {
        error = "Subscription paths must be absolute and contain no control characters or traversal"; return false;
    }
    while (path != "/") {
        const auto anchor = QRegularExpression("^/proc/" + QString::number(getpid()) + "/fd/([0-9]+)$").match(path);
        if (anchor.hasMatch()) {
            struct stat stamp{};
            if (fstat(anchor.captured(1).toInt(), &stamp) == 0 && S_ISDIR(stamp.st_mode) && stamp.st_uid == geteuid()) return true;
            error = "Private subscription directory anchor is unavailable"; return false;
        }
        const QFileInfo directory(path);
        if (directory.isSymLink() || (directory.exists() && !directory.isDir())) {
            error = "Subscription directory path is linked or not a directory; inspect before continuing"; return false;
        }
        path = path.left(path.lastIndexOf('/'));
        if (path.isEmpty()) break;
    }
    return true;
}
QByteArray localBlock(const Paths &location) {
    return ("storage qs_subscription_local {\n    type vdir/icalendar\n    path \"" + location.data + "\"\n}\n").toUtf8();
}
} // namespace

Paths paths() {
    const QString config = homePath("XDG_CONFIG_HOME", "/.config");
    const QString state = homePath("XDG_STATE_HOME", "/.local/state");
    const QString module = qEnvironmentVariable("HOME") + "/.config/quickshell/calendar/parse";
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    return {config + "/pimsync/pimsync.conf", homePath("XDG_DATA_HOME", "/.local/share") + "/calendars",
            state + "/quickshell-calendar/subscriptions", config + "/systemd/user", module + "/calendar-sync-helper",
            module + "/convert", module + "/conflict-broker.sh",
            (runtime.isEmpty() ? state + "/quickshell-calendar" : runtime) + "/calendar-pimsync.lock", state + "/pimsync/status"};
}

bool validId(const QString &id) {
    return QRegularExpression("^[a-z0-9][a-z0-9_-]*$").match(id).hasMatch() && id.size() <= 128;
}

bool validateRecord(Record &record, QString &error) {
    if (!validId(record.id)) {
        error = "Choose a valid subscription ID";
        return false;
    }
    if (record.interval < 300) {
        error = "Refresh interval must be at least 5 minutes";
        return false;
    }
    const QString source = record.url.trimmed();
    if (source.isEmpty() || source.size() > 8192 || QRegularExpression("[\\x00-\\x20\\x7f]").match(source).hasMatch()) {
        error = "Use a direct calendar link without whitespace or control characters";
        return false;
    }
    QUrl url(source, QUrl::StrictMode);
    if (url.scheme().compare("webcal", Qt::CaseInsensitive) == 0 || url.scheme().compare("webcals", Qt::CaseInsensitive) == 0)
        url.setScheme("https");
    if (!url.isValid() || url.host().isEmpty() || url.authority().contains('@') || !url.fragment().isEmpty()
        || !QStringList{"http", "https"}.contains(url.scheme().toLower())) {
        error = "Use a direct HTTP(S) calendar link without credentials or fragments";
        return false;
    }
    record.url = QString::fromUtf8(url.toEncoded());
    return true;
}

bool readFile(const QString &path, QByteArray &data, QString &error, bool optional, qint64 limit) {
    if (!safeAncestors(path.left(path.lastIndexOf('/')), error)) return false;
    const int descriptor = open(QFile::encodeName(path).constData(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (descriptor < 0) {
        if (optional && errno == ENOENT) { data.clear(); return true; }
        error = "Could not read a required subscription file; inspect its path and permissions";
        return false;
    }
    struct stat stamp{};
    if (fstat(descriptor, &stamp) != 0 || !S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid()
        || stamp.st_nlink != 1 || stamp.st_size < 0 || stamp.st_size > limit) {
        close(descriptor);
        error = "Subscription file must be an owned, bounded regular file, not a link";
        return false;
    }
    QFile file;
    if (!file.open(descriptor, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
        close(descriptor); error = "Could not open subscription file"; return false;
    }
    data = file.read(limit + 1);
    if (file.error() != QFileDevice::NoError || data.size() > limit) {
        error = "Could not read bounded subscription file"; return false;
    }
    return true;
}

bool ensureDirectory(const QString &path, QString &error) {
    if (!safeAncestors(path, error)) return false;
    const bool existed = QFileInfo::exists(path);
    if (!QDir().mkpath(path)) { error = "Could not prepare subscription directory"; return false; }
    if (!existed && chmod(QFile::encodeName(path).constData(), 0700) != 0) { error = "Could not protect subscription directory"; return false; }
    struct stat stamp{};
    if (stat(QFile::encodeName(path).constData(), &stamp) != 0 || !S_ISDIR(stamp.st_mode) || stamp.st_uid != geteuid()) {
        error = "Subscription directory must belong to the current user"; return false;
    }
    return true;
}

bool writeFile(const QString &path, const QByteArray &data, QString &error, bool createOnly, bool *published) {
    if (published) *published = false;
    const QString parent = path.left(path.lastIndexOf('/'));
    if (!safeAncestors(parent, error)) return false;
    const QByteArray name = QFile::encodeName(path.mid(path.lastIndexOf('/') + 1));
    const int directory = open(QFile::encodeName(parent).constData(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directory < 0) { error = "Could not open subscription output directory"; return false; }
    struct stat stamp{};
    const int current = fstatat(directory, name.constData(), &stamp, AT_SYMLINK_NOFOLLOW);
    if ((current == 0 && (!S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid() || stamp.st_nlink != 1 || createOnly))
        || (current != 0 && errno != ENOENT)) {
        close(directory); error = "Subscription output changed or collides with an existing file/link"; return false;
    }
    const QByteArray temporary = ".subscription-" + QUuid::createUuid().toString(QUuid::Id128).toLatin1();
    const int descriptor = openat(directory, temporary.constData(), O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600);
    bool ok = descriptor >= 0;
    qint64 offset = 0;
    while (ok && offset < data.size()) {
        const ssize_t count = write(descriptor, data.constData() + offset, static_cast<size_t>(data.size() - offset));
        if (count < 0 && errno == EINTR) continue;
        ok = count > 0;
        if (ok) offset += count;
    }
    if (descriptor >= 0) {
        if (ok) ok = fsync(descriptor) == 0;
        if (close(descriptor) != 0) ok = false;
    }
    if (ok) {
        ok = createOnly ? linkat(directory, temporary.constData(), directory, name.constData(), 0) == 0
                        : renameat(directory, temporary.constData(), directory, name.constData()) == 0;
        if (published) *published = ok;
    }
    (void)unlinkat(directory, temporary.constData(), 0);
    if (ok) ok = fsync(directory) == 0;
    close(directory);
    if (!ok) error = "Could not atomically publish subscription file";
    return ok;
}

bool loadConfig(const Paths &location, Config &config, QString &error) {
    if (!QDir::isAbsolutePath(location.config) || !QDir::isAbsolutePath(location.data)
        || location.data.contains('"') || location.data.contains('\\') || location.data.contains('\n')) {
        error = "Subscription configuration/data paths are unsupported"; return false;
    }
    if (!readFile(location.config, config.original, error, true)) return false;
    const QByteArray &text = config.original;
    const auto first = text.indexOf(beginMarker);
    const auto last = text.indexOf(endMarker);
    if (first < 0 && last < 0) {
        config.prefix = text;
        if (QRegularExpression("(?m)^\\s*(?:storage|pair)\\s+qs_subscription_").match(QString::fromUtf8(text)).hasMatch()) {
            error = "Subscription namespace exists without ownership markers; inspect before managing it"; return false;
        }
        return true;
    }
    if (first < 0 || last < first || text.indexOf(beginMarker, first + beginMarker.size()) >= 0
        || text.indexOf(endMarker, last + endMarker.size()) >= 0 || (first != 0 && text[first - 1] != '\n')) {
        error = "Subscription ownership markers are ambiguous; existing configuration was preserved"; return false;
    }
    config.prefix = text.left(first);
    config.suffix = text.mid(last + endMarker.size());
    if (QRegularExpression("(?m)^\\s*(?:storage|pair)\\s+qs_subscription_").match(QString::fromUtf8(config.prefix + config.suffix)).hasMatch()) {
        error = "Subscription namespace also has unowned declarations; inspect before managing it"; return false;
    }
    QByteArray owned = text.mid(first + beginMarker.size(), last - first - beginMarker.size());
    const QByteArray local = localBlock(location);
    if (!owned.startsWith(local)) { error = "Owned subscription local storage differs from configured calendar directory"; return false; }
    owned.remove(0, local.size());
    if (owned.count('\n') == owned.size()) owned.clear();
    const QRegularExpression recordPattern(
        "\\A\\n*storage qs_subscription_source_([a-z0-9][a-z0-9_-]*) \\{\\n"
        "    type webcal\\n    url \"([^\"\\n\\\\]*)\"\\n    collection_id \\1\\n    interval ([0-9]+)\\n\\}\\n"
        "\\n*pair qs_subscription_\\1 \\{\\n    storage_a qs_subscription_source_\\1\\n"
        "    storage_b qs_subscription_local\\n    collection \\1\\n    one_way\\n"
        "    on_empty sync\\n    on_delete skip\\n\\}\\n\\n*");
    while (!owned.isEmpty()) {
        const auto match = recordPattern.match(QString::fromUtf8(owned));
        bool integer = false;
        Record record{match.captured(1), match.captured(2), match.captured(3).toInt(&integer)};
        if (!match.hasMatch() || !integer || !validateRecord(record, error)
            || std::any_of(config.records.begin(), config.records.end(), [&](const Record &other) { return other.id == record.id; })) {
            if (error.isEmpty()) error = "Owned subscription section has unsupported or duplicate entries";
            return false;
        }
        config.records.append(record);
        owned.remove(0, match.captured().toUtf8().size());
    }
    return true;
}

QByteArray renderConfig(const Paths &location, const Config &config, const QList<Record> &records) {
    QByteArray prefix = config.prefix;
    if (records.isEmpty()) return prefix + config.suffix;
    if (!prefix.isEmpty() && !prefix.endsWith('\n')) prefix += '\n';
    if (!prefix.isEmpty() && !prefix.endsWith("\n\n")) prefix += '\n';
    QByteArray result = prefix + beginMarker + localBlock(location);
    for (const Record &record : records) {
        result += ("\nstorage qs_subscription_source_" + record.id + " {\n    type webcal\n    url \"" + record.url
            + "\"\n    collection_id " + record.id + "\n    interval " + QString::number(record.interval)
            + "\n}\n\npair " + record.pair() + " {\n    storage_a qs_subscription_source_" + record.id
            + "\n    storage_b qs_subscription_local\n    collection " + record.id
            + "\n    one_way\n    on_empty sync\n    on_delete skip\n}\n").toUtf8();
    }
    return result + endMarker + config.suffix;
}
QString revision(const QByteArray &data) {
    return QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
}
QJsonObject recordJson(const Paths &location, const Record &record) {
    return {{"id", record.id}, {"url", record.url}, {"intervalSeconds", record.interval}, {"pair", record.pair()},
            {"collectionPath", location.data + "/" + record.id}, {"cachePath", location.data + "/" + record.id + ".json"},
            {"statusPath", location.status + "/" + record.pair() + ".status"}};
}
} // namespace SubscriptionBackend
