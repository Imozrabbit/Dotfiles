#pragma once

#include "subscriptions.h"
#include <QJsonArray>

namespace CalDavBackend {
using SubscriptionBackend::Paths;
struct Record {
    QString id, url, username, passwordFile, remoteId, remoteHref;
    int interval = 300;
    QString pair() const { return "qs_caldav_" + id; }
};
struct Config {
    QByteArray original, prefix, suffix;
    QList<Record> records;
};
Paths paths();
QString quoted(QString value);
bool validateConnection(Record &record, QString &error);
bool discover(Record record, QJsonArray &calendars, QString &error);
bool loadConfig(const Paths &p, Config &config, QString &error);
QByteArray renderConfig(const Paths &p, const Config &config, const QList<Record> &records);
QByteArray renderReadOnlyConfig(const Paths &p, const Record &record);
QJsonObject recordJson(const Record &record);
QString remoteIdentity(const Record &record);
Record recordFromJson(const QJsonObject &object);
bool validIdentity(const Record &record);
QMap<QString, QByteArray> unitDefinitions(const Paths &p, const Config &config);
bool pauseDaemon(bool &wasActive, QString &error);
bool resumeDaemon(bool wasActive, QString &error);
bool syncRecord(const Paths &p, const Record &record, QString &error, bool initial = false, QByteArray *publishedCache = nullptr);
bool syncAttachmentRecord(const Paths &p, const Record &record, const QString &session, bool &started, QString &error);
bool verifyManagedDaemon(const Paths &p, QString &error);
bool synchronize(const Paths &p, const QString &id, QJsonObject &result, QString &error);
QString availabilityTarget(const Record &record);
bool unavailableStatus(const Paths &p, const Record &record, QJsonObject &status, QString &error);
bool remoteSyncAllowed(const Paths &p, const QString &id, QString &error);
bool checkRemoteForSync(const Paths &p, const Record &record, QString &error, bool recheck = false);
bool recheckRemote(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error);
bool settings(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error);
bool remove(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error);
bool conversion(const Paths &p, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error);
bool readConversionPause(const Paths &p, const QString &id, QJsonObject &pause, QString &error);
bool conversionAllowed(const Paths &p, const QString &id, QString &error);
bool attachment(const Paths &p, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error);
bool readAttachment(const Paths &p, const QString &id, QJsonObject &record, QString &error);
bool attachmentAllowed(const Paths &p, const QString &id, QString &error);
bool attachmentOwnsSync(const Paths &p, const Record &record, const QString &session, QString &error);
bool makeLocalDocument(const QString &id, const QJsonArray &events, QJsonObject &local, QString &error);
bool retireConverted(const Paths &p, const QJsonObject &request, const QString &localPath, QJsonObject &result, QString &error,
                     bool checkOnly = false, const QJsonObject &expectedSources = {});
int daemon(const Paths &p);
int run(const QStringList &arguments);
} // namespace CalDavBackend
