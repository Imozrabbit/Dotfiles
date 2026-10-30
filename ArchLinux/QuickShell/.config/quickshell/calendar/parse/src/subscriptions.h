#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QMap>
#include <QStringList>

namespace SubscriptionBackend {
struct Record {
    QString id;
    QString url;
    int interval = 600;
    QString pair() const { return "qs_subscription_" + id; }
};
struct Paths {
    QString config, data, state, units, helper, converter, broker, lock, status;
};
struct Config {
    QByteArray original, prefix, suffix;
    QList<Record> records;
};
struct Lease {
    int descriptor = -1;
    ~Lease();
    bool acquire(const Paths &location, QString &error, bool wait = false);
    bool inherit(const Paths &location, QString &error);
};
Paths paths();
bool validId(const QString &id);
bool validateRecord(Record &record, QString &error);
bool readFile(const QString &path, QByteArray &data, QString &error, bool optional = false, qint64 limit = 1024 * 1024);
bool writeFile(const QString &path, const QByteArray &data, QString &error, bool createOnly = false, bool *published = nullptr);
bool ensureDirectory(const QString &path, QString &error);
bool loadConfig(const Paths &location, Config &config, QString &error);
bool loadRegistry(const Paths &location, QJsonObject &registry, QString &error);
bool validProfile(const QJsonObject &profile);
QByteArray renderConfig(const Paths &location, const Config &config, const QList<Record> &records);
QString revision(const QByteArray &data);
QJsonObject recordJson(const Paths &location, const Record &record);
bool command(const QString &program, const QStringList &arguments, int timeout = 90000, bool conflictSnapshots = false);
bool jsonFile(const QString &path, QJsonObject &object, QString &error, bool optional = true, qint64 limit = 1024 * 1024);
bool settings(const Paths &location, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error);
bool remove(const Paths &location, const QJsonObject &request, QJsonObject &result, QString &error);
bool removeLocal(const Paths &location, const QJsonObject &request, QJsonObject &result, QString &error);
bool importLocal(const Paths &location, const QJsonObject &request, QJsonObject &result, QString &error);
bool readImported(const Paths &location, const QJsonObject &request, QJsonObject &result, QString &error);
QMap<QString, QByteArray> unitDefinitions(const Paths &location, const Config &config);
bool installUnits(const Paths &location, const Config &config, QString &error, bool checkOnly = false);
bool cache(const Paths &location, const Config &config, QString &error);
QStringList unitFiles(const Config &config);
QStringList unitNames(const Config &config);
int deploymentPlan(bool verifyEffective);
int run(const QStringList &arguments);
} // namespace SubscriptionBackend
