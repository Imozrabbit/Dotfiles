#include "helper.h"
#include "synced_recurrence.h"
#include <QDateTime>
#include <QFileDevice>
#include <QFileInfo>
#include <QSaveFile>
#include <QString>
#include <QTimeZone>
#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <iomanip>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <string>

#include <libical/ical.h>

// -------------------------------------------------------------------------------------- //
// Format converted timestamps and local calendar dates
// -------------------------------------------------------------------------------------- //
namespace {
icalcomponent *cloneComponent(icalcomponent *component) {
#if ICAL_MAJOR_VERSION >= 4
    return icalcomponent_clone(component);
#else
    return icalcomponent_new_clone(component);
#endif
}

icalproperty *cloneProperty(icalproperty *property) {
#if ICAL_MAJOR_VERSION >= 4
    return icalproperty_clone(property);
#else
    return icalproperty_new_clone(property);
#endif
}

void referencedTimezones(icalcomponent *component, std::set<std::string> &zones) {
    std::vector<icalcomponent *> pending{component};
    while (!pending.empty()) {
        auto *current = pending.back();
        pending.pop_back();
        for (auto *property     = icalcomponent_get_first_property(current, ICAL_ANY_PROPERTY);
             property; property = icalcomponent_get_next_property(current, ICAL_ANY_PROPERTY)) {
            const auto *parameter = icalproperty_get_first_parameter(property, ICAL_TZID_PARAMETER);
            if (parameter && icalparameter_get_tzid(parameter))
                zones.insert(icalparameter_get_tzid(parameter));
        }
        for (auto *child  = icalcomponent_get_first_component(current, ICAL_ANY_COMPONENT);
             child; child = icalcomponent_get_next_component(current, ICAL_ANY_COMPONENT))
            pending.push_back(child);
    }
}

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
    icalproperty *property       = icalcomponent_get_first_property(component, kind);
    const auto *durationProperty = kind == ICAL_DTEND_PROPERTY
                                       ? icalcomponent_get_first_property(component, ICAL_DURATION_PROPERTY)
                                        : nullptr;
    if (property && durationProperty) {
        error = "VEVENT has both DTEND and DURATION";
        return false;
    }
    if (!property && kind != ICAL_DTEND_PROPERTY) {
        error = kind == ICAL_DTSTART_PROPERTY ? "VEVENT is missing DTSTART" : "VEVENT is missing RECURRENCE-ID";
        return false;
    }
    const bool implicitEnd = !property && !durationProperty;

    icaltimetype value    = !property ? icalcomponent_get_dtstart(component) : kind == ICAL_RECURRENCEID_PROPERTY ? icalproperty_get_recurrenceid(property)
                                                                             : kind == ICAL_DTSTART_PROPERTY ? icalproperty_get_dtstart(property)
                                                                                                             : icalproperty_get_dtend(property);
    qint64 elapsedSeconds = 0;
    if (implicitEnd && value.is_date)
        icaltime_adjust(&value, 1, 0, 0, 0);
    if (durationProperty) {
        const auto duration      = icalproperty_get_duration(durationProperty);
        const qint64 nominalDays = qint64(duration.weeks) * 7 + duration.days;
        elapsedSeconds           = qint64(duration.hours) * 3600 + qint64(duration.minutes) * 60 + duration.seconds;
        if (duration.is_neg || nominalDays > 3652058 || (value.is_date && elapsedSeconds)) {
            error = "VEVENT contains an invalid duration";
            return false;
        }
        icaltime_adjust(&value, int(nominalDays), 0, 0, 0);
    }
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
        icalproperty_get_first_parameter(property ? property : icalcomponent_get_first_property(component, ICAL_DTSTART_PROPERTY), ICAL_TZID_PARAMETER);
    const char *tzid = parameter ? icalparameter_get_tzid(parameter) : nullptr;
    if (icaltime_is_utc(value) && (!tzid || !*tzid)) {
        const QDateTime instant(QDate(value.year, value.month, value.day),
                                QTime(value.hour, value.minute, value.second), QTimeZone::utc());
        if (!instant.isValid()) {
            error = "invalid UTC date-time";
            return false;
        }
        result = instant.addSecs(elapsedSeconds).toUTC().toString(Qt::ISODate).toStdString();
        allDay = false;
        return true;
    }
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
        result = utcString(timestamp + elapsedSeconds);
        allDay = false;
        return !result.empty();
    }

    result = utcString(icaltime_as_timet_with_zone(value, zone) + elapsedSeconds);
    allDay = false;
    if (result.empty())
        error = "could not convert date-time to UTC";
    return !result.empty();
}

bool eventRange(icalcomponent *calendar, icalcomponent *component, Event &event, std::string &error) {
    bool startAllDay = false, endAllDay = false;
    if (!propertyTime(calendar, component, ICAL_DTSTART_PROPERTY, event.startTime, startAllDay, error)
        || !propertyTime(calendar, component, ICAL_DTEND_PROPERTY, event.endTime, endAllDay, error)) return false;
    if (startAllDay && endAllDay && event.endTime == event.startTime) {
        icaltimetype endDate = icaltime_from_string(event.endTime.c_str());
        icaltime_adjust(&endDate, 1, 0, 0, 0);
        event.endTime = dateString(endDate);
    }
    const bool implicitEnd = !icalcomponent_get_first_property(component, ICAL_DTEND_PROPERTY)
                             && !icalcomponent_get_first_property(component, ICAL_DURATION_PROPERTY);
    if (startAllDay != endAllDay || event.endTime < event.startTime
        || (event.endTime == event.startTime && !implicitEnd)) {
        error = "VEVENT has an invalid time range"; return false;
    }
    event.allDay = startAllDay;
    return true;
}

// Only the simple reminder model is managed. Rich/parameterized alarms stay
// opaque and must not be regenerated or duplicated by the editor.
bool utcReminderStart(icalcomponent *event) {
    if (!event || icalcomponent_count_properties(event, ICAL_DTSTART_PROPERTY) != 1)
        return false;
    auto *start = icalcomponent_get_first_property(event, ICAL_DTSTART_PROPERTY);
    return icaltime_is_utc(icalproperty_get_dtstart(start)) && !icalproperty_get_first_parameter(start, ICAL_TZID_PARAMETER);
}

bool hasOneDayTrigger(icalcomponent *alarm) {
    for (auto *trigger = icalcomponent_get_first_property(alarm, ICAL_TRIGGER_PROPERTY); trigger;
         trigger = icalcomponent_get_next_property(alarm, ICAL_TRIGGER_PROPERTY)) {
        const auto value = icalproperty_get_trigger(trigger);
        const auto &duration = value.duration;
        const qint64 seconds = (qint64(duration.weeks) * 7 + duration.days) * 86400
            + qint64(duration.hours) * 3600 + qint64(duration.minutes) * 60 + duration.seconds;
        if (icaltime_is_null_time(value.time) && duration.is_neg && seconds == 86400) return true;
    }
    return false;
}

int supportedReminderMinutes(icalcomponent *alarm, bool utcStart, bool allowNominalOneDay = false) {
    if (!alarm || icalcomponent_isa(alarm) != ICAL_VALARM_COMPONENT || icalcomponent_get_first_component(alarm, ICAL_ANY_COMPONENT))
        return -1;
    std::set<icalproperty_kind> seen;
    for (auto *property = icalcomponent_get_first_property(alarm, ICAL_ANY_PROPERTY); property;
         property       = icalcomponent_get_next_property(alarm, ICAL_ANY_PROPERTY)) {
        const auto kind = icalproperty_isa(property);
        if ((kind != ICAL_ACTION_PROPERTY && kind != ICAL_TRIGGER_PROPERTY && kind != ICAL_DESCRIPTION_PROPERTY) || !seen.insert(kind).second || icalproperty_get_first_parameter(property, ICAL_ANY_PARAMETER))
            return -1;
    }
    if (propertyText(alarm, ICAL_ACTION_PROPERTY) != "DISPLAY")
        return -1;
    auto *trigger = icalcomponent_get_first_property(alarm, ICAL_TRIGGER_PROPERTY);
    if (!trigger)
        return -1;
    const auto value = icalproperty_get_trigger(trigger);
    // Only explicit UTC starts make civil days/weeks exact elapsed minutes.
    if ((value.duration.days != 0 || value.duration.weeks != 0) && !utcStart) {
        // ponytail: model only a single unambiguous all-day -P1D; richer civil offsets need a typed reminder schema.
        if (!allowNominalOneDay || !value.duration.is_neg || value.duration.days != 1 || value.duration.weeks != 0
            || value.duration.hours != 0 || value.duration.minutes != 0 || value.duration.seconds != 0)
            return -1;
    }
    const qint64 seconds = (qint64(value.duration.weeks) * 7 + value.duration.days) * 86400
        + qint64(value.duration.hours) * 3600 + qint64(value.duration.minutes) * 60 + value.duration.seconds;
    return icaltime_is_null_time(value.time) && seconds >= 0 && (value.duration.is_neg || seconds == 0)
        && seconds % 60 == 0 && seconds / 60 <= std::numeric_limits<int>::max() ? int(seconds / 60) : -1;
}

} // namespace

std::vector<int> simpleDisplayReminders(icalcomponent *event) {
    std::vector<int> result;
    const bool utcStart = utcReminderStart(event);
    for (auto *alarm = icalcomponent_get_first_component(event, ICAL_VALARM_COMPONENT); alarm;
         alarm = icalcomponent_get_next_component(event, ICAL_VALARM_COMPONENT)) {
        const int minutes = supportedReminderMinutes(alarm, utcStart);
        if (minutes >= 0 && std::find(result.begin(), result.end(), minutes) == result.end())
            result.push_back(minutes);
    }
    return result;
}

// -------------------------------------------------------------------------------------- //
// Parse VCALENDAR input into independent event records
// -------------------------------------------------------------------------------------- //
ParseResult parseCalendar(std::string_view source) {
    ParseResult result;
    if (source.size() > 16 * 1024 * 1024 || source.find('\0') != std::string_view::npos) {
        result.error = "iCalendar input exceeds size limit or contains NUL";
        return result;
    }
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
    if (icalcomponent_count_errors(calendar)) {
        result.error = "invalid iCalendar syntax";
        icalcomponent_free(calendar);
        return result;
    }

    std::map<std::string, std::vector<icalcomponent *>> series;
    std::vector<icalcomponent *> components;
    for (icalcomponent *component = icalcomponent_get_first_component(
             calendar, ICAL_VEVENT_COMPONENT);
         component;
         component = icalcomponent_get_next_component(calendar, ICAL_VEVENT_COMPONENT)) {
        const std::string uid = propertyText(component, ICAL_UID_PROPERTY);
        if (uid.empty()) {
            result.error = "VEVENT is missing UID";
            icalcomponent_free(calendar);
            return result;
        }
        if (icalcomponent_get_first_property(component, ICAL_RECURRENCEID_PROPERTY)
            && icalcomponent_get_status(component) != ICAL_STATUS_CANCELLED) {
            Event override;
            if (!eventRange(calendar, component, override, result.error)) {
                icalcomponent_free(calendar); return result;
            }
        }
        series[uid].push_back(component);
        components.push_back(component);
    }
    for (const auto &[uid, members] : series) {
        (void)uid;
        icalcomponent *master = nullptr;
        for (auto *member : members)
            if (!icalcomponent_get_first_property(member, ICAL_RECURRENCEID_PROPERTY)) master = member;
        if (!master) continue; // Missing masters are rejected below.
        const bool allDay = icalcomponent_get_dtstart(master).is_date;
        std::set<std::string> identities;
        for (auto *member : members) {
            if (!icalcomponent_get_first_property(member, ICAL_RECURRENCEID_PROPERTY)) continue;
            std::string identity;
            bool dateOnly = false;
            if (!propertyTime(calendar, member, ICAL_RECURRENCEID_PROPERTY, identity, dateOnly, result.error)) {
                icalcomponent_free(calendar); return result;
            }
            if (dateOnly != allDay || !identities.insert(identity).second
                || icalcomponent_count_properties(member, ICAL_RECURRENCEID_PROPERTY) != 1
                || (icalcomponent_get_first_property(member, ICAL_DTSTART_PROPERTY)
                    && bool(icalcomponent_get_dtstart(member).is_date) != allDay)) {
                result.error = "invalid or duplicate recurrence override";
                icalcomponent_free(calendar); return result;
            }
        }
    }
    std::set<std::string> retained;
    size_t retainedBytes = 0;
    // libical's component iteration cursor is shared with timezone lookup.
    for (auto *component : components) {
        Event event;
        const std::string uid = propertyText(component, ICAL_UID_PROPERTY);
        if (uid.empty()) {
            result.error = "VEVENT is missing UID";
            result.events.clear();
            icalcomponent_free(calendar);
            return result;
        }
        if (icalcomponent_get_first_property(component, ICAL_RECURRENCEID_PROPERTY))
            continue;
        if (!retained.insert(uid).second) {
            result.error = "duplicate master UID: " + uid;
            result.events.clear();
            icalcomponent_free(calendar);
            return result;
        }
        event.uid = uid;

        bool extended = series[uid].size() > 1;
        int timezoneHints = 0;
        std::string oneoffTimezone;
        bool timezoneParameters = false;
        for (const auto kind : {ICAL_RRULE_PROPERTY, ICAL_RDATE_PROPERTY, ICAL_EXDATE_PROPERTY, ICAL_EXRULE_PROPERTY})
            extended = extended || icalcomponent_get_first_property(component, kind);
        for (auto *property = icalcomponent_get_first_property(component, ICAL_X_PROPERTY); property;
             property       = icalcomponent_get_next_property(component, ICAL_X_PROPERTY)) {
            const auto name = QString::fromUtf8(icalproperty_get_x_name(property));
            if (name.compare("X-QUICKSHELL-TIMEZONE", Qt::CaseInsensitive) == 0) {
                ++timezoneHints;
                const auto *value = icalproperty_get_x(property);
                oneoffTimezone = value ? value : "";
                timezoneParameters = timezoneParameters || icalproperty_get_first_parameter(property, ICAL_ANY_PARAMETER);
            }
            extended        = extended || name.compare("X-QUICKSHELL-RECURRENCE", Qt::CaseInsensitive) == 0 || name.startsWith("X-QUICKSHELL-GROUP-", Qt::CaseInsensitive);
        }
        const bool oneoffZone = timezoneHints == 1 && !extended && !timezoneParameters && !oneoffTimezone.empty()
            && !icalcomponent_get_dtstart(component).is_date && QTimeZone(QByteArray::fromStdString(oneoffTimezone)).isValid();
        if (timezoneHints && !oneoffZone) extended = true; // Retain ambiguous/invalid metadata read-only.
        if (oneoffZone) event.timezone = oneoffTimezone;
        if (extended) {
            icalcomponent *single = icalcomponent_new_vcalendar();
            for (icalproperty *property = icalcomponent_get_first_property(calendar, ICAL_ANY_PROPERTY);
                 property; property     = icalcomponent_get_next_property(calendar, ICAL_ANY_PROPERTY))
                icalcomponent_add_property(single, cloneProperty(property));
            std::set<std::string> zones;
            for (auto *member : series[uid]) {
                icalcomponent_add_component(single, cloneComponent(member));
                referencedTimezones(member, zones);
            }
            for (auto *definition       = icalcomponent_get_first_component(calendar, ICAL_VTIMEZONE_COMPONENT);
                 definition; definition = icalcomponent_get_next_component(calendar, ICAL_VTIMEZONE_COMPONENT)) {
                if (zones.count(propertyText(definition, ICAL_TZID_PROPERTY)))
                    icalcomponent_add_component(single, cloneComponent(definition));
            }
            char *text = icalcomponent_as_ical_string_r(single);
            if (text) {
                event.ical = text;
                icalmemory_free_buffer(text);
            }
            icalcomponent_free(single);
            retainedBytes += event.ical.size();
            if (event.ical.empty() || retainedBytes > 32 * 1024 * 1024) {
                result.error = "retained iCalendar data exceeds output limit";
                result.events.clear();
                icalcomponent_free(calendar);
                return result;
            }
        }

        if (const std::string summary = propertyText(component, ICAL_SUMMARY_PROPERTY);
            !summary.empty())
            event.summary = summary;
        if (const std::string description = propertyText(component, ICAL_DESCRIPTION_PROPERTY);
            !description.empty())
            event.description = description;
        if (const std::string location = propertyText(component, ICAL_LOCATION_PROPERTY);
            !location.empty())
            event.location = location;

        if (!eventRange(calendar, component, event, result.error)) {
            result.events.clear();
            icalcomponent_free(calendar);
            return result;
        }
        const bool utcStart = utcReminderStart(component);
        auto *start = icalcomponent_get_first_property(component, ICAL_DTSTART_PROPERTY);
        const bool nominalCandidate = event.allDay && !extended && icalcomponent_count_properties(component, ICAL_DTSTART_PROPERTY) == 1
            && start && !icalproperty_get_first_parameter(start, ICAL_TZID_PARAMETER);
        int oneDayMatches = 0, nominalMatches = 0;
        if (nominalCandidate) {
            for (auto *alarm = icalcomponent_get_first_component(component, ICAL_VALARM_COMPONENT); alarm;
                 alarm = icalcomponent_get_next_component(component, ICAL_VALARM_COMPONENT)) {
                if (hasOneDayTrigger(alarm)) ++oneDayMatches;
                const int strict = supportedReminderMinutes(alarm, utcStart);
                const int extendedMinutes = supportedReminderMinutes(alarm, utcStart, true);
                if (strict < 0 && extendedMinutes == 1440) ++nominalMatches;
            }
        }
        const bool nominalOneDay = nominalCandidate && oneDayMatches == 1 && nominalMatches == 1;
        for (icalcomponent *alarm = icalcomponent_get_first_component(
                 component, ICAL_VALARM_COMPONENT);
             alarm;
             alarm = icalcomponent_get_next_component(component, ICAL_VALARM_COMPONENT)) {
            const int minutes = supportedReminderMinutes(alarm, utcStart, nominalOneDay);
            if (minutes >= 0) {
                if (std::find(event.reminders.begin(), event.reminders.end(), minutes) == event.reminders.end())
                    event.reminders.push_back(minutes);
            }
            if (nominalOneDay) {
                char *alarmText = icalcomponent_as_ical_string_r(alarm);
                if (!alarmText) {
                    result.error = "could not retain nominal alarm revision";
                    result.events.clear();
                    icalcomponent_free(calendar);
                    return result;
                }
                const std::string snapshot(alarmText);
                icalmemory_free_buffer(alarmText);
                event.nominalOneDayAlarmRevision += std::to_string(snapshot.size()) + ":" + snapshot;
            }
        }
        restoreSyncedRecurrence(event);
        result.events.push_back(std::move(event));
    }

    for (const auto &[uid, members] : series) {
        (void)members;
        if (!retained.count(uid)) {
            result.error = "recurrence overrides have no master: " + uid;
            result.events.clear();
            break;
        }
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
    // UTC keeps one-off instants unambiguous through DST folds; retain editor's zone separately.
    if (!event.allDay && event.recurrence.empty() && !event.timezone.empty())
        output += "X-QUICKSHELL-TIMEZONE:" + escapeText(event.timezone) + "\r\n";
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
    return serializeSyncedRecurrence(event, output);
}

bool writeAtomicallyFile(const std::string &path, const std::string &contents, std::string &error) {
    const std::filesystem::path target(path);
    const auto previousModified = target.extension() == ".ics" ? QFileInfo(QString::fromStdString(path)).lastModified() : QDateTime{};
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
    // Older pimsync vdir etags use whole mtime seconds. Keep source replacements
    // distinguishable across rapid saves and backwards wall-clock adjustments.
    // ponytail: mtime may lead clock by one second per rapid save; remove when
    // supported vdir etags use subsecond precision.
    if (previousModified.isValid()) {
        const auto second = std::max(QDateTime::currentDateTimeUtc().toSecsSinceEpoch(), previousModified.toSecsSinceEpoch() + 1);
        if (!file.flush() || !file.setFileTime(QDateTime::fromSecsSinceEpoch(second, QTimeZone::UTC), QFileDevice::FileModificationTime)) {
            error = "could not advance event modification time: " + file.errorString().toStdString();
            file.cancelWriting();
            return false;
        }
    }
    if (!file.commit()) {
        error = "could not commit event file: " + file.errorString().toStdString();
        return false;
    }
    return true;
}

bool supportedDisplayAlarm(const std::vector<std::string> &alarm, bool utcStart, bool allowNominalOneDay = false) {
    std::string source;
    for (const auto &line : alarm)
        source += line + "\r\n";
    auto *component      = icalparser_parse_string(source.c_str());
    const bool supported = supportedReminderMinutes(component, utcStart, allowNominalOneDay) >= 0;
    if (component)
        icalcomponent_free(component);
    return supported;
}

std::string preservedProperties(const std::string &source, bool extractNominalOneDay, std::string &nominalAlarm) {
    auto *calendar = icalparser_parse_string(source.c_str());
    const bool utcStart = calendar && utcReminderStart(icalcomponent_get_first_component(calendar, ICAL_VEVENT_COMPONENT));
    if (calendar)
        icalcomponent_free(calendar);
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
                if (!supportedDisplayAlarm(alarm, utcStart)) {
                    std::string &destination = extractNominalOneDay && supportedDisplayAlarm(alarm, utcStart, true) ? nominalAlarm : result;
                    for (const std::string &alarmLine : alarm)
                        destination += alarmLine + "\r\n";
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
        skipFoldedProperty = propertyName == "UID" || propertyName == "DTSTAMP" || propertyName == "DTSTART" || propertyName == "DTEND" || propertyName == "SUMMARY" || propertyName == "DESCRIPTION" || propertyName == "LOCATION" || propertyName == "DURATION" || propertyName == "RRULE" || propertyName == "RDATE" || propertyName == "EXDATE" || propertyName == "EXRULE" || propertyName == "RECURRENCE-ID" || propertyName == "X-QUICKSHELL-RECURRENCE" || propertyName == "X-QUICKSHELL-TIMEZONE" || propertyName == "X-QUICKSHELL-GROUP-ID" || propertyName == "X-QUICKSHELL-GROUP-RULE";
        if (skipFoldedProperty)
            continue;
        result += line + "\r\n";
    }
    return result;
}

bool writeEventFile(const std::string &path, const Event &event, std::string &error) {
    if (!event.ical.empty() && event.recurrence.empty()) {
        error = "external recurrence is read-only";
        return false;
    }
    const auto source = serializeEvent(event);
    if (source.empty()) {
        error = "could not serialize recurrence";
        return false;
    }
    return writeAtomicallyFile(path, source, error);
}

bool writeEventFilePreserving(const std::string &path, const Event &event,
                              const std::string &existing, std::string &error) {
    const auto parsed = parseCalendar(existing);
    if ((!event.ical.empty() && event.recurrence.empty()) || std::any_of(parsed.events.begin(), parsed.events.end(), [](const Event &source) { return !source.ical.empty() && source.recurrence.empty(); })) {
        error = "external recurrence is read-only";
        return false;
    }
    std::string result;
    return mergeEventSource(existing, serializeEvent(event), result, error) && writeAtomicallyFile(path, result, error);
}

bool mergeEventSource(const std::string &existing, const std::string &serialized,
                      std::string &result, std::string &error) {
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
    const std::size_t eventStart   = serialized.find("BEGIN:VEVENT\r\n");
    const std::size_t eventEnd     = serialized.find("END:VEVENT\r\n", eventStart);
    if (eventStart == std::string::npos || eventEnd == std::string::npos) {
        error = "could not serialize VEVENT";
        return false;
    }
    std::string eventBlock = serialized.substr(eventStart,
                                               eventEnd + std::string("END:VEVENT\r\n").size() - eventStart);
    const auto original = parseCalendar(existing);
    const bool hasNominalOneDay = original.error.empty() && original.events.size() == 1 && !original.events[0].nominalOneDayAlarmRevision.empty();
    std::string nominalAlarm;
    const auto preserved = preservedProperties(existing, hasNominalOneDay, nominalAlarm);
    if (hasNominalOneDay) {
        if (nominalAlarm.empty()) { error = "could not retain original nominal one-day alarm"; return false; }
        auto *target = icalparser_parse_string(serialized.c_str());
        auto *component = target ? icalcomponent_get_first_component(target, ICAL_VEVENT_COMPONENT) : nullptr;
        if (!component) {
            if (target) icalcomponent_free(target);
            error = "could not inspect replacement reminders";
            return false;
        }
        int oneDayAlarms = 0;
        for (auto *alarm = icalcomponent_get_first_component(component, ICAL_VALARM_COMPONENT); alarm;
             alarm = icalcomponent_get_next_component(component, ICAL_VALARM_COMPONENT))
            if (supportedReminderMinutes(alarm, true) == 1440) ++oneDayAlarms;
        icalcomponent_free(target);
        if (oneDayAlarms > 1) {
            error = "replacement one-day reminder is ambiguous";
            return false;
        }
        if (oneDayAlarms == 1) {
            const auto replacement = parseCalendar(serialized);
            if (!replacement.error.empty() || replacement.events.size() != 1 || !replacement.events[0].allDay
                || !replacement.events[0].recurrence.empty() || !replacement.events[0].ical.empty()) {
                error = "Remove the nominal one-day reminder before changing the event type or recurrence";
                return false;
            }
            const std::string trigger = "\r\nTRIGGER:-PT1440M\r\n";
            const auto triggerPos = eventBlock.find(trigger);
            const auto alarmStart = triggerPos == std::string::npos ? std::string::npos : eventBlock.rfind("BEGIN:VALARM\r\n", triggerPos);
            const auto alarmEnd = triggerPos == std::string::npos ? std::string::npos : eventBlock.find("END:VALARM\r\n", triggerPos);
            if (alarmStart == std::string::npos || alarmEnd == std::string::npos || eventBlock.find(trigger, triggerPos + trigger.size()) != std::string::npos) {
                error = "could not safely retain the nominal one-day reminder";
                return false;
            }
            eventBlock.replace(alarmStart, alarmEnd + std::string("END:VALARM\r\n").size() - alarmStart, nominalAlarm);
        }
    }
    const auto insertion = eventBlock.find("END:VEVENT\r\n");
    if (insertion == std::string::npos) { error = "could not locate serialized VEVENT end"; return false; }
    eventBlock.insert(insertion, preserved);
    result = existing.substr(0, originalStart) + eventBlock + existing.substr(originalTail);
    if (serialized.find("BEGIN:VTIMEZONE") != std::string::npos) {
        result = mergeRecurrenceTimezones(result, serialized);
        if (result.empty()) {
            error = "could not merge recurrence timezones";
            return false;
        }
    }
    return true;
}
