#include "synced_recurrence.h"
#include "helper.h"
#include "recurrence.h"
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QTimeZone>
#include <algorithm>
#include <libical/ical.h>
#include <memory>
#include <set>
#include <vector>

namespace {
using Calendar = std::unique_ptr<icalcomponent, decltype(&icalcomponent_free)>;
Calendar parse(const std::string &text) {
    return Calendar(icalparser_parse_string(text.c_str()), icalcomponent_free);
}
std::string text(icalcomponent *component) {
    char *value              = icalcomponent_as_ical_string_r(component);
    const std::string result = value ? value : "";
    if (value)
        icalmemory_free_buffer(value);
    return result;
}
icalcomponent *clone(icalcomponent *component) {
#if ICAL_MAJOR_VERSION >= 4
    return icalcomponent_clone(component);
#else
    return icalcomponent_new_clone(component);
#endif
}
std::string normalizedText(icalcomponent *component) {
    Calendar copy(clone(component), icalcomponent_free);
    if (!copy)
        return {};
    // Compare canonical order without rewriting retained source/timezone content.
    icalcomponent_normalize(copy.get());
    return text(copy.get());
}
void removeProperties(icalcomponent *component, icalproperty_kind kind) {
    while (auto *property = icalcomponent_get_first_property(component, kind)) {
        icalcomponent_remove_property(component, property);
        icalproperty_free(property);
    }
}
QString list(const QJsonArray &values) {
    QStringList items;
    for (const auto &value : values)
        items.append(QString::number(value.toInt()));
    return items.join(',');
}
QString rrule(const QJsonObject &rule, bool allDay, const QTimeZone &zone) {
    const auto frequency = rule.value("frequency").toString();
    const auto pattern   = rule.value("pattern").toObject();
    QString result       = "FREQ=" + frequency.toUpper() + ";INTERVAL=" + QString::number(rule.value("interval").toInt());
    const QStringList weekdays{"MO", "TU", "WE", "TH", "FR", "SA", "SU"};
    if (frequency == "weekly") {
        QStringList values;
        for (const auto &value : pattern.value("weekdays").toArray())
            values.append(weekdays[value.toInt()]);
        result += ";BYDAY=" + values.join(',') + ";WKST=MO";
    } else if (frequency == "monthly") {
        if (pattern.value("mode") == "dates")
            result += ";BYMONTHDAY=" + list(pattern.value("days").toArray());
        else {
            QStringList values;
            for (const auto &value : pattern.value("positions").toArray()) {
                const auto item = value.toObject();
                values.append(QString::number(item.value("ordinal").toInt()) + weekdays[item.value("weekday").toInt()]);
            }
            result += ";BYDAY=" + values.join(',');
        }
    } else if (frequency == "yearly") {
        const auto pair = pattern.value("dates").toArray().first().toObject();
        result += ";BYMONTH=" + QString::number(pair.value("month").toInt()) + ";BYMONTHDAY=" + QString::number(pair.value("day").toInt());
    }
    const auto ends = rule.value("ends").toObject();
    if (ends.value("mode") == "count")
        result += ";COUNT=" + QString::number(ends.value("count").toInt());
    else if (ends.value("mode") == "date") {
        const auto day = QDate::fromString(ends.value("date").toString(), Qt::ISODate);
        if (allDay)
            result += ";UNTIL=" + day.toString("yyyyMMdd");
        else {
            auto cutoff = day.endOfDay(zone);
            // Entirely skipped civil date: cutoff just before next valid date.
            for (int offset = 1; !cutoff.isValid() && offset <= 3; ++offset) {
                const auto next = day.addDays(offset).startOfDay(zone);
                if (next.isValid())
                    cutoff = next.addSecs(-1);
            }
            if (!cutoff.isValid())
                return {};
            result += ";UNTIL=" + cutoff.toUTC().toString("yyyyMMdd'T'HHmmss'Z'");
        }
    }
    return result;
}
std::string signature(icalcomponent *calendar) {
    std::vector<std::string> values;
    std::set<std::string> managedZones;
    int count = 0;
    for (auto *event = icalcomponent_get_first_component(calendar, ICAL_VEVENT_COMPONENT); event;
         event       = icalcomponent_get_next_component(calendar, ICAL_VEVENT_COMPONENT)) {
        ++count;
        for (const auto kind : {ICAL_DTSTART_PROPERTY, ICAL_DTEND_PROPERTY, ICAL_DURATION_PROPERTY,
                                ICAL_RRULE_PROPERTY, ICAL_RDATE_PROPERTY, ICAL_EXDATE_PROPERTY, ICAL_EXRULE_PROPERTY,
                                ICAL_RECURRENCEID_PROPERTY, ICAL_STATUS_PROPERTY}) {
            for (auto *property = icalcomponent_get_first_property(event, kind); property;
                 property       = icalcomponent_get_next_property(event, kind)) {
                for (auto *parameter = icalproperty_get_first_parameter(property, ICAL_TZID_PARAMETER); parameter;
                     parameter       = icalproperty_get_next_parameter(property, ICAL_TZID_PARAMETER)) {
                    const char *id = icalparameter_get_tzid(parameter);
                    if (id)
                        managedZones.insert(id);
                }
                char *value = icalproperty_as_ical_string_r(property);
                if (value) {
                    values.emplace_back(value);
                    icalmemory_free_buffer(value);
                }
            }
        }
    }
    for (auto *zone = icalcomponent_get_first_component(calendar, ICAL_VTIMEZONE_COMPONENT); zone;
         zone       = icalcomponent_get_next_component(calendar, ICAL_VTIMEZONE_COMPONENT)) {
        auto *property = icalcomponent_get_first_property(zone, ICAL_TZID_PROPERTY);
        const char *id = property ? icalproperty_get_tzid(property) : nullptr;
        if (!id || !managedZones.count(id))
            continue;
        values.push_back(normalizedText(zone));
    }
    std::sort(values.begin(), values.end());
    std::string result = std::to_string(count) + "\n";
    for (const auto &value : values)
        result += std::to_string(value.size()) + ":" + value;
    return result;
}
} // namespace

std::string serializeSyncedRecurrence(const Event &event, const std::string &plain) {
    if (event.recurrence.empty())
        return plain;
    const auto rule = QJsonDocument::fromJson(QByteArray::fromStdString(event.recurrence)).object();
    const QTimeZone zone(QByteArray::fromStdString(event.timezone));
    auto calendar = parse(plain);
    if (!calendar)
        return {};
    auto *component = icalcomponent_get_first_component(calendar.get(), ICAL_VEVENT_COMPONENT);
    if (!component)
        return {};
    if (!event.allDay) {
        auto *builtin          = icaltimezone_get_builtin_timezone(event.timezone.c_str());
        auto *builtinComponent = builtin ? icaltimezone_get_component(builtin) : nullptr;
        auto *definition       = builtinComponent ? clone(builtinComponent) : nullptr;
        if (!definition && !zone.hasTransitions()) {
            definition        = icalcomponent_new_vtimezone();
            auto *standard    = icalcomponent_new_xstandard();
            const auto offset = zone.offsetFromUtc(QDateTime::fromSecsSinceEpoch(0, QTimeZone::utc()));
            icalcomponent_add_property(standard, icalproperty_new_dtstart(icaltime_from_string("19700101T000000")));
            icalcomponent_add_property(standard, icalproperty_new_tzoffsetfrom(offset));
            icalcomponent_add_property(standard, icalproperty_new_tzoffsetto(offset));
            icalcomponent_add_component(definition, standard);
        }
        if (!definition)
            return {};
        removeProperties(definition, ICAL_TZID_PROPERTY);
        icalcomponent_add_property(definition, icalproperty_new_tzid(event.timezone.c_str()));
        icalcomponent_add_component(calendar.get(), definition);
        for (const auto kind : {ICAL_DTSTART_PROPERTY, ICAL_DTEND_PROPERTY}) {
            const auto instant = QDateTime::fromString(QString::fromStdString(kind == ICAL_DTSTART_PROPERTY ? event.startTime : event.endTime), Qt::ISODate);
            const auto local   = instant.toTimeZone(zone).toString("yyyyMMdd'T'HHmmss").toUtf8();
            const auto value   = icaltime_from_string(local.constData());
            removeProperties(component, kind);
            auto *property = kind == ICAL_DTSTART_PROPERTY ? icalproperty_new_dtstart(value) : icalproperty_new_dtend(value);
            icalproperty_add_parameter(property, icalparameter_new_tzid(event.timezone.c_str()));
            icalcomponent_add_property(component, property);
        }
    }
    const auto ruleText = rrule(rule, event.allDay, zone);
    if (ruleText.isEmpty())
        return {};
    auto *property = icalproperty_new_from_string(("RRULE:" + ruleText).toUtf8().constData());
    if (!property)
        return {};
    icalcomponent_add_property(component, property);
    const auto ends     = rule.value("ends").toObject();
    const auto firstDay = event.allDay ? QDate::fromString(QString::fromStdString(event.startTime), Qt::ISODate)
                                       : QDateTime::fromString(QString::fromStdString(event.startTime), Qt::ISODate).toTimeZone(zone).date();
    if (ends.value("mode") == "date" && firstDay > QDate::fromString(ends.value("date").toString(), Qt::ISODate)) {
        // RFC recurrence includes DTSTART independently of RRULE's range. Exclude the
        // seed when inclusive Until leaves no matching dates in the logical rule.
        auto *start    = icalcomponent_get_first_property(component, ICAL_DTSTART_PROPERTY);
        auto *excluded = icalproperty_new_exdate(icalproperty_get_dtstart(start));
        if (!event.allDay)
            icalproperty_add_parameter(excluded, icalparameter_new_tzid(event.timezone.c_str()));
        icalcomponent_add_property(component, excluded);
    }
    const auto metadata = QJsonDocument(QJsonObject{{"version", 1}, {"rule", rule}}).toJson(QJsonDocument::Compact).toBase64();
    auto *boundary      = icalproperty_new_x(metadata.constData());
    icalproperty_set_x_name(boundary, "X-QUICKSHELL-RECURRENCE");
    icalcomponent_add_property(component, boundary);
    return text(calendar.get());
}

void restoreSyncedRecurrence(Event &event) {
    if (event.ical.empty())
        return;
    auto calendar = parse(event.ical);
    if (!calendar)
        return;
    auto *component = icalcomponent_get_first_component(calendar.get(), ICAL_VEVENT_COMPONENT);
    if (!component || icalcomponent_get_next_component(calendar.get(), ICAL_VEVENT_COMPONENT))
        return;
    QByteArray encoded;
    for (auto *property = icalcomponent_get_first_property(component, ICAL_X_PROPERTY); property;
         property       = icalcomponent_get_next_property(component, ICAL_X_PROPERTY)) {
        const QString name = QString::fromUtf8(icalproperty_get_x_name(property));
        if (name.startsWith("X-QUICKSHELL-GROUP-", Qt::CaseInsensitive)
            || name.compare("X-QUICKSHELL-TIMEZONE", Qt::CaseInsensitive) == 0)
            return;
        if (name.compare("X-QUICKSHELL-RECURRENCE", Qt::CaseInsensitive) == 0) {
            if (!encoded.isEmpty())
                return;
            encoded = icalproperty_get_x(property);
        }
    }
    if (encoded.isEmpty() || encoded.size() > 32768)
        return;
    const auto decoded = QByteArray::fromBase64Encoding(encoded, QByteArray::AbortOnBase64DecodingErrors);
    if (!decoded)
        return;
    const auto metadata = QJsonDocument::fromJson(decoded.decoded).object();
    if (metadata.size() != 2 || metadata.value("version") != 1 || !metadata.value("rule").isObject())
        return;
    QJsonObject master{{"uid", QString::fromStdString(event.uid)}, {"start", QString::fromStdString(event.startTime)}, {"end", QString::fromStdString(event.endTime)}, {"allDay", event.allDay}, {"recurrence", metadata.value("rule")}};
    if (!event.allDay) {
        auto *start     = icalcomponent_get_first_property(component, ICAL_DTSTART_PROPERTY);
        auto *parameter = start ? icalproperty_get_first_parameter(start, ICAL_TZID_PARAMETER) : nullptr;
        if (!parameter)
            return;
        master["timezone"] = QString::fromUtf8(icalparameter_get_tzid(parameter));
    }
    QJsonObject normalized;
    QString error;
    if (!normalizeRecurrenceMaster(master, normalized, error) || normalized.value("start") != master.value("start") || normalized.value("end") != master.value("end"))
        return;
    const auto rule = normalized.value("recurrence").toObject();
    if (rule.value("frequency") == "yearly" && rule.value("pattern").toObject().value("dates").toArray().size() != 1)
        return;
    Event candidate      = event;
    candidate.recurrence = QJsonDocument(rule).toJson(QJsonDocument::Compact).toStdString();
    candidate.timezone   = normalized.value("timezone").toString().toStdString();
    auto generated       = parse(serializeEvent(candidate));
    if (!generated || signature(calendar.get()) != signature(generated.get()))
        return;
    event.recurrence = candidate.recurrence;
    event.timezone   = candidate.timezone;
}

std::string mergeRecurrenceTimezones(const std::string &source, const std::string &generated) {
    auto original    = parse(source);
    auto replacement = parse(generated);
    if (!original || !replacement)
        return {};
    for (auto *zone = icalcomponent_get_first_component(replacement.get(), ICAL_VTIMEZONE_COMPONENT); zone;
         zone       = icalcomponent_get_next_component(replacement.get(), ICAL_VTIMEZONE_COMPONENT)) {
        const auto *id = icalcomponent_get_first_property(zone, ICAL_TZID_PROPERTY);
        if (!id)
            return {};
        int matches = 0;
        for (auto *component = icalcomponent_get_first_component(original.get(), ICAL_VTIMEZONE_COMPONENT); component;
             component       = icalcomponent_get_next_component(original.get(), ICAL_VTIMEZONE_COMPONENT)) {
            const auto *oldId   = icalcomponent_get_first_property(component, ICAL_TZID_PROPERTY);
            const char *oldName = oldId ? icalproperty_get_tzid(oldId) : nullptr;
            if (oldName && std::string(oldName) == icalproperty_get_tzid(id)) {
                if (++matches > 1 || normalizedText(component) != normalizedText(zone))
                    return {};
            }
        }
        if (matches == 0)
            icalcomponent_add_component(original.get(), clone(zone));
    }
    return text(original.get());
}

std::string recurrenceSourceSignature(const std::string &source) {
    auto calendar = parse(source);
    return calendar ? signature(calendar.get()) : std::string{};
}

bool syncedEventFromJson(const QJsonObject &input, Event &event, std::string &error) {
    if (input.contains("ical")) {
        error = "external recurrence is read-only";
        return false;
    }
    QJsonObject object = input;
    if (object.contains("recurrence") && !object.value("recurrence").isNull()) {
        QJsonObject normalized;
        QString detail;
        if (!normalizeRecurrenceMaster(object, normalized, detail)) {
            error = detail.toStdString();
            return false;
        }
        const auto rule = normalized.value("recurrence").toObject();
        if (rule.value("frequency") == "yearly" && rule.value("pattern").toObject().value("dates").toArray().size() != 1) {
            error = "grouped yearly recurrence is not supported by ordinary mutation";
            return false;
        }
        for (const auto key : {"start", "end"}) {
            if (!normalized.value("allDay").toBool() && QDateTime::fromString(normalized.value(key).toString(), Qt::ISODate).time().msec() != 0) {
                error = "iCalendar recurrence requires whole-second timestamps";
                return false;
            }
        }
        object           = normalized;
        event.recurrence = QJsonDocument(rule).toJson(QJsonDocument::Compact).toStdString();
        event.timezone   = normalized.value("timezone").toString().toStdString();
    }
    for (const char *key : {"uid", "title", "description", "location", "start", "end"}) {
        if (!object.value(QLatin1String(key)).isString()) {
            error = "event fields are invalid";
            return false;
        }
    }
    if (!object.value("allDay").isBool() || !object.value("reminders").isArray()) {
        error = "event fields are invalid";
        return false;
    }
    if (event.recurrence.empty() && object.contains("timezone")) {
        if (object.value("allDay").toBool() || !object.value("timezone").isString() || object.value("timezone").toString().isEmpty()
            || !QTimeZone(object.value("timezone").toString().toUtf8()).isValid()) {
            error = "Saved timezone is invalid";
            return false;
        }
        event.timezone = object.value("timezone").toString().toStdString();
    }
    const auto stringValue = [&object](const char *key) { return object.value(QLatin1String(key)).toString().toStdString(); };
    event.uid              = stringValue("uid");
    event.summary          = stringValue("title");
    event.description      = stringValue("description");
    event.location         = stringValue("location");
    event.startTime        = stringValue("start");
    event.endTime          = stringValue("end");
    event.allDay           = object.value("allDay").toBool();
    if (event.uid.empty() || event.startTime.empty() || event.endTime.empty()) {
        error = "event requires uid, start, and end";
        return false;
    }
    const QString startText       = QString::fromStdString(event.startTime);
    const QString endText         = QString::fromStdString(event.endTime);
    const QDate startDate         = event.allDay ? QDate::fromString(startText, Qt::ISODate) : QDate{};
    const QDate endDate           = event.allDay ? QDate::fromString(endText, Qt::ISODate) : QDate{};
    const QDateTime startDateTime = event.allDay ? QDateTime{} : QDateTime::fromString(startText, Qt::ISODate);
    const QDateTime endDateTime   = event.allDay ? QDateTime{} : QDateTime::fromString(endText, Qt::ISODate);
    if (event.allDay ? !startDate.isValid() || !endDate.isValid() : !startDateTime.isValid() || !endDateTime.isValid()) {
        error = "event dates are invalid";
        return false;
    }
    // Inspect raw digits: QDateTime rounds submillisecond fractions before validation.
    static const QRegularExpression nonzeroFraction("[.,][0-9]*[1-9]");
    if (!event.allDay && (input.value("start").toString().contains(nonzeroFraction) || input.value("end").toString().contains(nonzeroFraction))) {
        error = "iCalendar events require whole-second timestamps";
        return false;
    }
    if (event.allDay ? endDate <= startDate : endDateTime <= startDateTime) {
        error = "event end must be later than start";
        return false;
    }
    for (const auto &value : object.value("reminders").toArray()) {
        const int minutes = value.toObject().value("minutesBefore").toInt(-1);
        if (minutes < 0) {
            error = "reminders must contain nonnegative minutesBefore values";
            return false;
        }
        event.reminders.push_back(minutes);
    }
    return true;
}
