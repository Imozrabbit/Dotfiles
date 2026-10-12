#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <string>

// Pure conflict snapshot codec. No filesystem or remote access.
bool seriesConflictIdentity(const std::string &source, QString &uid, bool &tagged, QString &error);
bool buildSeriesConflict(const QString &uid, const QJsonArray &pairs, QJsonObject &result, QString &error);
bool validateSeriesConflict(const QJsonObject &record, QString &error);
