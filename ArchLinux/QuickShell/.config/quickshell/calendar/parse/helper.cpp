#include "helper.h"
#include <QFileDevice>
#include <QSaveFile>
#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <iomanip>
#include <sstream>
#include <string>

#include <libical/ical.h>

// -------------------------------------------------------------------------------------- //
// Format converted timestamps and local calendar dates
// -------------------------------------------------------------------------------------- //
namespace {
bool equalsIgnoreCase(std::string_view actual, std::string_view expected) {
    return actual.size() == expected.size() && std::equal(actual.begin(), actual.end(), expected.begin(),
                                                          [](unsigned char left, unsigned char right) {
                                                              return std::toupper(left) == std::toupper(right);
                                                          });
}

std::string utcString(std::time_t value) {
    std::tm utc{};
    if (gmtime_r(&value, &utc) == nullptr)
        return {};

    std::ostringstream output;
    output << std::setfill('0')
           << std::setw(4) << utc.tm_year + 1900 << '-'
           << std::setw(2) << utc.tm_mon + 1 << '-'
           << std::setw(2) << utc.tm_mday << 'T'
           << std::setw(2) << utc.tm_hour << ':'
           << std::setw(2) << utc.tm_min << ':'
           << std::setw(2) << utc.tm_sec << 'Z';
    return output.str();
}

std::string dateString(const icaltimetype &value) {
    std::ostringstream output;
    output << std::setfill('0')
           << std::setw(4) << value.year << '-'
           << std::setw(2) << value.month << '-'
           << std::setw(2) << value.day;
    return output.str();
}

// -------------------------------------------------------------------------------------- //
// Read and decode text properties from one VEVENT
// -------------------------------------------------------------------------------------- //
std::string unescapeText(const char *value) {
    if (!value)
        return {};

    std::string result;
    for (size_t index = 0; value[index] != '\0'; ++index) {
        if (value[index] != '\\' || value[index + 1] == '\0') {
            result += value[index];
            continue;
        }
        const char escaped = value[++index];
        if (escaped == 'n' || escaped == 'N')
            result += '\n';
        else
            result += escaped;
    }
    return result;
}

std::string propertyText(icalcomponent *component, icalproperty_kind kind) {
    icalproperty *property = icalcomponent_get_first_property(component, kind);
    if (!property)
        return {};
    return unescapeText(icalproperty_get_value_as_string(property));
}

std::string escapeText(const std::string &value) {
    std::string result;
    result.reserve(value.size());
    for (const char character : value) {
        if (character == '\\' || character == ';' || character == ',')
            result += '\\';
        if (character == '\n')
            result += "\\n";
        else
            result += character;
    }
    return result;
}

std::string icalTime(const std::string &value, bool allDay) {
    if (allDay)
        return value.substr(0, 4) + value.substr(5, 2) + value.substr(8, 2);
    int year   = 0;
    int month  = 0;
    int day    = 0;
    int hour   = 0;
    int minute = 0;
    int second = 0;
    if (std::sscanf(value.c_str(), "%4d-%2d-%2dT%2d:%2d:%2d",
                    &year, &month, &day, &hour, &minute, &second) != 6)
        return {};

    std::tm local{};
    local.tm_year               = year - 1900;
    local.tm_mon                = month - 1;
    local.tm_mday               = day;
    local.tm_hour               = hour;
    local.tm_min                = minute;
    local.tm_sec                = second;
    std::time_t utc             = timegm(&local);
    const std::size_t zoneStart = value.find_first_of("Z+-", 19);
    if (zoneStart < value.size() && value[zoneStart] != 'Z') {
        int zoneHour   = 0;
        int zoneMinute = 0;
        if (std::sscanf(value.c_str() + zoneStart + 1, "%2d:%2d", &zoneHour, &zoneMinute) != 2)
            return {};
        const int offset = (zoneHour * 60 + zoneMinute) * 60;
        utc += value[zoneStart] == '+' ? -offset : offset;
    }

    std::tm normalized{};
    if (gmtime_r(&utc, &normalized) == nullptr)
        return {};
    char buffer[32]{};
    std::strftime(buffer, sizeof(buffer), "%Y%m%dT%H%M%SZ", &normalized);
    return buffer;
}

std::string currentUtc() {
    const std::time_t now = std::time(nullptr);
    std::tm utc{};
    if (gmtime_r(&now, &utc) == nullptr)
        return "19700101T000000Z";
    char buffer[32]{};
    std::strftime(buffer, sizeof(buffer), "%Y%m%dT%H%M%SZ", &utc);
    return buffer;
}

// -------------------------------------------------------------------------------------- //
// Convert one ICS date or date-time property into service format
// -------------------------------------------------------------------------------------- //
bool propertyTime(icalcomponent *calendar, icalcomponent *component, icalproperty_kind kind,
                  std::string &result, bool &allDay, std::string &error) {
    icalproperty *property = icalcomponent_get_first_property(component, kind);
    if (!property) {
        error = kind == ICAL_DTSTART_PROPERTY ? "VEVENT is missing DTSTART" : "VEVENT is missing DTEND";
        return false;
    }

    const icaltimetype value = kind == ICAL_DTSTART_PROPERTY
                                   ? icalproperty_get_dtstart(property)
                                   : icalproperty_get_dtend(property);
    if (!icaltime_is_valid_time(value)) {
        error = "VEVENT contains an invalid date-time";
        return false;
    }

    if (icaltime_is_date(value)) {
        result = dateString(value);
        allDay = true;
        return true;
    }

    const icalparameter *parameter =
        icalproperty_get_first_parameter(property, ICAL_TZID_PARAMETER);
    const char *tzid         = parameter ? icalparameter_get_tzid(parameter) : nullptr;
    const icaltimezone *zone = icaltimezone_get_utc_timezone();
    if (tzid && *tzid != '\0') {
        zone = icalcomponent_get_timezone(calendar, tzid);
        if (!zone)
            zone = icaltimezone_get_builtin_timezone(tzid);
        if (!zone) {
            error = std::string("unknown TZID: ") + tzid;
            return false;
        }
    } else if (!icaltime_is_utc(value)) {
        std::tm local{};
        local.tm_year               = value.year - 1900;
        local.tm_mon                = value.month - 1;
        local.tm_mday               = value.day;
        local.tm_hour               = value.hour;
        local.tm_min                = value.minute;
        local.tm_sec                = value.second;
        local.tm_isdst              = -1;
        const std::time_t timestamp = std::mktime(&local);
        if (timestamp == static_cast<std::time_t>(-1)) {
            error = "could not convert floating date-time";
            return false;
        }
        result = utcString(timestamp);
        allDay = false;
        return !result.empty();
    }

    result = utcString(icaltime_as_timet_with_zone(value, zone));
    allDay = false;
    if (result.empty())
        error = "could not convert date-time to UTC";
    return !result.empty();
}

} // namespace

// -------------------------------------------------------------------------------------- //
// Parse VCALENDAR input into independent event records
// -------------------------------------------------------------------------------------- //
ParseResult parseCalendar(std::string_view source) {
    ParseResult result;
    const std::string input(source);
    icalcomponent *calendar = icalparser_parse_string(input.c_str());
    if (!calendar) {
        result.error = "could not parse iCalendar data";
        return result;
    }

    if (icalcomponent_isa(calendar) != ICAL_VCALENDAR_COMPONENT) {
        result.error = "root component is not VCALENDAR";
        icalcomponent_free(calendar);
        return result;
    }

    for (icalcomponent *component = icalcomponent_get_first_component(
             calendar, ICAL_VEVENT_COMPONENT);
         component;
         component = icalcomponent_get_next_component(
             calendar, ICAL_VEVENT_COMPONENT)) {
        Event event;
        const std::string uid = propertyText(component, ICAL_UID_PROPERTY);
        if (uid.empty()) {
            result.error = "VEVENT is missing UID";
            result.events.clear();
            icalcomponent_free(calendar);
            return result;
        }
        event.uid = uid;

        if (const std::string summary = propertyText(component, ICAL_SUMMARY_PROPERTY);
            !summary.empty())
            event.summary = summary;
        if (const std::string description = propertyText(component, ICAL_DESCRIPTION_PROPERTY);
            !description.empty())
            event.description = description;
        if (const std::string location = propertyText(component, ICAL_LOCATION_PROPERTY);
            !location.empty())
            event.location = location;

        bool startAllDay = false;
        bool endAllDay   = false;
        if (!propertyTime(calendar, component, ICAL_DTSTART_PROPERTY, event.startTime,
                          startAllDay, result.error) ||
            !propertyTime(calendar, component, ICAL_DTEND_PROPERTY, event.endTime,
                          endAllDay, result.error)) {
            result.events.clear();
            icalcomponent_free(calendar);
            return result;
        }
        if (startAllDay && endAllDay && event.endTime == event.startTime) {
            icaltimetype endDate = icaltime_from_string(event.endTime.c_str());
            icaltime_adjust(&endDate, 1, 0, 0, 0);
            event.endTime = dateString(endDate);
        }
        if (startAllDay != endAllDay || event.endTime <= event.startTime) {
            result.error = "VEVENT has an invalid time range";
            result.events.clear();
            icalcomponent_free(calendar);
            return result;
        }
        event.allDay = startAllDay;
        for (icalcomponent *alarm = icalcomponent_get_first_component(
                 component, ICAL_VALARM_COMPONENT);
             alarm;
             alarm = icalcomponent_get_next_component(component, ICAL_VALARM_COMPONENT)) {
            if (propertyText(alarm, ICAL_ACTION_PROPERTY) != "DISPLAY")
                continue;
            icalproperty *trigger = icalcomponent_get_first_property(alarm, ICAL_TRIGGER_PROPERTY);
            if (!trigger)
                continue;
            const icaltriggertype value = icalproperty_get_trigger(trigger);
            const int seconds           = icaldurationtype_as_seconds(value.duration);
            if (seconds < 0 && seconds % 60 == 0) {
                const int minutes = -seconds / 60;
                if (std::find(event.reminders.begin(), event.reminders.end(), minutes) == event.reminders.end())
                    event.reminders.push_back(minutes);
            }
        }
        result.events.push_back(std::move(event));
    }

    icalcomponent_free(calendar);
    return result;
}

std::string serializeEvent(const Event &event) {
    const std::string start = icalTime(event.startTime, event.allDay);
    const std::string end   = icalTime(event.endTime, event.allDay);
    std::string output      = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//QuickShell Calendar//EN\r\nBEGIN:VEVENT\r\n";
    output += "UID:" + escapeText(event.uid) + "\r\n";
    output += "DTSTAMP:" + currentUtc() + "\r\n";
    output += event.allDay ? "DTSTART;VALUE=DATE:" + start + "\r\n" : "DTSTART:" + start + "\r\n";
    output += event.allDay ? "DTEND;VALUE=DATE:" + end + "\r\n" : "DTEND:" + end + "\r\n";
    if (!event.summary.empty())
        output += "SUMMARY:" + escapeText(event.summary) + "\r\n";
    if (!event.description.empty())
        output += "DESCRIPTION:" + escapeText(event.description) + "\r\n";
    if (!event.location.empty())
        output += "LOCATION:" + escapeText(event.location) + "\r\n";
    for (const int minutes : event.reminders) {
        if (minutes < 0)
            continue;
        output += "BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:";
        output += escapeText(event.summary.empty() ? "Reminder" : event.summary);
        output += "\r\nTRIGGER:-PT" + std::to_string(minutes) + "M\r\nEND:VALARM\r\n";
    }
    output += "END:VEVENT\r\nEND:VCALENDAR\r\n";
    return output;
}

bool writeAtomicallyFile(const std::string &path, const std::string &contents, std::string &error) {
    const std::filesystem::path target(path);
    std::error_code filesystemError;
    if (!target.parent_path().empty()) {
        const bool created = std::filesystem::create_directories(target.parent_path(), filesystemError);
        if (filesystemError) {
            error = "could not create event directory: " + filesystemError.message();
            return false;
        }
        if (created) {
            std::filesystem::permissions(target.parent_path(), std::filesystem::perms::owner_all,
                                         std::filesystem::perm_options::replace, filesystemError);
            if (filesystemError) {
                error = "could not protect event directory: " + filesystemError.message();
                return false;
            }
        }
    }

    QSaveFile file(QString::fromStdString(path));
    file.setDirectWriteFallback(false);
    if (!file.open(QIODevice::WriteOnly)) {
        error = "could not open temporary event file: " + file.errorString().toStdString();
        return false;
    }
    if (!file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)) {
        error = "could not protect temporary event file: " + file.errorString().toStdString();
        file.cancelWriting();
        return false;
    }
    qint64 written           = 0;
    const qint64 contentSize = static_cast<qint64>(contents.size());
    while (written < contentSize) {
        const qint64 count = file.write(contents.data() + written, contentSize - written);
        if (count <= 0) {
            error = "could not write temporary event file: " + file.errorString().toStdString();
            file.cancelWriting();
            return false;
        }
        written += count;
    }
    if (!file.commit()) {
        error = "could not commit event file: " + file.errorString().toStdString();
        return false;
    }
    return true;
}

bool supportedDisplayAlarm(const std::vector<std::string> &alarm, const Event &event) {
    std::string action;
    std::string trigger;
    for (const std::string &line : alarm) {
        if (line.rfind("ACTION:", 0) == 0)
            action = line.substr(7);
        else if (line.rfind("TRIGGER:", 0) == 0)
            trigger = line.substr(8);
    }
    if (action != "DISPLAY" || trigger.rfind("-PT", 0) != 0 || trigger.back() != 'M')
        return false;
    try {
        const int minutes = std::stoi(trigger.substr(3, trigger.size() - 4));
        return std::find(event.reminders.begin(), event.reminders.end(), minutes) != event.reminders.end();
    } catch (...) {
        return false;
    }
}

std::string preservedProperties(const std::string &source, const Event &event) {
    std::istringstream input(source);
    std::string line;
    std::string result;
    bool inEvent            = false;
    bool inAlarm            = false;
    bool skipFoldedProperty = false;
    std::vector<std::string> alarm;
    while (std::getline(input, line)) {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        if (equalsIgnoreCase(line, "BEGIN:VEVENT")) {
            inEvent = true;
            continue;
        }
        if (!inEvent)
            continue;
        if (equalsIgnoreCase(line, "BEGIN:VALARM")) {
            inAlarm = true;
            alarm   = {line};
            continue;
        }
        if (inAlarm) {
            alarm.push_back(line);
            if (equalsIgnoreCase(line, "END:VALARM")) {
                if (!supportedDisplayAlarm(alarm, event)) {
                    for (const std::string &alarmLine : alarm)
                        result += alarmLine + "\r\n";
                }
                inAlarm = false;
                alarm.clear();
            }
            continue;
        }
        if (!line.empty() && (line.front() == ' ' || line.front() == '\t')) {
            if (!skipFoldedProperty)
                result += line + "\r\n";
            continue;
        }
        if (equalsIgnoreCase(line, "END:VEVENT"))
            break;
        const std::size_t separator = line.find_first_of(":;");
        std::string propertyName    = line.substr(0, separator);
        if (const std::size_t group = propertyName.rfind('.'); group != std::string::npos)
            propertyName.erase(0, group + 1);
        std::transform(propertyName.begin(), propertyName.end(), propertyName.begin(),
                       [](unsigned char character) { return static_cast<char>(std::toupper(character)); });
        skipFoldedProperty = propertyName == "UID" || propertyName == "DTSTAMP" || propertyName == "DTSTART" || propertyName == "DTEND" || propertyName == "SUMMARY" || propertyName == "DESCRIPTION" || propertyName == "LOCATION";
        if (skipFoldedProperty)
            continue;
        result += line + "\r\n";
    }
    return result;
}

bool writeEventFile(const std::string &path, const Event &event, std::string &error) {
    return writeAtomicallyFile(path, serializeEvent(event), error);
}

bool writeEventFilePreserving(const std::string &path, const Event &event,
                              const std::string &existing, std::string &error) {
    const auto findLine = [&existing](std::string_view line, std::size_t from) {
        std::size_t position = from;
        while (position < existing.size()) {
            if (position + line.size() <= existing.size() && equalsIgnoreCase(std::string_view(existing).substr(position, line.size()), line) && (position + line.size() == existing.size() || existing[position + line.size()] == '\r' || existing[position + line.size()] == '\n'))
                return position;
            const std::size_t nextLine = existing.find('\n', position);
            position                   = nextLine == std::string::npos ? existing.size() : nextLine + 1;
        }
        return std::string::npos;
    };
    const std::size_t originalStart = findLine("BEGIN:VEVENT", 0);
    const std::size_t originalEnd   = originalStart == std::string::npos
                                          ? std::string::npos
                                          : findLine("END:VEVENT", originalStart);
    if (originalEnd == std::string::npos) {
        error = "could not locate original VEVENT";
        return false;
    }
    const std::size_t nextLine     = existing.find('\n', originalEnd);
    const std::size_t originalTail = nextLine == std::string::npos ? existing.size() : nextLine + 1;
    std::string serialized         = serializeEvent(event);
    const std::size_t eventStart   = serialized.find("BEGIN:VEVENT\r\n");
    const std::size_t eventEnd     = serialized.find("END:VEVENT\r\n", eventStart);
    if (eventStart == std::string::npos || eventEnd == std::string::npos) {
        error = "could not serialize VEVENT";
        return false;
    }
    std::string eventBlock = serialized.substr(eventStart,
                                               eventEnd + std::string("END:VEVENT\r\n").size() - eventStart);
    eventBlock.insert(eventEnd - eventStart, preservedProperties(existing, event));
    const std::string result = existing.substr(0, originalStart) + eventBlock + existing.substr(originalTail);
    return writeAtomicallyFile(path, result, error);
}
