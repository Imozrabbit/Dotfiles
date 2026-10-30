#include "caldav.h"
#include "caldav_remote.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QTemporaryDir>
#include <QUrl>
#include <iostream>
#include <csignal>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

namespace CalDavBackend {
using namespace SubscriptionBackend;
namespace {
const QByteArray beginMarker("# BEGIN quickshell-calendar caldav v1\n");
const QByteArray endMarker("# END quickshell-calendar caldav v1\n");
const QByteArray recordMarker("# calendar ");
bool text(const QString &value, int maximum = 8192) {
    return !value.isEmpty() && value.size() <= maximum && !QRegularExpression("[\\x00-\\x1f\\x7f]").match(value).hasMatch();
}
} // namespace
Record recordFromJson(const QJsonObject &object) {
    return {object.value("id").toString(), object.value("url").toString(), object.value("username").toString(),
            object.value("passwordFile").toString(), object.value("remoteId").toString(), object.value("remoteHref").toString(),
            object.value("intervalSeconds").toInt(300)};
}
bool validIdentity(const Record &r) {
    const QUrl href(r.remoteHref, QUrl::StrictMode);
    return validId(r.id) && text(r.remoteId, 1024) && text(r.remoteHref) && r.remoteHref.startsWith('/')
        && !r.remoteHref.startsWith("//") && href.isValid() && href.isRelative() && href.query().isEmpty()
        && href.fragment().isEmpty() && href.path().endsWith('/') && r.interval >= 300;
}
namespace {
QByteArray storage(const QString &name, const Record &r, bool readOnly) {
    return ("storage " + name + " {\n    type caldav\n    url " + quoted(r.url) + "\n    username " + quoted(r.username)
        + "\n    password {\n        cmd /usr/bin/cat -- " + quoted(r.passwordFile)
        + "\n    }\n    auth_method basic\n    discovery principal\n" + (readOnly ? "    read_only\n" : "") + "}\n").toUtf8();
}
QByteArray section(const Paths &p, const QList<Record> &records, bool readOnly = false) {
    if (records.isEmpty()) return {};
    QByteArray output = beginMarker;
    for (const auto &r : records) {
        output += recordMarker + QJsonDocument(recordJson(r)).toJson(QJsonDocument::Compact).toBase64() + '\n';
        output += ("storage qs_caldav_local_" + r.id + " {\n    type vdir/icalendar\n    path " + quoted(p.data) + "\n}\n").toUtf8();
        output += storage("qs_caldav_remote_" + r.id, r, readOnly);
        output += ("pair " + r.pair() + " {\n    storage_a qs_caldav_local_" + r.id + "\n    storage_b qs_caldav_remote_" + r.id
            + "\n    collection {\n        alias " + quoted(r.id) + "\n        id_a " + quoted(r.id) + "\n        href_b " + quoted(r.remoteHref)
            + "\n    }\n    on_empty sync\n    on_delete skip\n    conflict_resolution cmd /usr/bin/env " + quoted("CALENDAR_ID=" + r.id)
            + " /bin/sh " + quoted(p.broker) + "\n}\n").toUtf8();
    }
    return output + endMarker;
}
} // namespace

QByteArray renderReadOnlyConfig(const Paths &p, const Record &record) {
    return ("status_path " + quoted(p.status) + '\n').toUtf8() + section(p, {record}, true);
}

Paths paths() {
    auto p = SubscriptionBackend::paths();
    p.state = p.state.left(p.state.lastIndexOf('/')) + "/caldav";
    return p;
}
QString quoted(QString value) { return '"' + value.replace("\\", "\\\\").replace("\"", "\\\"") + '"'; }

bool validateConnection(Record &r, QString &error) {
    if (!text(r.url) || !text(r.username, 512) || !text(r.passwordFile) || !QDir::isAbsolutePath(r.passwordFile)
        || QDir::cleanPath(r.passwordFile) != r.passwordFile) {
        error = "Use a server URL, username and absolute password-file path without control characters"; return false;
    }
    QUrl url(r.url.trimmed(), QUrl::StrictMode);
    if (!url.isValid() || url.host().isEmpty() || !url.userInfo().isEmpty() || !url.fragment().isEmpty() || !url.query().isEmpty()
        || !QStringList{"https", "http"}.contains(url.scheme())) {
        error = "Use an HTTP(S) server URL without embedded credentials, query or fragment"; return false;
    }
    if (url.scheme() == "http" && !QStringList{"127.0.0.1", "localhost", "::1"}.contains(url.host())) {
        error = "Use HTTPS to protect your calendar password; HTTP is allowed only for loopback tests"; return false;
    }
    auto path = url.path();
    while (path.endsWith('/')) path.chop(1);
    url.setPath(path + '/');
    r.url = QString::fromUtf8(url.toEncoded(QUrl::FullyEncoded));
    QString ancestor = r.passwordFile;
    struct stat stamp{};
    bool file = true;
    while (ancestor != "/") {
        if (lstat(QFile::encodeName(ancestor).constData(), &stamp) != 0 || S_ISLNK(stamp.st_mode)
            || (file ? (!S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid() || stamp.st_nlink != 1 || (stamp.st_mode & 0077)
                        || stamp.st_size <= 0 || stamp.st_size > 65536)
                     : (!S_ISDIR(stamp.st_mode) || ((stamp.st_mode & 0022) && !(stamp.st_mode & S_ISVTX))))) {
            error = "Password file must be an owned private regular file (0600), without linked or unsafe parents"; return false;
        }
        file = false;
        ancestor = QFileInfo(ancestor).path();
    }
    return true;
}

bool discover(Record r, QJsonArray &calendars, QString &error) {
    QString home;
    return discoverRemote(r, home, calendars, error);
}

QJsonObject recordJson(const Record &r) {
    return {{"id", r.id}, {"url", r.url}, {"username", r.username}, {"passwordFile", r.passwordFile},
            {"remoteId", r.remoteId}, {"remoteHref", r.remoteHref}, {"intervalSeconds", r.interval}};
}

QString remoteIdentity(const Record &r) {
    auto url = QUrl(r.url).resolved(QUrl(r.remoteHref)).adjusted(QUrl::NormalizePathSegments);
    if ((url.scheme() == "https" && url.port() == 443) || (url.scheme() == "http" && url.port() == 80)) url.setPort(-1);
    return QString::fromUtf8(url.toEncoded(QUrl::FullyEncoded)) + '\n' + r.username;
}

bool loadConfig(const Paths &p, Config &c, QString &error) {
    if (!readFile(p.config, c.original, error, true)) return false;
    const auto first = c.original.indexOf(beginMarker), last = c.original.indexOf(endMarker);
    if (first < 0 && last < 0) c.prefix = c.original;
    else {
        if (first < 0 || last < first || (first && c.original[first - 1] != '\n')
            || c.original.indexOf(beginMarker, first + beginMarker.size()) >= 0 || c.original.indexOf(endMarker, last + endMarker.size()) >= 0) {
            error = "CalDAV ownership markers are ambiguous; existing configuration was preserved"; return false;
        }
        c.prefix = c.original.left(first); c.suffix = c.original.mid(last + endMarker.size());
        const auto owned = c.original.mid(first, last + endMarker.size() - first);
        QSet<QString> ids, remotes;
        for (const auto &line : owned.split('\n')) {
            if (!line.startsWith(recordMarker)) continue;
            const auto data = QByteArray::fromBase64Encoding(line.mid(recordMarker.size()), QByteArray::AbortOnBase64DecodingErrors);
            const auto object = QJsonDocument::fromJson(data.decoded).object();
            auto r = recordFromJson(object);
            const auto key = remoteIdentity(r);
            // Loading settings does not read/stat credentials: offline metadata edits remain available.
            if (!data || object != recordJson(r) || !validIdentity(r) || !text(r.url) || !text(r.username) || !text(r.passwordFile)
                || ids.contains(r.id) || remotes.contains(key)) {
                error = "Owned CalDAV section has invalid or duplicate records"; return false;
            }
            ids.insert(r.id); remotes.insert(key); c.records.append(r);
        }
        if (owned != section(p, c.records)) { error = "Owned CalDAV configuration changed; inspect before managing it"; return false; }
    }
    if (QRegularExpression("(?m)^\\s*(?:storage|pair)\\s+qs_caldav_").match(QString::fromUtf8(c.prefix + c.suffix)).hasMatch()) {
        error = "CalDAV namespace has unowned declarations; no configuration was changed"; return false;
    }
    return true;
}

QByteArray renderConfig(const Paths &p, const Config &c, const QList<Record> &records) {
    auto prefix = c.prefix;
    if (!records.isEmpty() && !prefix.isEmpty() && !prefix.endsWith('\n')) prefix += '\n';
    return prefix + section(p, records) + c.suffix;
}

int run(const QStringList &arguments) {
    umask(0077);
    const struct rlimit noCore{0, 0};
    if (setrlimit(RLIMIT_CORE, &noCore) != 0) {
        std::cout << "{\"ok\":false,\"field\":\"storage\",\"message\":\"Could not disable credential-bearing core dumps\"}\n";
        return 1;
    }
    QString error;
    QJsonObject result;
    const auto p = CalDavBackend::paths();
    if (arguments.size() == 6 && arguments[0] == "convert-callback") {
        const bool ok = conversion(p, "convert-callback", {{"id", arguments[1]}, {"session", arguments[2]}, {"phase", arguments[3]},
            {"localPath", arguments[4]}, {"remotePath", arguments[5]}}, result, error);
        if (!error.isEmpty()) std::cerr << error.toStdString() << '\n';
        return ok ? 0 : 1;
    }
    if (arguments == QStringList{"daemon"}) return daemon(p);
    if (arguments == QStringList{"list"}) {
        Config config;
        QJsonObject status;
        if (CalDavBackend::loadConfig(p, config, error) && jsonFile(p.state + "/status.json", status, error)) {
            QJsonArray records;
            for (const auto &r : config.records) {
                auto value = recordJson(r);
                value["pair"] = r.pair();
                auto snapshot = status.value("records").toObject().value(r.id).toObject();
                QJsonObject unavailable;
                if (!unavailableStatus(p, r, unavailable, error)) break;
                if (unavailable.isEmpty()) { snapshot.remove("remoteState"); snapshot.remove("remoteTarget"); }
                if (snapshot.value("busy").toBool() && (snapshot.value("pid").toInt() <= 0 || kill(snapshot.value("pid").toInt(), 0) != 0)) {
                    snapshot["busy"] = false;
                    snapshot["error"] = "Previous synchronization was interrupted; cached calendar retained";
                }
                value["status"] = snapshot;
                records.append(value);
            }
            QJsonObject sessions, deletions, attachments;
            if (error.isEmpty() && conversion(p, "list", {}, sessions, error) && remoteDeletion(p, "list", {}, deletions, error)
                && attachment(p, "list", {}, attachments, error)) {
                auto all = sessions.value("conversions").toArray();
                for (const auto &session : deletions.value("conversions").toArray()) all.append(session);
                for (const auto &session : attachments.value("conversions").toArray()) all.append(session);
                result = {{"ok", true}, {"revision", revision(config.original)}, {"records", records}, {"conversions", all}};
            }
        }
    } else if (arguments.size() == 2 && arguments[0] == "sync") {
        synchronize(p, arguments[1], result, error);
    } else if (arguments.size() == 2 && arguments[0] == "trigger") {
        Config config;
        if (CalDavBackend::loadConfig(p, config, error)) {
            for (const auto &r : config.records) if (r.id == arguments[1]) {
                if (conversionAllowed(p, r.id, error) && remoteSyncAllowed(p, r.id, error) && command("systemctl", {"--user", "start", "--no-block", "quickshell-calendar-caldav@" + r.id + ".service"}, 10000))
                    result = {{"ok", true}, {"id", r.id}};
                else if (error.isEmpty()) error = "Could not start calendar synchronization";
            }
        }
    } else if (arguments.size() == 2 && arguments[0] == "preflight") {
        Lease lease; Config config;
        const auto id = arguments[1];
        if (lease.acquire(p, error) && conversionAllowed(p, id, error) && loadConfig(p, config, error)) {
            bool ok = true;
            for (const auto &record : config.records) if (record.id == id) ok = checkRemoteForSync(p, record, error);
            result = {{"ok", ok}, {"id", id}};
        }
    } else if (arguments.size() == 1 && QStringList{"discover", "save", "create", "remove", "convert-begin", "convert-finish", "convert-cancel", "remote-delete-begin", "remote-delete-cancel", "remote-delete-finish", "remote-delete-retry", "local-preserve-begin", "remote-recheck", "attach-begin", "attach-finish", "attach-cancel", "attach-retry"}.contains(arguments[0])) {
        QFile input;
        QByteArray bytes;
        const qint64 limit = arguments[0] == "convert-finish" || arguments[0] == "remote-delete-finish" || arguments[0] == "attach-finish" ? 64LL * 1024 * 1024 : 65536;
        if (input.open(stdin, QIODevice::ReadOnly)) bytes = input.readLine(limit + 1);
        QJsonParseError parsed;
        const auto doc = QJsonDocument::fromJson(bytes, &parsed);
        QJsonArray calendars;
        if (bytes.size() > limit || parsed.error != QJsonParseError::NoError || !doc.isObject()) error = "CalDAV request is invalid or too large";
        else if (arguments[0] == "save") CalDavBackend::settings(p, doc.object(), result, error);
        else if (arguments[0] == "create") createRemoteAndAdd(p, doc.object(), result, error);
        else if (arguments[0] == "remove") CalDavBackend::remove(p, doc.object(), result, error);
        else if (arguments[0] == "remote-recheck") recheckRemote(p, doc.object(), result, error);
        else if (arguments[0].startsWith("attach-")) attachment(p, arguments[0], doc.object(), result, error);
        else if (arguments[0].startsWith("convert-")) conversion(p, arguments[0], doc.object(), result, error);
        else if (arguments[0].startsWith("remote-delete-") || arguments[0] == "local-preserve-begin") remoteDeletion(p, arguments[0], doc.object(), result, error);
        else {
            auto connection = recordFromJson(doc.object());
            QString home;
            if (discoverRemote(connection, home, calendars, error)) result = {{"ok", true}, {"homeHref", home}, {"calendars", calendars}};
        }
    }
    if (!result.value("ok").toBool()) {
        result["ok"] = false;
        if (!result.contains("field")) result["field"] = "storage";
        result["message"] = error.isEmpty() ? result.value("message").toString("Unknown CalDAV operation") : error;
    }
    std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << '\n';
    return result.value("ok").toBool() ? 0 : 1;
}
} // namespace CalDavBackend
