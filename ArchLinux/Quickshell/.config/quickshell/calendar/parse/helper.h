#pragma once
#include <string>
#include <string_view>
#include <vector>

struct Event {
    std::string uid;
    std::string summary;
    std::string description;
    std::string location;
    std::string startTime;
    std::string endTime;
    bool allDay = false;
    std::vector<int> reminders;
};

struct ParseResult {
    std::vector<Event> events;
    std::string error;
};

ParseResult parseCalendar(std::string_view source);
std::string serializeEvent(const Event &event);
bool writeEventFile(const std::string &path, const Event &event, std::string &error);
bool writeAtomicallyFile(const std::string &path, const std::string &contents, std::string &error);
bool writeEventFilePreserving(const std::string &path, const Event &event,
                              const std::string &existing, std::string &error);
