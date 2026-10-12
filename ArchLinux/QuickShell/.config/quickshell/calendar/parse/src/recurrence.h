#pragma once
#include <QJsonObject>
#include <QString>

bool validateRecurrenceMaster(const QJsonObject &master, QString &error);
// Group members reuse the logical master's elapsed duration, not a new end clock.
bool normalizeRecurrenceMaster(const QJsonObject &master, QJsonObject &result, QString &error,
                               bool preserveElapsedDuration = false);
bool expandCalendarRange(const QJsonObject &request, QJsonObject &result, QString &error);
