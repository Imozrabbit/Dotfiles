#pragma once

#include "caldav.h"

namespace CalDavBackend {
struct RemoteSnapshot {
    QString homeHref;
    QMap<QString, QByteArray> resources;
    QString fingerprint;
};
enum class RemoteOutcome { Succeeded, Refused, Uncertain };
enum class RemotePresence { Present, Absent, Unknown };
enum class RemoteAvailability { Available, Deleted, Unavailable, Error };
RemoteAvailability remoteAvailability(const Record &target, QString &error);
bool validRemoteName(const QString &displayName);
bool discoverRemote(Record &connection, QString &homeHref, QJsonArray &calendars, QString &error);
bool snapshotRemote(const Record &target, RemoteSnapshot &snapshot, QString &error);
RemotePresence inspectRemote(const Record &target, const QString &homeHref, RemoteSnapshot &snapshot, QString &error);
RemoteOutcome createRemoteCollection(Record &target, const QString &homeHref, const QString &displayName,
                                     const QString &identifier, QString &error);
RemoteOutcome deleteRemoteCollection(const Record &target, const QString &homeHref, QString &error, bool *conservative = nullptr);
bool createRemoteAndAdd(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error);
bool buildRemoteReview(const Record &target, const QMap<QString, QByteArray> &localSources,
                       const RemoteSnapshot &remote, QJsonObject &payload, QJsonArray &conflicts, QString &error);
bool projectRemoteReview(const QString &id, const QJsonObject &payload, const QJsonArray &choices,
                          QJsonObject &local, QString &error);
bool projectRemoteSources(const QString &id, const QJsonObject &payload, const QJsonArray &choices,
                          QMap<QString, QByteArray> &sources, QString &error);
bool remoteDeletion(const Paths &p, const QString &action, const QJsonObject &request, QJsonObject &result, QString &error);
bool readRemoteDeletion(const Paths &p, const QString &id, QJsonObject &record, QString &error);
bool remoteDeletionAllowed(const Paths &p, const QString &id, QString &error);
bool saveRemoteDeletion(const Paths &p, const QJsonObject &record, QString &error);
bool preflightRemoteRetirement(const Paths &p, const QJsonObject &operation, QString &error);
bool finishRemoteRetirement(const Paths &p, QJsonObject &operation, QJsonObject &result, QString &error);
// Streaming fingerprint unless bytes is requested; all callers hold lifecycle lease.
bool remoteFileStamp(const QString &path, QJsonObject &info, QString &error, QByteArray *bytes = nullptr, qint64 limit = 0);
}
