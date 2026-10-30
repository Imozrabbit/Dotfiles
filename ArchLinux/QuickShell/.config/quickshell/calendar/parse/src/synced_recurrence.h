#pragma once
#include <QJsonObject>
#include <string>

struct Event;
std::string serializeSyncedRecurrence(const Event &event, const std::string &plain);
void restoreSyncedRecurrence(Event &event);
std::string mergeRecurrenceTimezones(const std::string &source, const std::string &generated);
std::string recurrenceSourceSignature(const std::string &source);
bool syncedEventFromJson(const QJsonObject &input, Event &event, std::string &error);
