#include "calendar_json.h"
#include "series_group.h"
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>
#include <sstream>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <set>

namespace {

QJsonObject eventJson(const Event &event, const std::string &sourceId, bool synced) {
    QJsonArray reminders;
    for (const int minutes : event.reminders)
        reminders.append(QJsonObject{{QStringLiteral("minutesBefore"), minutes}});
    QJsonObject result{
        {QStringLiteral("uid"), QString::fromStdString(sourceId + ":" + event.uid)},
        {QStringLiteral("calendarId"), QString::fromStdString(sourceId)},
        {QStringLiteral("title"), QString::fromStdString(event.summary)},
        {QStringLiteral("description"), QString::fromStdString(event.description)},
        {QStringLiteral("location"), QString::fromStdString(event.location)},
        {QStringLiteral("start"), QString::fromStdString(event.startTime)},
        {QStringLiteral("end"), QString::fromStdString(event.endTime)},
        {QStringLiteral("allDay"), event.allDay},
        {QStringLiteral("reminders"), reminders}};
    if (synced) {
        result.insert(QStringLiteral("sourceUid"), QString::fromStdString(event.uid));
        result.insert(QStringLiteral("revision"), QString::fromStdString(eventRevision(event)));
    }
    if (synced && !event.recurrence.empty()) {
        result.insert(QStringLiteral("recurrence"), QJsonDocument::fromJson(QByteArray::fromStdString(event.recurrence)).object());
        if (!event.allDay)
            result.insert(QStringLiteral("timezone"), QString::fromStdString(event.timezone));
    } else if (!event.ical.empty()) {
        result.insert(QStringLiteral("ical"), QString::fromStdString(event.ical));
        result.insert(QStringLiteral("readOnly"), true);
    }
    if (synced && !event.seriesGroup.empty())
        result.insert(QStringLiteral("seriesGroup"), QJsonDocument::fromJson(QByteArray::fromStdString(event.seriesGroup)).object());
    if (event.readOnly)
        result.insert(QStringLiteral("readOnly"), true);
    return result;
}

std::string jsonText(const QJsonObject &object) {
    return QJsonDocument(object).toJson(QJsonDocument::Indented).toStdString();
}

} // namespace

std::string eventRevision(const Event &event) {
    if (!event.groupRevision.empty())
        return event.groupRevision;
    std::ostringstream canonical;
    canonical << event.uid << '\n'
              << event.summary << '\n'
              << event.description << '\n'
              << event.location << '\n'
              << event.startTime << '\n'
              << event.endTime << '\n'
              << event.allDay << '\n';
    for (const int reminder : event.reminders)
        canonical << reminder << ',';
    if (!event.ical.empty())
        canonical << '\n' << event.ical;
    const std::string source = canonical.str();
    return QCryptographicHash::hash(QByteArray::fromStdString(source), QCryptographicHash::Sha256)
        .toHex()
        .toStdString();
}

std::string serializeCalendar(std::vector<Event> events, const std::string &sourceId) {
    std::sort(events.begin(), events.end(), [](const Event &left, const Event &right) {
        if (left.startTime != right.startTime)
            return left.startTime < right.startTime;
        if (left.endTime != right.endTime)
            return left.endTime < right.endTime;
        return left.uid < right.uid;
    });

    QJsonArray eventArray;
    for (const Event &event : events)
        eventArray.append(eventJson(event, sourceId, false));
    const bool extended = std::any_of(events.begin(), events.end(), [](const Event &event) { return !event.ical.empty(); });
    return jsonText({{QStringLiteral("version"), extended ? 2 : 1}, {QStringLiteral("events"), eventArray}});
}

std::string serializeSyncedCalendar(std::vector<Event> events, const std::string &sourceId,
                                    const std::vector<std::string> &warnings) {
    auto diagnostics = warnings;
    reconstructSeriesGroups(events, diagnostics);
    std::sort(events.begin(), events.end(), [](const Event &left, const Event &right) {
        return left.uid < right.uid;
    });

    QJsonArray eventArray;
    for (const Event &event : events)
        eventArray.append(eventJson(event, sourceId, true));
    QJsonArray warningArray;
    for (const std::string &warning : diagnostics)
        warningArray.append(QString::fromStdString(warning));
    const bool extended = std::any_of(events.begin(), events.end(), [](const Event &event) { return !event.ical.empty() || !event.recurrence.empty(); });
    const bool grouped = std::any_of(events.begin(), events.end(), [](const Event &event) { return !event.seriesGroup.empty(); });
    return jsonText({{QStringLiteral("version"), grouped ? 4 : extended ? 3 : 2},
                     {QStringLiteral("events"), eventArray},
                     {QStringLiteral("warnings"), warningArray}});
}

bool rebuildSyncedCache(const std::string &directory, const std::string &output,
                        const std::string &sourceId, std::string &error) {
    namespace fs = std::filesystem;
    std::error_code filesystemError;
    if (!fs::is_directory(directory, filesystemError)) {
        error = "calendar directory is unavailable";
        return false;
    }
    std::vector<Event> events;
    std::vector<std::string> warnings;
    std::set<std::string> uids;
    fs::directory_iterator entry(directory, filesystemError), end;
    for (; !filesystemError && entry != end; entry.increment(filesystemError)) {
        if (!entry->is_regular_file(filesystemError) || entry->path().extension() != ".ics")
            continue;
        std::ifstream file(entry->path(), std::ios::binary);
        if (!file) {
            error = entry->path().string() + ": could not open file";
            return false;
        }
        const std::string source((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        const auto parsed = parseCalendar(source);
        if (!parsed.error.empty()) {
            warnings.push_back(entry->path().filename().string() + ": malformed event omitted from cache");
            continue;
        }
        for (const auto &event : parsed.events) {
            if (!uids.insert(event.uid).second) {
                error = "duplicate UID: " + event.uid;
                return false;
            }
        }
        events.insert(events.end(), parsed.events.begin(), parsed.events.end());
    }
    if (filesystemError) {
        error = "could not scan calendar directory: " + filesystemError.message();
        return false;
    }
    const auto contents = serializeSyncedCalendar(std::move(events), sourceId, warnings);
    std::ifstream existing(output, std::ios::binary);
    if (existing && std::string((std::istreambuf_iterator<char>(existing)), std::istreambuf_iterator<char>()) == contents)
        return true;
    return writeAtomicallyFile(output, contents, error);
}
