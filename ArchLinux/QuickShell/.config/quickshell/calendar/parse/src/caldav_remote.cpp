#include "caldav_remote.h"
#include <algorithm>
#include <QCryptographicHash>
#include <QDeadlineTimer>
#include <QEventLoop>
#include <QNetworkAccessManager>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSet>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QTimer>
#include <QUrl>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>

namespace CalDavBackend {
namespace {
const QString dav = QStringLiteral("DAV:");
const QString caldav = QStringLiteral("urn:ietf:params:xml:ns:caldav");
constexpr qint64 snapshotLimit = 64LL * 1024 * 1024;
struct Reply { int status = 0; QByteArray body, etag; bool complete = false; };
struct Resource { QString href; QMap<QString, QString> properties; int status = 200; };

bool safeUrl(const QUrl &base, const QString &href, QUrl &out, QString &error) {
    const QUrl relative(href, QUrl::StrictMode);
    const auto encodedPath = relative.path(QUrl::FullyEncoded);
    const auto decodedPath = relative.path(QUrl::FullyDecoded);
    const auto pieces = decodedPath.split('/');
    out = base.resolved(relative);
    if (!relative.isValid() || href.isEmpty() || href.contains(QRegularExpression("[\\x00-\\x20\\x7f]"))
        || relative.hasQuery() || relative.hasFragment() || !relative.userInfo().isEmpty()
        || decodedPath.contains(QRegularExpression("[\\x00-\\x1f\\x7f]"))
        || encodedPath.contains(QRegularExpression("%(?:2f|5c)", QRegularExpression::CaseInsensitiveOption))
        || decodedPath.contains('\\') || pieces.contains(".") || pieces.contains("..")
        || out.scheme() != base.scheme() || out.host() != base.host()
        || out.port(out.scheme() == "https" ? 443 : 80) != base.port(base.scheme() == "https" ? 443 : 80)
        || !out.userInfo().isEmpty()) {
        error = "Unsafe or cross-origin calendar URL; no remote change attempted";
        return false;
    }
    return true;
}
QString hrefFor(const QUrl &url) { return url.path(QUrl::FullyEncoded); }
bool childOf(const QString &href, const QString &home) {
    return home.startsWith('/') && home.endsWith('/') && href.startsWith(home)
        && href != home && href.endsWith('/');
}
bool sameHome(const QString &actual, const QString &expected, QString &error) {
    if (actual == expected) return true;
    error = "Calendar home changed; reconnect before continuing";
    return false;
}

class Client {
    QNetworkAccessManager manager;
    QDeadlineTimer deadline{90000};
    QByteArray authorization;
public:
    QUrl base;
    bool valid = false;
    Client(Record connection, QString &error) {
        if (!validateConnection(connection, error)) return;
        QByteArray password;
        if (!SubscriptionBackend::readFile(connection.passwordFile, password, error, false, 65536)) return;
        while (password.endsWith('\n')) {
            password.chop(1);
            if (password.endsWith('\r')) password.chop(1);
        }
        authorization = "Basic " + (connection.username.toUtf8() + ':' + password).toBase64();
        base = QUrl(connection.url);
        manager.setProxy(QNetworkProxy::NoProxy);
        valid = true;
    }
    Reply request(const QByteArray &method, const QUrl &url, const QByteArray &body, int depth,
                  QString &error, qint64 limit = 1024 * 1024, const QByteArray &match = {}) {
        Reply result;
        if (!valid || deadline.hasExpired()) { error = "Calendar request timed out"; return result; }
        QUrl checked;
        if (!safeUrl(base, url.toString(QUrl::FullyEncoded), checked, error)) return result;
        QNetworkRequest request(checked);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
        auto ssl = QSslConfiguration::defaultConfiguration();
        ssl.setPeerVerifyMode(QSslSocket::VerifyPeer);
        request.setSslConfiguration(ssl);
        request.setRawHeader("Authorization", authorization);
        request.setRawHeader("Content-Type", "application/xml; charset=utf-8");
        if (depth >= 0) request.setRawHeader("Depth", QByteArray::number(depth));
        if (method == "MKCALENDAR") request.setRawHeader("If-None-Match", "*");
        if (!match.isEmpty()) request.setRawHeader("If-Match", match);
        auto *reply = manager.sendCustomRequest(request, method, body);
        reply->setReadBufferSize(65536);
        QEventLoop loop;
        QTimer timer;
        timer.setSingleShot(true);
        bool overflow = false, timeout = false;
        auto collect = [&] {
            const auto bytes = reply->readAll();
            if (result.body.size() > limit - bytes.size()) {
                overflow = true; reply->abort();
            } else result.body += bytes;
        };
        QObject::connect(reply, &QIODevice::readyRead, &loop, collect);
        QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
        QObject::connect(&timer, &QTimer::timeout, &loop, [&] { timeout = true; reply->abort(); });
        timer.start(int(qMin<qint64>(30000, deadline.remainingTime())));
        if (!reply->isFinished()) loop.exec();
        collect();
        result.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        result.etag = reply->rawHeader("ETag");
        result.complete = !overflow && !timeout && (reply->error() == QNetworkReply::NoError
            || (result.status == 410 && reply->error() == QNetworkReply::ContentGoneError)
            || (result.status == 404 && reply->error() == QNetworkReply::ContentNotFoundError));
        if (!result.complete || result.status < 200 || result.status >= 300)
            error = overflow ? "Calendar response exceeds size limit" : timeout ? "Calendar request timed out"
                : "Calendar request failed (HTTP " + QString::number(result.status) + ")";
        delete reply;
        return result;
    }
};

int statusCode(const QString &text) {
    const auto match = QRegularExpression("^HTTP/[0-9.]+ ([0-9]{3})(?: .*)?$").match(text.trimmed());
    return match.hasMatch() ? match.captured(1).toInt() : 0;
}
QMap<QString, QString> readProperties(QXmlStreamReader &xml) {
    QMap<QString, QString> values;
    while (xml.readNextStartElement()) {
        const auto ns = xml.namespaceUri().toString(), name = xml.name().toString();
        if (ns == dav && name == "resourcetype") {
            QStringList types;
            while (xml.readNextStartElement()) {
                if (xml.namespaceUri() == dav && xml.name() == "collection") types.append("collection");
                if (xml.namespaceUri() == caldav && xml.name() == "calendar") types.append("calendar");
                xml.skipCurrentElement();
            }
            values["type"] = types.join(' ');
        } else if ((ns == dav && name == "current-user-principal") || (ns == caldav && name == "calendar-home-set")) {
            QString href;
            while (xml.readNextStartElement()) {
                if (xml.namespaceUri() == dav && xml.name() == "href") {
                    if (!href.isEmpty()) xml.raiseError("Multiple calendar homes/principals are unsupported");
                    href = xml.readElementText();
                } else xml.skipCurrentElement();
            }
            values[name == "current-user-principal" ? "principal" : "home"] = href;
        } else if ((ns == dav && QStringList{"getetag", "getcontenttype", "displayname"}.contains(name))
                   || (ns == caldav && name == "calendar-data")) {
            values[name] = xml.readElementText();
        } else xml.skipCurrentElement();
    }
    return values;
}
bool parse(const Reply &reply, QList<Resource> &resources, QString &error) {
    if (reply.status != 207 || !reply.complete) return false;
    QXmlStreamReader xml(reply.body);
    while (!xml.atEnd()) {
        const auto token = xml.readNext();
        if (token == QXmlStreamReader::DTD) { error = "Calendar XML declarations/entities are unsupported"; return false; }
        if (token == QXmlStreamReader::StartElement) break;
    }
    if (xml.namespaceUri() != dav || xml.name() != "multistatus") { error = "Malformed calendar response"; return false; }
    while (xml.readNextStartElement()) {
        if (xml.namespaceUri() != dav || xml.name() != "response") { xml.raiseError("Unsupported DAV result"); break; }
        Resource resource;
        while (xml.readNextStartElement()) {
            if (xml.namespaceUri() != dav) { xml.skipCurrentElement(); continue; }
            if (xml.name() == "href") resource.href = xml.readElementText();
            else if (xml.name() == "status") resource.status = statusCode(xml.readElementText());
            else if (xml.name() == "propstat") {
                QMap<QString, QString> properties;
                int status = 0;
                while (xml.readNextStartElement()) {
                    if (xml.namespaceUri() == dav && xml.name() == "prop") properties = readProperties(xml);
                    else if (xml.namespaceUri() == dav && xml.name() == "status") status = statusCode(xml.readElementText());
                    else xml.skipCurrentElement();
                }
                if (status == 200) {
                    for (auto it = properties.begin(); it != properties.end(); ++it) {
                        if (resource.properties.contains(it.key())) xml.raiseError("Duplicate DAV property");
                        resource.properties[it.key()] = it.value();
                    }
                }
            } else xml.skipCurrentElement();
        }
        if (resource.href.isEmpty() || resource.status != 200) xml.raiseError("Incomplete DAV result");
        resources.append(resource);
    }
    while (!xml.atEnd()) xml.readNext();
    if (xml.hasError() || resources.isEmpty()) { error = "Malformed or incomplete calendar response"; return false; }
    return true;
}
QByteArray propertiesBody(const QStringList &properties) {
    QByteArray body;
    QXmlStreamWriter xml(&body);
    xml.writeStartDocument();
    xml.writeStartElement("D:propfind");
    xml.writeNamespace(dav, "D"); xml.writeNamespace(caldav, "C");
    xml.writeStartElement("D:prop");
    for (const auto &property : properties) xml.writeEmptyElement(property);
    xml.writeEndElement(); xml.writeEndElement(); xml.writeEndDocument();
    return body;
}
bool propfind(Client &client, const QUrl &url, int depth, QList<Resource> &resources, QString &error) {
    return parse(client.request("PROPFIND", url, propertiesBody({"D:current-user-principal", "C:calendar-home-set", "D:resourcetype", "D:displayname", "D:getetag", "D:getcontenttype"}), depth, error), resources, error);
}
const Resource *exact(const QList<Resource> &resources, Client &client, const QUrl &url, QString &error) {
    const Resource *found = nullptr;
    for (const auto &resource : resources) {
        QUrl href;
        if (!safeUrl(client.base, resource.href, href, error)) return nullptr;
        if (href == url) {
            if (found) { error = "Duplicate calendar response"; return nullptr; }
            found = &resource;
        }
    }
    if (!found && error.isEmpty()) error = "Required calendar response is missing";
    return found;
}
bool discover(Client &client, QString &homeHref, QJsonArray &calendars, QString &error) {
    QList<Resource> root;
    if (!client.valid || !propfind(client, client.base, 0, root, error)) return false;
    const auto *base = exact(root, client, client.base, error);
    if (!base) return false;
    QUrl home, principal;
    const auto principalHref = base->properties.value("principal");
    QString candidate = base->properties.value("home");
    if (!principalHref.isEmpty()) {
        if (!safeUrl(client.base, principalHref, principal, error)) return false;
        QList<Resource> account;
        if (!propfind(client, principal, 0, account, error)) return false;
        const auto *current = exact(account, client, principal, error);
        if (!current) return false;
        if (!candidate.isEmpty() && candidate != current->properties.value("home")) {
            error = "Calendar home changed during discovery"; return false;
        }
        candidate = current->properties.value("home");
    }
    if (!safeUrl(client.base, candidate, home, error) || !home.path().endsWith('/')) return false;
    QList<Resource> listing;
    if (!propfind(client, home, 1, listing, error)) return false;
    const auto *parent = exact(listing, client, home, error);
    if (!parent || parent->properties.value("type") != "collection") {
        if (error.isEmpty()) error = "Calendar home is not a verified account collection";
        return false;
    }
    homeHref = hrefFor(home);
    QSet<QString> seen;
    for (const auto &entry : listing) {
        QUrl href;
        if (!safeUrl(client.base, entry.href, href, error)) return false;
        if (href == home) continue;
        const auto type = entry.properties.value("type");
        if (type.isEmpty()) { error = "Incomplete calendar listing"; return false; }
        if (!type.split(' ').contains("calendar")) continue;
        const auto path = hrefFor(href);
        if (!childOf(path, homeHref) || seen.contains(path) || calendars.size() >= 256) { error = "Unsafe, duplicate or excessive calendar collection listing"; return false; }
        seen.insert(path);
        const auto id = href.path(QUrl::FullyDecoded).split('/', Qt::SkipEmptyParts).last();
        if (id.size() > 1024 || id.contains(QRegularExpression("[\\x00-\\x1f\\x7f]"))) {
            error = "Unsupported remote calendar identifier"; return false;
        }
        calendars.append(QJsonObject{{"id", id}, {"href", path}});
    }
    return true;
}
bool targetUrl(Client &client, const Record &target, const QString &home, QUrl &url, QString &error) {
    if (!validIdentity(target) || !safeUrl(client.base, target.remoteHref, url, error) || !childOf(hrefFor(url), home)) {
        if (error.isEmpty()) error = "Remote target must be a calendar below its authenticated home";
        return false;
    }
    return true;
}
bool snapshot(Client &client, const Record &target, const QString &home, RemoteSnapshot &out, QString &error) {
    QUrl url;
    if (!targetUrl(client, target, home, url, error)) return false;
    QList<Resource> entries;
    const auto response = client.request("PROPFIND", url, propertiesBody({"D:resourcetype", "D:getetag", "D:getcontenttype"}), 1, error, snapshotLimit);
    if (!parse(response, entries, error)) return false;
    const auto *calendar = exact(entries, client, url, error);
    if (!calendar || !calendar->properties.value("type").split(' ').contains("calendar")) {
        if (error.isEmpty()) error = "Remote target is not a verified calendar";
        return false;
    }
    QMap<QString, QByteArray> fingerprints;
    qint64 total = 0;
    for (const auto &entry : entries) {
        QUrl member;
        if (!safeUrl(client.base, entry.href, member, error)) return false;
        if (member == url) continue;
        const auto href = hrefFor(member), etag = entry.properties.value("getetag");
        if (!href.startsWith(hrefFor(url)) || href.endsWith('/') || etag.isEmpty()
            || !entry.properties.value("getcontenttype").startsWith("text/calendar", Qt::CaseInsensitive)
            || out.resources.contains(href)) { error = "Calendar has an unreadable or unsupported member"; return false; }
        const auto data = client.request("GET", member, {}, -1, error, snapshotLimit, etag.toUtf8());
        if (!data.complete || data.status != 200 || data.etag != etag.toUtf8()) {
            if (error.isEmpty()) error = "Calendar member changed while reading";
            return false;
        }
        total += data.body.size();
        if (total > snapshotLimit) { error = "Calendar snapshot exceeds size limit"; return false; }
        out.resources[href] = data.body;
        fingerprints[href] = etag.toUtf8() + '\0' + QCryptographicHash::hash(data.body, QCryptographicHash::Sha256).toHex();
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    for (auto it = fingerprints.begin(); it != fingerprints.end(); ++it) {
        const auto key = it.key().toUtf8(), value = it.value();
        hash.addData(QByteArray::number(key.size()) + ':' + key + QByteArray::number(value.size()) + ':' + value);
    }
    out.homeHref = home;
    out.fingerprint = QString::fromLatin1(hash.result().toHex());
    error.clear();
    return true;
}
}

bool discoverRemote(Record &connection, QString &homeHref, QJsonArray &calendars, QString &error) {
    homeHref.clear(); calendars = {}; error.clear();
    if (!validateConnection(connection, error)) return false;
    Client client(connection, error);
    return discover(client, homeHref, calendars, error);
}
bool snapshotRemote(const Record &target, RemoteSnapshot &out, QString &error) {
    out = {}; error.clear();
    Client client(target, error);
    QString home; QJsonArray calendars;
    return discover(client, home, calendars, error) && snapshot(client, target, home, out, error);
}
RemoteAvailability remoteAvailability(const Record &target, QString &error) {
    error.clear();
    Client client(target, error);
    QString home; QJsonArray calendars;
    if (!discover(client, home, calendars, error)) return RemoteAvailability::Error;
    QUrl url;
    if (!targetUrl(client, target, home, url, error)) return RemoteAvailability::Error;
    const auto reply = client.request("PROPFIND", url, propertiesBody({"D:resourcetype"}), 0, error);
    const bool listed = std::any_of(calendars.begin(), calendars.end(), [&](const auto &entry) { return entry.toObject().value("href") == target.remoteHref; });
    if (reply.complete && reply.status == 410 && !listed) {
        error = "Remote calendar deleted. Synchronization paused; local events retained.";
        return RemoteAvailability::Deleted;
    }
    if (reply.complete && reply.status == 404) {
        error = "Remote calendar unavailable (HTTP 404: missing or permission-hidden). Synchronization paused; local events retained.";
        return RemoteAvailability::Unavailable;
    }
    QList<Resource> resources;
    if (!parse(reply, resources, error)) return RemoteAvailability::Error;
    const auto *calendar = exact(resources, client, url, error);
    if (!calendar || !calendar->properties.value("type").split(' ').contains("calendar")) {
        if (error.isEmpty()) error = "Remote target is not a verified calendar; synchronization not attempted";
        return RemoteAvailability::Error;
    }
    error.clear();
    return RemoteAvailability::Available;
}
RemotePresence inspectRemote(const Record &target, const QString &homeHref, RemoteSnapshot &out, QString &error) {
    out = {}; error.clear();
    Client client(target, error);
    QString home; QJsonArray calendars;
    if (!discover(client, home, calendars, error) || !sameHome(home, homeHref, error)) return RemotePresence::Unknown;
    QUrl url;
    if (!targetUrl(client, target, home, url, error)) return RemotePresence::Unknown;
    QList<Resource> resources;
    const auto reply = client.request("PROPFIND", url, propertiesBody({"D:resourcetype"}), 0, error);
    if (reply.complete && reply.status == 410 && std::none_of(calendars.begin(), calendars.end(), [&](const auto &entry) { return entry.toObject().value("href") == target.remoteHref; })) {
        out.homeHref = home; error.clear(); return RemotePresence::Absent;
    }
    if (reply.status == 404) {
        error = "Collection is missing or permission-hidden (HTTP 404); deletion is not confirmed";
        return RemotePresence::Unknown;
    }
    if (!parse(reply, resources, error) || !snapshot(client, target, home, out, error)) return RemotePresence::Unknown;
    return RemotePresence::Present;
}
RemoteOutcome createRemoteCollection(Record &target, const QString &homeHref, const QString &displayName,
                                     const QString &identifier, QString &error) {
    error.clear();
    if (!SubscriptionBackend::validId(identifier) || !validRemoteName(displayName)) {
        error = "Use a valid collection identifier and single-line remote name (maximum 512 characters)";
        return RemoteOutcome::Refused;
    }
    Client client(target, error);
    QString home; QJsonArray calendars;
    if (!discover(client, home, calendars, error) || !sameHome(home, homeHref, error)) return RemoteOutcome::Refused;
    if (calendars.size() >= 256) { error = "Calendar discovery limit reached; nothing created"; return RemoteOutcome::Refused; }
    target.remoteId = identifier; target.remoteHref = home + identifier + '/';
    QUrl url;
    if (!targetUrl(client, target, home, url, error)) return RemoteOutcome::Refused;
    if (std::any_of(calendars.begin(), calendars.end(), [&](const auto &entry) { return entry.toObject().value("href") == target.remoteHref; })) {
        error = "Remote collection identifier already exists; nothing overwritten"; return RemoteOutcome::Refused;
    }
    QByteArray body;
    QXmlStreamWriter xml(&body);
    xml.writeStartDocument(); xml.writeStartElement("C:mkcalendar");
    xml.writeNamespace(dav, "D"); xml.writeNamespace(caldav, "C");
    xml.writeStartElement("D:set"); xml.writeStartElement("D:prop");
    xml.writeTextElement("D:displayname", displayName);
    xml.writeStartElement("C:supported-calendar-component-set");
    xml.writeEmptyElement("C:comp"); xml.writeAttribute("name", "VEVENT");
    xml.writeEndElement(); xml.writeEndElement(); xml.writeEndElement(); xml.writeEndElement(); xml.writeEndDocument();
    const auto reply = client.request("MKCALENDAR", url, body, -1, error);
    if (reply.complete && reply.status == 201) { error.clear(); return RemoteOutcome::Succeeded; }
    if (QList<int>{400, 401, 403, 405, 409, 412, 415, 501}.contains(reply.status)) return RemoteOutcome::Refused;
    return RemoteOutcome::Uncertain;
}
bool validRemoteName(const QString &displayName) {
    if (displayName.trimmed().isEmpty() || displayName.toUcs4().size() > 512) return false;
    for (const auto character : displayName) {
        if (character.category() == QChar::Other_Control || character.category() == QChar::Separator_Line
            || character.category() == QChar::Separator_Paragraph) return false;
    }
    return true;
}
RemoteOutcome deleteRemoteCollection(const Record &target, const QString &homeHref, QString &error, bool *conservative) {
    error.clear();
    if (conservative) *conservative = false;
    Client client(target, error);
    QUrl url;
    if (!targetUrl(client, target, homeHref, url, error)) return RemoteOutcome::Refused;
    QString home; QJsonArray calendars;
    if (!discover(client, home, calendars, error) || !sameHome(home, homeHref, error)) return RemoteOutcome::Refused;
    QList<Resource> properties;
    if (!propfind(client, url, 0, properties, error)) return RemoteOutcome::Refused;
    const auto *calendar = exact(properties, client, url, error);
    if (!calendar || !calendar->properties.value("type").split(' ').contains("calendar")) {
        if (error.isEmpty()) error = "Remote deletion target is not a verified calendar";
        return RemoteOutcome::Refused;
    }
    const auto reply = client.request("DELETE", url, {}, -1, error);
    if (conservative) *conservative = reply.status == 202 || reply.status == 207;
    if (reply.complete && (reply.status == 200 || reply.status == 204)) { error.clear(); return RemoteOutcome::Succeeded; }
    if (QList<int>{400, 401, 403, 405, 409, 412, 415, 501}.contains(reply.status)) return RemoteOutcome::Refused;
    if (error.isEmpty()) error = "Remote deletion was not confirmed";
    return RemoteOutcome::Uncertain;
}
}
