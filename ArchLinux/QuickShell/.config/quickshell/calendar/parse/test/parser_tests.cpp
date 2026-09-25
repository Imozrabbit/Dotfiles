#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include "calendar_json.h"
#include "helper.h"
#include <filesystem>
#include <fstream>
#include <cstdlib>
#include <iostream>
#include <iterator>
#include <string>
#include <sys/stat.h>

void require(bool condition, const char *expression, int line) {
    if (!condition) {
        std::cerr << "FAIL line " << line << ": " << expression << '\n';
        std::exit(1);
    }
}

#undef assert
#define assert(condition) require(static_cast<bool>(condition), #condition, __LINE__)

void testUtcDateTime() {
    const auto result = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:utc@example
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
SUMMARY:UTC event
END:VEVENT
END:VCALENDAR
)");

    assert(result.error.empty());
    assert(result.events.size() == 1);
    assert(result.events[0].startTime == "2026-06-14T14:00:00Z");
    assert(result.events[0].endTime == "2026-06-14T15:00:00Z");
    assert(result.events[0].uid == "utc@example");
}

void testAllDayDate() {
    const auto result = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:all-day@example
DTSTART;VALUE=DATE:20260614
DTEND;VALUE=DATE:20260615
SUMMARY:All day
END:VEVENT
END:VCALENDAR
)");

    assert(result.error.empty());
    assert(result.events.size() == 1);
    assert(result.events[0].allDay);
    assert(result.events[0].startTime == "2026-06-14");
    assert(result.events[0].endTime == "2026-06-15");
}

void testEqualAllDayDateBecomesExclusiveEnd() {
    const auto result = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:single-day@example
DTSTART;VALUE=DATE:20261231
DTEND;VALUE=DATE:20261231
SUMMARY:Single day
END:VEVENT
END:VCALENDAR
)");

    assert(result.error.empty());
    assert(result.events.size() == 1);
    assert(result.events[0].allDay);
    assert(result.events[0].startTime == "2026-12-31");
    assert(result.events[0].endTime == "2027-01-01");
}

void testNamedAndFloatingTimezones() {
    const auto named = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:named@example
DTSTART;TZID=Europe/Paris:20260614T140000
DTEND;TZID=Europe/Paris:20260614T150000
END:VEVENT
END:VCALENDAR
)");
    assert(named.error.empty());
    assert(named.events.size() == 1);
    assert(named.events[0].startTime == "2026-06-14T12:00:00Z");

    const auto floating = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:floating@example
DTSTART:20260614T140000
DTEND:20260614T150000
END:VEVENT
END:VCALENDAR
)");
    assert(floating.error.empty());
    assert(floating.events.size() == 1);
}

void testEmbeddedTimezoneDefinition() {
    const auto result = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VTIMEZONE
TZID:Test/Offset
BEGIN:STANDARD
DTSTART:19700101T000000
TZOFFSETFROM:+0200
TZOFFSETTO:+0200
TZNAME:TST
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
UID:embedded-zone@example
DTSTART;TZID=Test/Offset:20260614T140000
DTEND;TZID=Test/Offset:20260614T150000
SUMMARY:Embedded timezone
END:VEVENT
END:VCALENDAR
)");
    assert(result.error.empty());
    assert(result.events.size() == 1);
    assert(result.events[0].startTime == "2026-06-14T12:00:00Z");
    assert(result.events[0].endTime == "2026-06-14T13:00:00Z");
}

void testMultipleEventsAndEscapedText() {
    const auto result = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:first@example
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
DESCRIPTION:Line one\nLine two\, with comma
END:VEVENT
BEGIN:VEVENT
UID:second@example
DTSTART:20260615T140000Z
DTEND:20260615T150000Z
END:VEVENT
END:VCALENDAR
)");

    assert(result.error.empty());
    assert(result.events.size() == 2);
    assert(result.events[0].description == "Line one\nLine two, with comma");
}

void testRejectsMalformedDateTime() {
    const auto result = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:invalid@example
DTSTART:20260614T1400Z
DTEND:20260614T150000Z
END:VEVENT
END:VCALENDAR
)");

    assert(!result.error.empty());
    assert(result.events.empty());
}

void testRejectsMalformedEvents() {
    const auto missingUid = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
END:VEVENT
END:VCALENDAR
)");
    assert(!missingUid.error.empty());
    assert(missingUid.events.empty());

    const auto missingEnd = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:missing-end@example
DTSTART:20260614T140000Z
END:VEVENT
END:VCALENDAR
)");
    assert(!missingEnd.error.empty());
    assert(missingEnd.events.empty());

    const auto wrongRoot = parseCalendar("BEGIN:VEVENT\nEND:VEVENT\n");
    assert(!wrongRoot.error.empty());
    assert(wrongRoot.events.empty());

    const auto reversed = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:reversed@example
DTSTART:20260614T150000Z
DTEND:20260614T140000Z
END:VEVENT
END:VCALENDAR
)");
    assert(!reversed.error.empty());
    assert(reversed.events.empty());

    const auto equal = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:equal@example
DTSTART:20260614T140000Z
DTEND:20260614T140000Z
END:VEVENT
END:VCALENDAR
)");
    assert(!equal.error.empty());
    assert(equal.events.empty());
}

void testSerializesDeterministicCalendarJson() {
    Event later;
    later.uid         = "later@example";
    later.summary     = "Later \"event\" — café 🎓";
    later.description = "Line one\nLine two";
    later.location    = "Room \\ 2";
    later.startTime   = "2026-06-15T14:00:00Z";
    later.endTime     = "2026-06-15T15:00:00Z";

    Event earlier;
    earlier.uid       = "earlier@example";
    earlier.summary   = "Earlier";
    earlier.startTime = "2026-06-14";
    earlier.endTime   = "2026-06-15";
    earlier.allDay    = true;

    const std::string json = serializeCalendar({later, earlier}, "edt_unistra");
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(QByteArray::fromStdString(json), &parseError);
    assert(parseError.error == QJsonParseError::NoError);
    assert(document.object().value("version").toInt() == 1);
    const QJsonArray events = document.object().value("events").toArray();
    assert(events.size() == 2);
    assert(events[0].toObject().value("uid").toString() == "edt_unistra:earlier@example");
    assert(events[0].toObject().value("allDay").toBool());
    assert(events[1].toObject().value("title").toString() == "Later \"event\" — café 🎓");
    assert(events[1].toObject().value("description").toString() == "Line one\nLine two");
    assert(events[1].toObject().value("location").toString() == "Room \\ 2");
    assert(json == serializeCalendar({later, earlier}, "edt_unistra"));

    const std::string holidayJson = serializeCalendar({earlier}, "holidays_fr");
    assert(holidayJson.find("holidays_fr:earlier@example") != std::string::npos);
    assert(holidayJson.find("\"calendarId\": \"holidays_fr\"") != std::string::npos);
}

void testSerializesWritableEvent() {
    Event event;
    event.uid = "personal-event";
    event.summary = "Writable event";
    event.description = "Notes";
    event.location = "Library";
    event.startTime = "2026-06-14T14:00:00Z";
    event.endTime = "2026-06-14T15:00:00Z";
    event.reminders = {15, 60};

    const std::string ics = serializeEvent(event);
    assert(ics.find("UID:personal-event") != std::string::npos);
    assert(ics.find("SUMMARY:Writable event") != std::string::npos);
    assert(ics.find("TRIGGER:-PT15M") != std::string::npos);
    assert(ics.find("TRIGGER:-PT60M") != std::string::npos);
    const auto parsed = parseCalendar(ics);
    assert(parsed.events.size() == 1);
    assert(parsed.events[0].reminders == event.reminders);

    event.startTime = "2026-06-14T14:00:00.000Z";
    event.endTime = "2026-06-14T15:00:00.000Z";
    const std::string millisecondIcs = serializeEvent(event);
    assert(millisecondIcs.find("DTSTART:20260614T140000Z") != std::string::npos);
    assert(millisecondIcs.find("DTSTART:20260614T140000000Z") == std::string::npos);
    assert(parseCalendar(millisecondIcs).events.size() == 1);
}

void testDuplicateDisplayAlarmsDoNotInvalidateCache() {
    const auto parsed = parseCalendar(R"(BEGIN:VCALENDAR
BEGIN:VEVENT
UID:duplicate-alarms
DTSTART:20260614T140000Z
DTEND:20260614T150000Z
SUMMARY:Two alarms
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
END:VEVENT
END:VCALENDAR
)");
    assert(parsed.error.empty());
    assert(parsed.events.size() == 1);
    assert(parsed.events[0].reminders == std::vector<int>{15});
}

void testWritesEventFileAtomically() {
    Event event;
    event.uid = "atomic-event";
    event.summary = "Atomic";
    event.startTime = "2026-06-14T14:00:00Z";
    event.endTime = "2026-06-14T15:00:00Z";
    const auto path = std::filesystem::temp_directory_path() / "quickshell-calendar-test.ics";
    std::string error;
    assert(writeEventFile(path.string(), event, error));
    struct stat fileStatus {};
    assert(stat(path.c_str(), &fileStatus) == 0);
    assert((fileStatus.st_mode & 0777) == 0600);
    std::ifstream file(path);
    const std::string source((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    const auto parsed = parseCalendar(source);
    assert(parsed.events.size() == 1);
    assert(parsed.events[0].uid == event.uid);
    std::filesystem::remove(path);

    const auto privateDirectory = std::filesystem::temp_directory_path() / "quickshell-calendar-private-test";
    std::filesystem::remove_all(privateDirectory);
    const auto privatePath = privateDirectory / "nested" / "event.ics";
    assert(writeEventFile(privatePath.string(), event, error));
    assert(stat(privatePath.parent_path().c_str(), &fileStatus) == 0);
    assert((fileStatus.st_mode & 0777) == 0700);
    assert(stat(privatePath.c_str(), &fileStatus) == 0);
    assert((fileStatus.st_mode & 0777) == 0600);
    std::filesystem::remove_all(privateDirectory);
}

void testFailedEventWritePreservesExistingPathData() {
    const auto blocker = std::filesystem::temp_directory_path() / "quickshell-calendar-write-blocker";
    std::filesystem::remove_all(blocker);
    {
        std::ofstream file(blocker, std::ios::binary);
        file << "keep existing data";
    }
    Event event;
    event.uid = "blocked-event";
    event.startTime = "2026-06-14T14:00:00Z";
    event.endTime = "2026-06-14T15:00:00Z";
    std::string error;
    assert(!writeEventFile((blocker / "event.ics").string(), event, error));
    std::ifstream file(blocker, std::ios::binary);
    const std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    assert(contents == "keep existing data");
    std::filesystem::remove(blocker);
}

void testPreservesUncontrolledFoldedProperties() {
    const std::string existing =
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n"
        "UID:folded-preserve\r\nDTSTART:20260614T140000Z\r\nDTEND:20260614T150000Z\r\n"
        "summary;language=en:Old title\r\n"
        "DESCRIPTION:Old description\r\n continued old description\r\n"
        "X-CUSTOM;X-PARAM=1:keep this\r\n\tfolded custom value\r\n"
        "END:VEVENT\r\nEND:VCALENDAR\r\n";
    Event updated;
    updated.uid = "folded-preserve";
    updated.summary = "New title";
    updated.description = "New description";
    updated.startTime = "2026-06-14T14:00:00Z";
    updated.endTime = "2026-06-14T15:00:00Z";
    const auto path = std::filesystem::temp_directory_path() / "quickshell-calendar-folded-test.ics";
    std::string error;
    assert(writeEventFilePreserving(path.string(), updated, existing, error));
    std::ifstream file(path, std::ios::binary);
    const std::string serialized((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    const auto parsed = parseCalendar(serialized);
    assert(parsed.error.empty());
    assert(parsed.events.size() == 1);
    assert(parsed.events[0].summary == "New title");
    assert(parsed.events[0].description == "New description");
    assert(serialized.find("X-CUSTOM;X-PARAM=1:keep this\r\n\tfolded custom value\r\n") != std::string::npos);
    assert(serialized.find("Old title") == std::string::npos);
    assert(serialized.find("Old description") == std::string::npos);
    std::filesystem::remove(path);
}

void testPreservesCalendarEnvelope() {
    const std::string existing =
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Remote//EN\r\n"
        "X-WR-CALNAME:Work calendar\r\n"
        "BEGIN:VTIMEZONE\r\nTZID:Test/Offset\r\nBEGIN:STANDARD\r\n"
        "DTSTART:19700101T000000\r\nTZOFFSETFROM:+0200\r\nTZOFFSETTO:+0200\r\n"
        "TZNAME:TST\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n"
        "BEGIN:VEVENT\r\nUID:envelope-test\r\n"
        "DTSTART:20260614T140000Z\r\nDTEND:20260614T150000Z\r\n"
        "SUMMARY:Before\r\nEND:VEVENT\r\n"
        "X-AFTER-EVENT:keep-me\r\nEND:VCALENDAR\r\n";
    Event event;
    event.uid = "envelope-test";
    event.summary = "After";
    event.startTime = "2026-06-14T14:00:00Z";
    event.endTime = "2026-06-14T15:00:00Z";
    const auto path = std::filesystem::temp_directory_path() / "quickshell-calendar-envelope-test.ics";
    std::string error;
    assert(writeEventFilePreserving(path.string(), event, existing, error));
    std::ifstream file(path, std::ios::binary);
    const std::string updated((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    assert(updated.find("PRODID:-//Remote//EN\r\n") != std::string::npos);
    assert(updated.find("X-WR-CALNAME:Work calendar\r\n") != std::string::npos);
    assert(updated.find("BEGIN:VTIMEZONE\r\nTZID:Test/Offset\r\n") != std::string::npos);
    assert(updated.find("X-AFTER-EVENT:keep-me\r\n") != std::string::npos);
    const auto parsed = parseCalendar(updated);
    assert(parsed.error.empty() && parsed.events.size() == 1);
    assert(parsed.events[0].summary == "After");
    std::filesystem::remove(path);
}

void testEditsLowercaseEventBoundariesWithoutLosingProperties() {
    const std::string existing =
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nbegin:vevent\r\n"
        "uid:lowercase-event\r\ndtstart:20260614T140000Z\r\n"
        "dtend:20260614T150000Z\r\nsummary:Before\r\n"
        "X-CUSTOM:keep-me\r\nend:vevent\r\nEND:VCALENDAR\r\n";
    const auto parsed = parseCalendar(existing);
    assert(parsed.error.empty() && parsed.events.size() == 1);
    Event event = parsed.events[0];
    event.summary = "After";
    const auto path = std::filesystem::temp_directory_path() / "quickshell-calendar-lowercase-test.ics";
    std::string error;
    assert(writeEventFilePreserving(path.string(), event, existing, error));
    std::ifstream file(path, std::ios::binary);
    const std::string updated((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    assert(updated.find("X-CUSTOM:keep-me\r\n") != std::string::npos);
    assert(updated.find("summary:Before") == std::string::npos);
    assert(parseCalendar(updated).events[0].summary == "After");
    std::filesystem::remove(path);
}

void testSerializesSyncedCache() {
    Event event;
    event.uid = "cached-event";
    event.summary = "Cached";
    event.startTime = "2026-06-14T14:00:00Z";
    event.endTime = "2026-06-14T15:00:00Z";
    event.reminders = {15};
    const std::string cache = serializeSyncedCalendar({event}, "personal");
    assert(cache == serializeSyncedCalendar({event}, "personal"));
    assert(cache.find("\"version\": 2") != std::string::npos);
    assert(cache.find("\"uid\": \"personal:cached-event\"") != std::string::npos);
    assert(cache.find("\"sourceUid\": \"cached-event\"") != std::string::npos);
    assert(cache.find("\"revision\": \"") != std::string::npos);
    assert(cache.find("faea812029781c625278543b8ea2d99e3da4e6488c206bb2baa0ee4c1fe6dc4b") != std::string::npos);
    assert(cache.find("\"minutesBefore\": 15") != std::string::npos);
}

void testImportedCachePreservesReminders() {
    Event event;
    event.uid = "reminder-import";
    event.startTime = "2026-06-14T14:00:00Z";
    event.endTime = "2026-06-14T15:00:00Z";
    event.reminders = {15, 60};
    const std::string json = serializeCalendar({event}, "feed");
    const QJsonDocument document = QJsonDocument::fromJson(QByteArray::fromStdString(json));
    const QJsonArray reminders = document.object().value("events").toArray()[0].toObject().value("reminders").toArray();
    assert(reminders.size() == 2);
    assert(reminders[0].toObject().value("minutesBefore").toInt() == 15);
    assert(reminders[1].toObject().value("minutesBefore").toInt() == 60);
}

int main() {
    if (std::getenv("CALENDAR_TEST_FORCE_FAILURE"))
        assert(false);
    testUtcDateTime();
    testAllDayDate();
    testEqualAllDayDateBecomesExclusiveEnd();
    testNamedAndFloatingTimezones();
    testEmbeddedTimezoneDefinition();
    testMultipleEventsAndEscapedText();
    testRejectsMalformedDateTime();
    testRejectsMalformedEvents();
    testSerializesDeterministicCalendarJson();
    testSerializesWritableEvent();
    testDuplicateDisplayAlarmsDoNotInvalidateCache();
    testWritesEventFileAtomically();
    testFailedEventWritePreservesExistingPathData();
    testPreservesUncontrolledFoldedProperties();
    testPreservesCalendarEnvelope();
    testEditsLowercaseEventBoundariesWithoutLosingProperties();
    testSerializesSyncedCache();
    testImportedCachePreservesReminders();
}
