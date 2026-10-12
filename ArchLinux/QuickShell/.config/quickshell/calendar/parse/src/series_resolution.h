#pragma once
#include <QStringList>
#include <string>

// Broker owns global serialization and pauses sync. All commands independently
// lock conflict state; source operations also own the calendar directory lock.
bool runSeriesResolution(const QString &command, const QStringList &arguments,
                         std::string &error, bool &sourceCommitted);
