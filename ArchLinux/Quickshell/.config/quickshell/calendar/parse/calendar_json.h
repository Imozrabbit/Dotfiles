#pragma once

#include "helper.h"
#include <string>
#include <vector>

std::string serializeCalendar(std::vector<Event> events, const std::string &sourceId);
std::string serializeSyncedCalendar(std::vector<Event> events, const std::string &sourceId,
                                    const std::vector<std::string> &warnings = {});
std::string eventRevision(const Event &event);
