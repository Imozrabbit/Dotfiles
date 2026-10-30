#pragma once
#include <QJsonObject>
#include <QString>
#include <map>
#include <optional>
#include <string>
#include <vector>
struct Event;

struct SeriesFileChange {
    std::string uid;
    std::optional<std::string> before;
    std::optional<std::string> after;
    std::string filename{}; // Existing ordinary remote resource; empty means canonical UID hash.
};

// Caller must hold the existing calendar directory lock and pause sync before
// using these primitives. No remote or cross-file atomicity is promised.
bool commitSeriesFiles(const std::string &directory, const std::vector<SeriesFileChange> &changes,
                       QString &error, bool &sourceCommitted);
// Same paused-sync/lock contract. Deferred replacements are performed by pimsync;
// journal remains prepared until every expected replacement is verified durable.
bool prepareSeriesFiles(const std::string &directory, const std::vector<SeriesFileChange> &changes, QString &error);
bool checkPreparedSeriesFiles(const std::string &directory, QString &error);
bool finishSeriesFiles(const std::string &directory, QString &error, bool &sourceCommitted);
bool recoverSeriesGroups(const std::string &directory, QString &error);
bool buildSeriesGroup(const QJsonObject &master, QJsonObject &result, QString &error);
bool inspectSeriesGroup(const std::string &directory, const QString &uid,
                        QJsonObject &result, QString &error);
bool mutateSeriesGroup(const std::string &directory, const std::string &output,
                       const QJsonObject &request, QString &error, bool &sourceCommitted);
// Pure cache reconstruction; no member paths read or sources repaired.
void reconstructSeriesGroups(std::vector<Event> &events, std::vector<std::string> &warnings);
// Caller pauses sync. Owns calendar lock; sourcesSafe permits resume even if cache fails.
bool recoverSeriesCache(const std::string &directory, const std::string &output,
                        const QString &sourceId, QString &error, bool &sourcesSafe, const QString &uid = {});
// Read-only argument preflight, before broker installs a durable recovery guard.
bool checkSeriesTarget(const std::string &directory, const std::string &output,
                       const QString &sourceId, QString &error);
// Pure snapshot validation; identical rules to source/cache reconstruction.
bool inspectSeriesSources(const std::map<std::string, std::string> &sources, const QString &uid,
                          QJsonObject &result, QString &error);
QString seriesSourceGroup(const Event &event, bool &tagged, bool &ambiguous);
