#include "calendar_json.h"
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>
#include <sstream>

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
    return result;
}

std::string jsonText(const QJsonObject &object) {
    return QJsonDocument(object).toJson(QJsonDocument::Indented).toStdString();
}

} // namespace

std::string eventRevision(const Event &event) {
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
    return jsonText({{QStringLiteral("version"), 1}, {QStringLiteral("events"), eventArray}});
}

std::string serializeSyncedCalendar(std::vector<Event> events, const std::string &sourceId,
                                    const std::vector<std::string> &warnings) {
    std::sort(events.begin(), events.end(), [](const Event &left, const Event &right) {
        return left.uid < right.uid;
    });

    QJsonArray eventArray;
    for (const Event &event : events)
        eventArray.append(eventJson(event, sourceId, true));
    QJsonArray warningArray;
    for (const std::string &warning : warnings)
        warningArray.append(QString::fromStdString(warning));
    return jsonText({{QStringLiteral("version"), 2},
                     {QStringLiteral("events"), eventArray},
                     {QStringLiteral("warnings"), warningArray}});
}
