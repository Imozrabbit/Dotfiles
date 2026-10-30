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
    // Complete alarm snapshot for an editable, unambiguous all-day nominal-one-day reminder.
    std::string nominalOneDayAlarmRevision;
    // Per-UID source calendar for external recurrence/timezone fidelity.
    std::string ical;
    // Verified ordinary authored rule; retained ICS still participates in revision.
    std::string recurrence;
    std::string timezone;
    // Validated logical grouped cache metadata; never serialized as a single ICS.
    std::string seriesGroup;
    std::string groupRevision;
    bool readOnly = false;
};

struct ParseResult {
    std::vector<Event> events;
    std::string error;
};

ParseResult parseCalendar(std::string_view source);
struct icalcomponent_impl;
// Existing strict DISPLAY-alarm model, without editable nominal-day extensions.
std::vector<int> simpleDisplayReminders(icalcomponent_impl *event);
std::string serializeEvent(const Event &event);
bool writeEventFile(const std::string &path, const Event &event, std::string &error);
bool writeAtomicallyFile(const std::string &path, const std::string &contents, std::string &error);
bool writeEventFilePreserving(const std::string &path, const Event &event,
                              const std::string &existing, std::string &error);
// Pure merge only. Caller must validate ownership/stale state before committing.
bool mergeEventSource(const std::string &existing, const std::string &serialized,
                      std::string &result, std::string &error);
