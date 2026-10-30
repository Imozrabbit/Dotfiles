#include "recurrence.h"
#include "helper.h"
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSet>
#include <QTimeZone>
#include <algorithm>
#include <cmath>
#include <libical/ical.h>
#include <map>
#include <memory>
#include <vector>

namespace {
constexpr int maxSteps = 1000000;

bool fail(QString &error, const QString &message) {
    error = message;
    return false;
}

bool keys(const QJsonValue &value, const QStringList &required) {
    if (!value.isObject() || value.toObject().size() != required.size())
        return false;
    for (const auto &key : required)
        if (!value.toObject().contains(key))
            return false;
    return true;
}

bool integer(const QJsonValue &value, int minimum, int maximum) {
    const double number = value.toDouble(-1);
    return value.isDouble() && std::isfinite(number) && std::floor(number) == number && number >= minimum && number <= maximum;
}

QDate date(const QJsonValue &value) {
    if (!value.isString())
        return {};
    const QString text = value.toString();
    const QDate result = QDate::fromString(text, Qt::ISODate);
    return text.size() == 10 && result.year() >= 1 && result.toString(Qt::ISODate) == text ? result : QDate{};
}

QDateTime timestamp(const QJsonValue &value) {
    static const QRegularExpression format(QStringLiteral("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,3})?(?:Z|[+-]\\d{2}:\\d{2})$"));
    if (!value.isString() || !format.match(value.toString()).hasMatch())
        return {};
    return QDateTime::fromString(value.toString(), Qt::ISODate);
}

QDate boundary(const QJsonObject &rule) {
    const QDate start = date(rule.value("startsOn"));
    if (rule.value("frequency") == "monthly")
        return QDate(start.year(), start.month(), 1);
    if (rule.value("frequency") == "yearly")
        return QDate(start.year(), 1, 1);
    return start;
}

bool validateRule(const QJsonValue &value, QString &error) {
    if (!keys(value, {"frequency", "interval", "startsOn", "pattern", "ends"}))
        return fail(error, "Recurrence schema is invalid");
    const auto rule      = value.toObject();
    const auto frequency = rule.value("frequency").toString();
    if (!QStringList{"daily", "weekly", "monthly", "yearly"}.contains(frequency) || !integer(rule.value("interval"), 1, 2147483647) || !date(rule.value("startsOn")).isValid())
        return fail(error, "Recurrence frequency, interval or boundary is invalid");
    const auto patternValue = rule.value("pattern");
    const auto pattern      = patternValue.toObject();
    bool valid              = false;
    if (frequency == "daily") {
        valid = keys(patternValue, {});
    } else if (frequency == "weekly" || (frequency == "monthly" && pattern.value("mode") == "dates")) {
        const QString selection = frequency == "weekly" ? "weekdays" : "days";
        valid                   = keys(patternValue, frequency == "weekly" ? QStringList{selection} : QStringList{"mode", selection}) && pattern.value(selection).isArray() && !pattern.value(selection).toArray().isEmpty();
        for (const auto &item : pattern.value(selection).toArray())
            valid = valid && integer(item, frequency == "weekly" ? 0 : 1, frequency == "weekly" ? 6 : 31);
    } else if (frequency == "monthly" && pattern.value("mode") == "positions") {
        valid = keys(patternValue, {"mode", "positions"}) && pattern.value("positions").isArray() && !pattern.value("positions").toArray().isEmpty();
        for (const auto &item : pattern.value("positions").toArray()) {
            const auto position = item.toObject();
            valid               = valid && keys(item, {"ordinal", "weekday"}) && (integer(position.value("ordinal"), 1, 5) || integer(position.value("ordinal"), -1, -1)) && integer(position.value("weekday"), 0, 6);
        }
    } else if (frequency == "yearly") {
        valid = keys(patternValue, {"dates"}) && pattern.value("dates").isArray() && !pattern.value("dates").toArray().isEmpty();
        for (const auto &item : pattern.value("dates").toArray()) {
            const auto pair = item.toObject();
            valid           = valid && keys(item, {"month", "day"}) && integer(pair.value("month"), 1, 12) && integer(pair.value("day"), 1, 31) && QDate(2000, pair.value("month").toInt(), pair.value("day").toInt()).isValid();
        }
    }
    if (!valid)
        return fail(error, "Recurrence pattern is invalid");
    const auto endsValue = rule.value("ends");
    const auto ends      = endsValue.toObject();
    valid                = (keys(endsValue, {"mode"}) && ends.value("mode") == "never") || (keys(endsValue, {"mode", "count"}) && ends.value("mode") == "count" && integer(ends.value("count"), 1, 2147483647)) || (keys(endsValue, {"mode", "date"}) && ends.value("mode") == "date" && date(ends.value("date")).isValid() && date(ends.value("date")) >= boundary(rule));
    return valid || fail(error, "Recurrence end condition is invalid");
}

icaltimetype dayTime(const QDate &day) {
    auto value    = icaltime_null_time();
    value.year    = day.year();
    value.month   = day.month();
    value.day     = day.day();
    value.is_date = 1;
    return value;
}

// Date selection stays in libical; interval phase stays anchored to the original boundary.
class Dates {
    struct Cursor {
        std::unique_ptr<icalrecur_iterator, decltype(&icalrecur_iterator_free)> iterator{nullptr, icalrecur_iterator_free};
        QDate next;
    };
    std::vector<Cursor> cursors;
    QJsonObject rule;
    QDate anchor;
    int steps = 0;

    QDate nextPhase(const QDate &day) const {
        const QString frequency = rule.value("frequency").toString();
        const qint64 interval   = rule.value("interval").toInt();
        qint64 phase            = 0;
        QDate cycle;
        if (frequency == "daily") {
            phase = anchor.daysTo(day);
            cycle = day;
        } else if (frequency == "weekly") {
            const QDate first = anchor.addDays(1 - anchor.dayOfWeek());
            cycle             = day.addDays(1 - day.dayOfWeek());
            phase             = first.daysTo(cycle) / 7;
        } else if (frequency == "monthly") {
            cycle = QDate(day.year(), day.month(), 1);
            phase = (day.year() - anchor.year()) * 12LL + day.month() - anchor.month();
        } else {
            cycle = QDate(day.year(), 1, 1);
            phase = day.year() - anchor.year();
        }
        if (phase % interval == 0)
            return day;
        const qint64 jump = interval - phase % interval;
        return frequency == "daily"     ? cycle.addDays(jump)
               : frequency == "weekly"  ? cycle.addDays(jump * 7)
               : frequency == "monthly" ? cycle.addMonths(jump)
                                        : cycle.addYears(jump);
    }

    void advance(Cursor &cursor) {
        cursor.next = {};
        while (++steps <= maxSteps) {
            const auto value = icalrecur_iterator_next(cursor.iterator.get());
            if (icaltime_is_null_time(value))
                return;
            const QDate candidate(value.year, value.month, value.day);
            if (!candidate.isValid() || candidate.year() > 9999)
                return;
            const QDate phase = nextPhase(candidate);
            if (phase == candidate) {
                cursor.next = candidate;
                return;
            }
            if (!phase.isValid() || phase.year() > 9999 || !icalrecur_iterator_set_start(cursor.iterator.get(), dayTime(phase)))
                return;
        }
    }

  public:
    explicit Dates(const QJsonObject &value, QDate seek = {}) : rule(value), anchor(boundary(value)) {
        const QString frequency = rule.value("frequency").toString();
        const auto pattern      = rule.value("pattern").toObject();
        const QStringList weekdays{"MO", "TU", "WE", "TH", "FR", "SA", "SU"};
        QStringList rules;
        QString text = "FREQ=" + frequency.toUpper() + ";WKST=MO";
        QStringList parts;
        if (frequency == "weekly") {
            for (const auto &day : pattern.value("weekdays").toArray())
                parts.append(weekdays[day.toInt()]);
            text += ";BYDAY=" + parts.join(',');
        } else if (frequency == "monthly") {
            if (pattern.value("mode") == "dates") {
                for (const auto &day : pattern.value("days").toArray())
                    parts.append(QString::number(day.toInt()));
                text += ";BYMONTHDAY=" + parts.join(',');
            } else {
                for (const auto &position : pattern.value("positions").toArray())
                    parts.append(QString::number(position.toObject().value("ordinal").toInt()) + weekdays[position.toObject().value("weekday").toInt()]);
                text += ";BYDAY=" + parts.join(',');
            }
        } else if (frequency == "yearly") {
            for (const auto &pair : pattern.value("dates").toArray())
                rules.append(text + ";BYMONTH=" + QString::number(pair.toObject().value("month").toInt()) + ";BYMONTHDAY=" + QString::number(pair.toObject().value("day").toInt()));
        }
        if (rules.isEmpty())
            rules.append(text);
        rules.removeDuplicates();
        for (const auto &item : rules) {
            Cursor cursor;
#if ICAL_MAJOR_VERSION >= 4
            auto *recurrence = icalrecurrencetype_new_from_string(item.toUtf8().constData());
            if (!recurrence)
                continue;
            cursor.iterator.reset(icalrecur_iterator_new(recurrence, dayTime(anchor)));
            icalrecurrencetype_unref(recurrence);
#else
            auto recurrence = icalrecurrencetype_from_string(item.toUtf8().constData());
            cursor.iterator.reset(icalrecur_iterator_new(recurrence, dayTime(anchor)));
            icalrecurrencetype_clear(&recurrence);
#endif
            if (!cursor.iterator)
                continue;
            if (seek.isValid() && seek > anchor)
                icalrecur_iterator_set_start(cursor.iterator.get(), dayTime(seek));
            advance(cursor);
            cursors.push_back(std::move(cursor));
        }
    }

    QDate next() {
        QDate result;
        for (const auto &cursor : cursors)
            if (cursor.next.isValid() && (!result.isValid() || cursor.next < result))
                result = cursor.next;
        for (auto &cursor : cursors)
            if (cursor.next == result && result.isValid())
                advance(cursor);
        return result;
    }
    bool exhaustedBudget() const { return steps > maxSteps; }
    int work() const { return steps; }
};

QString utcText(const QDateTime &value) {
    return value.toUTC().toString(value.time().msec() ? Qt::ISODateWithMs : Qt::ISODate);
}

QString icalText(icalcomponent *component, icalproperty_kind kind) {
    auto *property = icalcomponent_get_first_property(component, kind);
    if (!property)
        return {};
    const char *value = kind == ICAL_SUMMARY_PROPERTY       ? icalproperty_get_summary(property)
                        : kind == ICAL_DESCRIPTION_PROPERTY ? icalproperty_get_description(property)
                        : kind == ICAL_LOCATION_PROPERTY    ? icalproperty_get_location(property)
                        : kind == ICAL_UID_PROPERTY         ? icalproperty_get_uid(property)
                                                            : icalproperty_get_value_as_string(property);
    return value ? QString::fromUtf8(value) : QString{};
}

// Supplied VTIMEZONE wins over builtin definitions. Floating times belong to the viewer.
QDateTime icalInstant(icalcomponent *calendar, icalproperty *property, icaltimetype value) {
    if (icaltime_is_null_time(value) || !icaltime_is_valid_time(value))
        return {};
    const QDate day(value.year, value.month, value.day);
    const QTime clock(value.hour, value.minute, value.second);
    if (!day.isValid() || value.year < 1 || value.year > 9999 || (!value.is_date && !clock.isValid()))
        return {};
    if (value.is_date)
        return QDateTime(day, QTime(0, 0), QTimeZone::systemTimeZone());
    const auto *parameter = property ? icalproperty_get_first_parameter(property, ICAL_TZID_PARAMETER) : nullptr;
    const char *tzid      = parameter ? icalparameter_get_tzid(parameter) : nullptr;
    if (icaltime_is_utc(value) && (!tzid || !*tzid))
        return QDateTime(day, clock, QTimeZone::utc());
    const icaltimezone *zone = icaltime_is_utc(value) ? icaltimezone_get_utc_timezone() : nullptr;
    if (tzid && *tzid) {
        zone = icalcomponent_get_timezone(calendar, tzid);
        if (!zone)
            zone = icaltimezone_get_builtin_timezone(tzid);
        if (!zone)
            return {};
    }
    if (!zone) {
        const QDateTime result(day, clock, QTimeZone::systemTimeZone());
        return result.date() == day && result.time() == clock ? result : QDateTime{};
    }
    const auto seconds   = icaltime_as_timet_with_zone(value, zone);
    const auto roundTrip = icaltime_from_timet_with_zone(seconds, 0, zone);
    if (roundTrip.year != value.year || roundTrip.month != value.month || roundTrip.day != value.day || roundTrip.hour != value.hour || roundTrip.minute != value.minute || roundTrip.second != value.second)
        return {};
    return QDateTime::fromSecsSinceEpoch(seconds, QTimeZone::utc());
}

QString icalIdentity(icaltimetype value) {
    const auto day = QDate(value.year, value.month, value.day).toString(Qt::ISODate);
    return value.is_date ? day : day + "T" + QTime(value.hour, value.minute, value.second).toString(Qt::ISODate);
}

QDateTime icalDurationEnd(icalcomponent *calendar, icalproperty *property,
                          icaltimetype start, icaldurationtype duration) {
    const qint64 days    = qint64(duration.weeks) * 7 + duration.days;
    const qint64 seconds = qint64(duration.hours) * 3600 + qint64(duration.minutes) * 60 + duration.seconds;
    if (duration.is_neg || days > 3652058 || (start.is_date && seconds != 0))
        return {};
    // Nominal days/weeks advance the source-zone clock; smaller units are elapsed.
    icaltime_adjust(&start, int(days), 0, 0, 0);
    return icalInstant(calendar, property, start).addSecs(seconds);
}

bool reminderLead(const QJsonObject &event, qint64 &leadMs, QString &error) {
    if (!event.value("reminders").isArray())
        return fail(error, "Reminder list is invalid");
    for (const auto &value : event.value("reminders").toArray()) {
        if (!keys(value, {"minutesBefore"}) || !integer(value.toObject().value("minutesBefore"), 0, 2147483647))
            return fail(error, "Reminder lead is invalid");
        leadMs = std::max(leadMs, qint64(value.toObject().value("minutesBefore").toInt()) * 60000);
    }
    return true;
}

bool reminderInRange(const QJsonObject &event, qint64 startMs, qint64 from, qint64 until) {
    for (const auto &value : event.value("reminders").toArray()) {
        const qint64 deadline = startMs - qint64(value.toObject().value("minutesBefore").toInt()) * 60000;
        if (deadline >= from && deadline < until)
            return true;
    }
    return false;
}

bool expandIcalMaster(const QJsonObject &master, qint64 rangeStart, qint64 rangeEnd,
                      QJsonArray &output, QJsonArray &warnings, int &work, qint64 &outputBytes, QString &error, bool forReminders) {
    const qint64 deadlineEnd = rangeEnd;
    qint64 leadMs = 0;
    bool hasReminders = !master.value("reminders").toArray().isEmpty();
    if (forReminders && !reminderLead(master, leadMs, error))
        return false;
    const QString uid = master.value("uid").toString();
    const auto warn   = [&](const QString &message) {
        const QString warning = uid + ": " + message;
        const auto bytes      = QJsonDocument(QJsonArray{warning}).toJson(QJsonDocument::Compact).size();
        if (warnings.size() >= 100000 || outputBytes + bytes > 32 * 1024 * 1024 - 1024)
            return fail(error, "Occurrence query exceeds output limit");
        outputBytes += bytes;
        warnings.append(warning);
        return true; // Preserve other valid series; never invent this one's occurrences.
    };
    const auto input = master.value("ical").toString().toUtf8();
    if (input.isEmpty() || input.size() > 16 * 1024 * 1024 || input.contains('\0'))
        return warn("Invalid retained iCalendar data");
    std::unique_ptr<icalcomponent, decltype(&icalcomponent_free)> calendar(icalparser_parse_string(input.constData()), icalcomponent_free);
    if (!calendar || icalcomponent_isa(calendar.get()) != ICAL_VCALENDAR_COMPONENT || icalcomponent_count_errors(calendar.get()))
        return warn("Malformed retained iCalendar data");
    icalcomponent *base = nullptr;
    QString sourceUid;
    std::vector<icalcomponent *> overrides;
    for (auto *component      = icalcomponent_get_first_component(calendar.get(), ICAL_VEVENT_COMPONENT);
         component; component = icalcomponent_get_next_component(calendar.get(), ICAL_VEVENT_COMPONENT)) {
        const QString memberUid = icalText(component, ICAL_UID_PROPERTY);
        if (memberUid.isEmpty() || (!sourceUid.isEmpty() && sourceUid != memberUid))
            return warn("Retained calendar must contain one UID");
        sourceUid = memberUid;
        if (icalcomponent_get_first_property(component, ICAL_RECURRENCEID_PROPERTY))
            overrides.push_back(component);
        else if (base)
            return warn("Duplicate recurrence master");
        else
            base = component;
    }
    if (!base)
        return warn("Missing recurrence master");
    if (master.value("calendarId").isString() && uid != master.value("calendarId").toString() + ":" + sourceUid)
        return warn("Retained calendar UID does not match master");
    if (icalcomponent_count_properties(base, ICAL_RRULE_PROPERTY) > 1 || icalcomponent_get_first_property(base, ICAL_EXRULE_PROPERTY))
        return warn("Multiple RRULE or EXRULE semantics are unsupported");
    if (icalText(base, ICAL_STATUS_PROPERTY) == "CANCELLED")
        return true;
    auto *startProperty    = icalcomponent_get_first_property(base, ICAL_DTSTART_PROPERTY);
    auto *endProperty      = icalcomponent_get_first_property(base, ICAL_DTEND_PROPERTY);
    auto *durationProperty = icalcomponent_get_first_property(base, ICAL_DURATION_PROPERTY);
    if (!startProperty || (endProperty && durationProperty))
        return warn("Recurrence master needs DTSTART and at most one end/duration");
    const auto startValue  = icalproperty_get_dtstart(startProperty);
    const bool implicitEnd = !endProperty && !durationProperty;
    auto endValue         = endProperty ? icalproperty_get_dtend(endProperty) : implicitEnd ? startValue : icalcomponent_get_dtend(base);
    if (implicitEnd && startValue.is_date) icaltime_adjust(&endValue, 1, 0, 0, 0);
    const auto original    = icalInstant(calendar.get(), startProperty, startValue);
    const auto originalEnd = durationProperty
                                 ? icalDurationEnd(calendar.get(), startProperty, startValue, icalproperty_get_duration(durationProperty))
                                  : icalInstant(calendar.get(), endProperty ? endProperty : startProperty, endValue);
    if (!original.isValid() || !originalEnd.isValid() || originalEnd < original
        || (originalEnd == original && !implicitEnd) || startValue.is_date != endValue.is_date)
        return warn("Invalid recurrence master dates/timezone");
    const bool allDay     = startValue.is_date;
    const auto inRange = [&](const QDateTime &start, const QDateTime &end) {
        const auto from = start.toMSecsSinceEpoch(), until = end.toMSecsSinceEpoch();
        return from < rangeEnd && (until > rangeStart || (from == until && from >= rangeStart));
    };
    const auto isFloating = [](icalproperty *property, icaltimetype value) {
        return !value.is_date && !icaltime_is_utc(value) && !icalproperty_get_first_parameter(property, ICAL_TZID_PARAMETER);
    };
    const bool floating   = isFloating(startProperty, startValue);
    const qint64 duration = original.msecsTo(originalEnd);
    const qint64 days     = QDate(startValue.year, startValue.month, startValue.day).daysTo(QDate(endValue.year, endValue.month, endValue.day));
    const auto ending     = [&](icalproperty *property, icaltimetype value, const QDateTime &from) {
        if (durationProperty) {
            return icalDurationEnd(calendar.get(), property, value, icalproperty_get_duration(durationProperty));
        }
        return allDay ? QDateTime(from.date().addDays(days), QTime(0, 0), QTimeZone::systemTimeZone()) : from.addMSecs(duration);
    };
    struct Replacement {
        icaltimetype identity;
        QDateTime start, end;
        QJsonObject data;
        bool cancelled = false;
        bool floating  = false;
    };
    std::map<qint64, Replacement> replacements;
    for (auto *component : overrides) {
        auto *identityProperty = icalcomponent_get_first_property(component, ICAL_RECURRENCEID_PROPERTY);
        if (icalproperty_get_first_parameter(identityProperty, ICAL_RANGE_PARAMETER))
            return warn("RECURRENCE-ID RANGE overrides are unsupported");
        const auto identity = icalproperty_get_recurrenceid(identityProperty);
        const auto when     = icalInstant(calendar.get(), identityProperty, identity);
        if (!when.isValid() || identity.is_date != allDay || replacements.count(when.toMSecsSinceEpoch()))
            return warn("Invalid or duplicate recurrence override");
        Replacement replacement;
        replacement.identity  = identity;
        replacement.floating  = isFloating(identityProperty, identity);
        replacement.cancelled = icalText(component, ICAL_STATUS_PROPERTY) == "CANCELLED";
        if (!replacement.cancelled) {
            auto *from  = icalcomponent_get_first_property(component, ICAL_DTSTART_PROPERTY);
            auto *until = icalcomponent_get_first_property(component, ICAL_DTEND_PROPERTY);
            auto *span  = icalcomponent_get_first_property(component, ICAL_DURATION_PROPERTY);
            if (!from || (until && span))
                return warn("Override needs DTSTART and at most one end/duration");
            const auto fromValue  = icalproperty_get_dtstart(from);
            const bool implicit = !until && !span;
            auto untilValue = until ? icalproperty_get_dtend(until) : fromValue;
            if (implicit && fromValue.is_date) icaltime_adjust(&untilValue, 1, 0, 0, 0);
            replacement.start     = icalInstant(calendar.get(), from, fromValue);
            replacement.end       = span ? icalDurationEnd(calendar.get(), from, fromValue, icalproperty_get_duration(span))
                                         : icalInstant(calendar.get(), until ? until : from, untilValue);
            if (!replacement.start.isValid() || !replacement.end.isValid() || replacement.end < replacement.start
                || (replacement.end == replacement.start && !implicit) || fromValue.is_date != allDay || (until && untilValue.is_date != allDay))
                return warn("Invalid override dates/timezone");
            if (allDay) {
                replacement.data["start"] = QDate(fromValue.year, fromValue.month, fromValue.day).toString(Qt::ISODate);
                replacement.data["end"]   = replacement.end.date().toString(Qt::ISODate);
            }
            for (const auto &[kind, name] : std::vector<std::pair<icalproperty_kind, const char *>>{
                     {ICAL_SUMMARY_PROPERTY, "title"}, {ICAL_DESCRIPTION_PROPERTY, "description"}, {ICAL_LOCATION_PROPERTY, "location"}})
                if (icalcomponent_get_first_property(component, kind))
                    replacement.data[name] = icalText(component, kind);
            QJsonArray reminders;
            for (const int minutes : simpleDisplayReminders(component))
                reminders.append(QJsonObject{{"minutesBefore", minutes}});
            replacement.data["reminders"] = reminders;
            hasReminders = hasReminders || !reminders.isEmpty();
            if (forReminders && !reminderLead(replacement.data, leadMs, error))
                return false;
        }
        replacements.emplace(when.toMSecsSinceEpoch(), std::move(replacement));
    }
    if (forReminders && !hasReminders)
        return true;
    // ponytail: shared lead span stays under native work limits; group by lead if dense/long-lead series hit the cap.
    if (forReminders)
        rangeEnd = std::min(253402300800000LL, rangeEnd + leadMs);
    QSet<qint64> excluded;
    for (auto *property     = icalcomponent_get_first_property(base, ICAL_EXDATE_PROPERTY);
         property; property = icalcomponent_get_next_property(base, ICAL_EXDATE_PROPERTY)) {
        const auto value = icalproperty_get_exdate(property);
        const auto when  = icalInstant(calendar.get(), property, value);
        if (!when.isValid() || value.is_date != allDay)
            return warn("Invalid EXDATE date/timezone");
        excluded.insert(when.toMSecsSinceEpoch());
    }
    struct Additional {
        icaltimetype value;
        QDateTime start, end;
        bool floating;
    };
    std::vector<Additional> additional;
    std::map<qint64, QDateTime> periodEnds;
    for (auto *property     = icalcomponent_get_first_property(base, ICAL_RDATE_PROPERTY);
         property; property = icalcomponent_get_next_property(base, ICAL_RDATE_PROPERTY)) {
        const auto value     = icalproperty_get_rdate(property);
        const bool period    = icaltime_is_null_time(value.time);
        const auto fromValue = period ? value.period.start : value.time;
        const auto from      = icalInstant(calendar.get(), property, fromValue);
        QDateTime until;
        if (period) {
            until = icaltime_is_null_time(value.period.end)
                        ? icalDurationEnd(calendar.get(), property, fromValue, value.period.duration)
                        : icalInstant(calendar.get(), property, value.period.end);
        } else {
            until = ending(property, fromValue, from);
        }
        if (!from.isValid() || !until.isValid() || until < from || (until == from && (period || !implicitEnd)) || fromValue.is_date != allDay || (period && allDay))
            return warn("Invalid RDATE date/period/timezone");
        if (period) {
            const auto [found, inserted] = periodEnds.emplace(from.toMSecsSinceEpoch(), until);
            if (!inserted && found->second != until)
                return warn("Conflicting RDATE periods");
        }
        additional.push_back({fromValue, from, until, isFloating(property, fromValue)});
    }
    QJsonObject display = master;
    display.remove("ical"); // No full source-calendar copy in every rendered occurrence.
    display["readOnly"] = true;
    if (!additional.empty())
        display["recurrenceSummary"] = "Custom dates";
    QSet<qint64> seen;
    const auto append = [&](icaltimetype identity, const QDateTime &start, const QDateTime &end, const QJsonObject &fields, qint64 identityMs, bool floatingId) {
        if (!start.isValid() || !end.isValid() || end < start || (end == start && allDay) || end.date().year() > 9999)
            return fail(error, "Occurrence end is outside supported dates");
        if (!inRange(start, end))
            return true;
        QJsonObject occurrence = display;
        for (auto it = fields.begin(); it != fields.end(); ++it)
            occurrence[it.key()] = it.value();
        if (forReminders && !reminderInRange(occurrence, start.toMSecsSinceEpoch(), rangeStart, deadlineEnd))
            return true;
        if (!allDay) {
            occurrence["start"] = utcText(start);
            occurrence["end"]   = utcText(end);
        }
        const QString id           = uid + "#" + (allDay || floatingId ? icalIdentity(identity) : utcText(QDateTime::fromMSecsSinceEpoch(identityMs, QTimeZone::utc())));
        occurrence["uid"]          = id;
        occurrence["masterUid"]    = uid;
        occurrence["occurrenceId"] = id;
        occurrence["startMs"]      = double(start.toMSecsSinceEpoch());
        occurrence["endMs"]        = double(end.toMSecsSinceEpoch());
        const auto bytes           = QJsonDocument(occurrence).toJson(QJsonDocument::Compact).size();
        if (output.size() >= 100000 || outputBytes + bytes > 32 * 1024 * 1024 - 1024)
            return fail(error, "Occurrence query exceeds output limit");
        outputBytes += bytes;
        output.append(occurrence);
        return true;
    };
    const auto candidate = [&](icaltimetype value, const QDateTime &start, const QDateTime &defaultEnd, bool floatingId) {
        const auto period = periodEnds.find(start.toMSecsSinceEpoch());
        const auto &end   = period == periodEnds.end() ? defaultEnd : period->second;
        if (!inRange(start, end))
            return true;
        const auto key = start.toMSecsSinceEpoch();
        if (seen.contains(key) || excluded.contains(key) || replacements.count(key))
            return true;
        seen.insert(key);
        const auto fields = allDay ? QJsonObject{{"start", start.date().toString(Qt::ISODate)}, {"end", end.date().toString(Qt::ISODate)}} : QJsonObject{};
        return append(value, start, end, fields, key, floatingId);
    };
    auto *ruleProperty = icalcomponent_get_first_property(base, ICAL_RRULE_PROPERTY);
    if (ruleProperty) {
#if ICAL_MAJOR_VERSION >= 4
        auto *rule = icalproperty_get_rrule(ruleProperty);
        if (!rule)
            return warn("Malformed RRULE");
        const auto count      = rule->count;
        const auto frequency  = rule->freq;
        const auto interval   = rule->interval;
        const auto untilValue = rule->until;
        auto *iterRule        = icalrecurrencetype_clone(rule);
        iterRule->count       = 0;                    // Count valid start times, not nonexistent DST clock times.
        iterRule->until       = icaltime_null_time(); // Compare UTC UNTIL after resolving each local start.
        std::unique_ptr<icalrecur_iterator, decltype(&icalrecur_iterator_free)> iterator(icalrecur_iterator_new(iterRule, startValue), icalrecur_iterator_free);
        icalrecurrencetype_unref(iterRule);
#else
        auto rule             = icalproperty_get_rrule(ruleProperty);
        const auto count      = rule.count;
        const auto frequency  = rule.freq;
        const auto interval   = rule.interval;
        const auto untilValue = rule.until;
        rule.count            = 0;
        rule.until            = icaltime_null_time();
        std::unique_ptr<icalrecur_iterator, decltype(&icalrecur_iterator_free)> iterator(icalrecur_iterator_new(rule, startValue), icalrecur_iterator_free);
        icalrecurrencetype_clear(&rule);
#endif
        if (!iterator)
            return warn("Unsupported RRULE");
        const bool hasUntil = !icaltime_is_null_time(untilValue);
        const auto cutoff   = hasUntil ? icalInstant(calendar.get(), icaltime_is_utc(untilValue) ? nullptr : startProperty, untilValue) : QDateTime{};
        if (hasUntil && !cutoff.isValid())
            return warn("Invalid RRULE UNTIL date/timezone");
        const QStringList units{"seconds", "minutes", "hours", "days", "weeks", "months", "years"};
        const QStringList labels{"Every second", "Every minute", "Hourly", "Daily", "Weekly", "Monthly", "Yearly"};
        const int frequencyIndex = int(frequency);
        if (frequencyIndex >= 0 && frequencyIndex < units.size())
            display["recurrenceSummary"] = interval == 1 ? labels[frequencyIndex]
                                                         : "Every " + QString::number(interval) + " " + units[frequencyIndex];
        // Never-ending rules seek near the range. COUNT rules retain full-series counting.
        // ponytail: libical subdaily INTERVAL seek can change seed phase; iterate
        // under existing work cap until phase-safe native seeking is available.
        const bool phaseSafeSeek = interval == 1 || frequency > ICAL_HOURLY_RECURRENCE;
        if (count == 0 && phaseSafeSeek && rangeStart > original.toMSecsSinceEpoch() + duration) {
            auto seek         = startValue;
            const auto target = QDateTime::fromMSecsSinceEpoch(rangeStart - duration, QTimeZone::utc());
            const auto span   = durationProperty ? icalproperty_get_duration(durationProperty) : icaldurationtype_null_duration();
            if (icaltime_is_utc(startValue) && !icalproperty_get_first_parameter(startProperty, ICAL_TZID_PARAMETER) && span.days == 0 && span.weeks == 0) {
                seek = icaltime_from_timet_with_zone(target.toSecsSinceEpoch(), 0, icaltimezone_get_utc_timezone());
                if (target.time() < original.time()) {
                    // ponytail: libical seek before seed clock needs up to one day's work;
                    // retain work limit, use a phase-safe subdaily iterator if this ceiling matters.
                    const auto day = target.date().addDays(-1);
                    seek           = startValue;
                    seek.year      = day.year();
                    seek.month     = day.month();
                    seek.day       = day.day();
                }
            } else {
                const auto day = target.date().addDays(-2);
                seek.year      = day.year();
                seek.month     = day.month();
                seek.day       = day.day();
            }
            if (!icalrecur_iterator_set_start(iterator.get(), seek))
                return warn("Could not seek recurrence range");
        }
        int emitted = 0;
        while (true) {
            if (++work > maxSteps)
                return fail(error, "Occurrence query exceeds work limit");
            const auto value = icalrecur_iterator_next(iterator.get());
            if (icaltime_is_null_time(value))
                break;
            const auto from = icalInstant(calendar.get(), startProperty, value);
            if (!from.isValid())
                continue;
            if (from.toMSecsSinceEpoch() >= rangeEnd || (hasUntil && from > cutoff) || (count > 0 && emitted >= count))
                break;
            ++emitted;
            const auto until = ending(startProperty, value, from);
            if (!candidate(value, from, until, floating))
                return false;
        }
    }
    if (!candidate(startValue, original, ending(startProperty, startValue, original), floating))
        return false;
    for (const auto &item : additional) {
        if (++work > maxSteps)
            return fail(error, "Occurrence query exceeds work limit");
        if (!candidate(item.value, item.start, item.end, item.floating))
            return false;
    }
    for (const auto &[key, item] : replacements) {
        if (++work > maxSteps)
            return fail(error, "Occurrence query exceeds work limit");
        if (!item.cancelled && !excluded.contains(key) && !append(item.identity, item.start, item.end, item.data, key, item.floating))
            return false;
    }
    return true;
}
} // namespace

bool validateRecurrenceMaster(const QJsonObject &master, QString &error) {
    error.clear();
    if (!master.value("uid").isString() || master.value("uid").toString().isEmpty() || !master.value("allDay").isBool())
        return fail(error, "Event identity or timing is invalid");
    if (master.contains("ical") && (!master.value("ical").isString() || master.value("ical").toString().isEmpty() || master.contains("recurrence")))
        return fail(error, "External recurrence metadata is invalid");
    if (master.contains("recurrence") && !validateRule(master.value("recurrence"), error))
        return false;
    if (master.value("allDay").toBool()) {
        const auto start = date(master.value("start"));
        const auto end   = date(master.value("end"));
        return (start.isValid() && end.isValid() && end > start) || fail(error, "All-day dates are invalid");
    }
    const auto start = timestamp(master.value("start"));
    const auto end   = timestamp(master.value("end"));
    if (!start.isValid() || !end.isValid() || end < start
        || (end == start && !(master.contains("ical") && master.value("readOnly").toBool())))
        return fail(error, "Event dates or duration are invalid");
    if ((master.contains("recurrence") || master.contains("timezone")) && (!master.value("timezone").isString() || !QTimeZone(master.value("timezone").toString().toUtf8()).isValid()))
        return fail(error, "Saved timezone is invalid");
    return true;
}

bool normalizeRecurrenceMaster(const QJsonObject &master, QJsonObject &result, QString &error,
                               bool preserveElapsedDuration) {
    if (!validateRecurrenceMaster(master, error))
        return false;
    result = master;
    if (!master.contains("recurrence"))
        return true;
    auto rule            = master.value("recurrence").toObject();
    rule["startsOn"]     = boundary(rule).toString(Qt::ISODate);
    result["recurrence"] = rule;
    Dates dates(rule);
    const bool allDay = master.value("allDay").toBool();
    const QTimeZone zone(master.value("timezone").toString().toUtf8());
    const auto original    = timestamp(master.value("start")).toTimeZone(zone);
    const auto originalEnd = timestamp(master.value("end")).toTimeZone(zone);
    QDate first;
    QDateTime start;
    while ((first = dates.next()).isValid()) {
        if (allDay)
            break;
        start = QDateTime(first, original.time(), zone);
        if (start.isValid() && start.date() == first && start.time() == original.time())
            break;
    }
    if (!first.isValid())
        return fail(error, "Repeat rule has no valid occurrence within supported dates/work limit");
    if (allDay) {
        result["start"] = first.toString(Qt::ISODate);
        result["end"]   = first.addDays(1).toString(Qt::ISODate);
    } else {
        const auto end = preserveElapsedDuration ? start.addMSecs(original.msecsTo(originalEnd))
                                                 : QDateTime(first.addDays(original.date().daysTo(originalEnd.date())), originalEnd.time(), zone);
        if (!end.isValid() || end <= start || (!preserveElapsedDuration && end.time() != originalEnd.time()))
            return fail(error, "First occurrence end time is invalid in saved timezone");
        result["start"] = utcText(start);
        result["end"]   = utcText(end);
    }
    return true;
}

bool expandCalendarRange(const QJsonObject &request, QJsonObject &result, QString &error) {
    error.clear();
    if (request.contains("forReminders") && !request.value("forReminders").isBool())
        return fail(error, "Reminder query mode is invalid");
    const bool forReminders = request.value("forReminders").toBool();
    const double from          = request.value("rangeStartMs").toDouble(NAN);
    const double until         = request.value("rangeEndMs").toDouble(NAN);
    constexpr double dateLimit = 253402300800000.0;
    if (!request.value("requestId").isString() || !request.value("events").isArray() || !std::isfinite(from) || !std::isfinite(until) || std::floor(from) != from || std::floor(until) != until || from < -62135596800000.0 || until > dateLimit || until <= from)
        return fail(error, "Occurrence range/request is invalid");
    const qint64 rangeStart = qint64(from), rangeEnd = qint64(until);
    QJsonArray occurrences;
    QJsonArray warnings;
    int work           = 0;
    qint64 outputBytes = 0;
    bool outputLimit   = false;
    QSet<QString> identities;
    for (const auto &value : request.value("events").toArray()) {
        if (++work > maxSteps)
            return fail(error, "Occurrence query exceeds work limit");
        const QJsonObject master = value.toObject();
        if (!value.isObject() || !validateRecurrenceMaster(master, error))
            return false;
        const QString uid = master.value("uid").toString();
        if (identities.contains(uid))
            return fail(error, "Duplicate master identity");
        identities.insert(uid);
        if (master.contains("ical")) {
            if (!expandIcalMaster(master, rangeStart, rangeEnd, occurrences, warnings, work, outputBytes, error, forReminders))
                return false;
            continue;
        }
        qint64 leadMs = 0;
        if (forReminders && !reminderLead(master, leadMs, error))
            return false;
        if (forReminders && master.value("reminders").toArray().isEmpty())
            continue;
        const qint64 masterRangeEnd = forReminders ? std::min(253402300800000LL, rangeEnd + leadMs) : rangeEnd;
        const bool allDay            = master.value("allDay").toBool();
        const QTimeZone zone         = allDay ? QTimeZone::systemTimeZone()
                                              : QTimeZone(master.value("timezone").toString().toUtf8());
        const QDateTime original     = allDay ? QDateTime(date(master.value("start")), QTime(0, 0), zone)
                                              : timestamp(master.value("start"));
        const QDateTime originalEnd  = allDay ? QDateTime(date(master.value("end")), QTime(0, 0), zone)
                                              : timestamp(master.value("end"));
        const qint64 duration        = original.msecsTo(originalEnd);
        const qint64 occurrenceBytes = QJsonDocument(master).toJson(QJsonDocument::Compact).size() + 256 + uid.toUtf8().size() * 3;
        const auto append            = [&](const QDateTime &start, const QDateTime &end, const QDate &day, bool recurring) {
            if (start.toMSecsSinceEpoch() >= masterRangeEnd || end.toMSecsSinceEpoch() <= rangeStart
                || (forReminders && !reminderInRange(master, start.toMSecsSinceEpoch(), rangeStart, rangeEnd)))
                return;
            if (occurrences.size() >= 100000 || outputBytes + occurrenceBytes > 32 * 1024 * 1024 - 1024) {
                outputLimit = true;
                return;
            }
            outputBytes += occurrenceBytes;
            QJsonObject occurrence = master;
            if (recurring) {
                occurrence["start"] = allDay ? day.toString(Qt::ISODate) : utcText(start);
                occurrence["end"]   = allDay ? day.addDays(1).toString(Qt::ISODate) : utcText(end);
                occurrence["uid"]   = uid + "#" + day.toString(Qt::ISODate);
            }
            occurrence["masterUid"]    = uid;
            occurrence["occurrenceId"] = occurrence.value("uid");
            occurrence["startMs"]      = double(start.toMSecsSinceEpoch());
            occurrence["endMs"]        = double(end.toMSecsSinceEpoch());
            occurrences.append(occurrence);
        };
        if (!master.contains("recurrence")) {
            append(original, originalEnd, original.date(), false);
            if (outputLimit)
                return fail(error, "Occurrence query exceeds output limit");
            continue;
        }
        const auto rule     = master.value("recurrence").toObject();
        const auto ends     = rule.value("ends").toObject();
        const bool counted  = ends.value("mode") == "count";
        const int count     = ends.value("count").toInt();
        const QDate endDate = date(ends.value("date"));
        const auto lookback = QDateTime::fromMSecsSinceEpoch(rangeStart - (allDay ? 2 * 86400000LL : duration), zone).date();
        Dates dates(rule, counted ? QDate{} : lookback);
        int emitted = 0;
        QDate day;
        const QTime clock = original.toTimeZone(zone).time();
        while ((day = dates.next()).isValid()) {
            if (work + dates.work() > maxSteps)
                return fail(error, "Occurrence query exceeds work/output limit");
            if (endDate.isValid() && day > endDate)
                break;
            const QDateTime start(day, allDay ? QTime(0, 0) : clock, zone);
            if (!start.isValid() || (!allDay && (start.date() != day || start.time() != clock)))
                continue;
            if (start.toMSecsSinceEpoch() >= masterRangeEnd)
                break;
            if (counted && emitted >= count)
                break;
            ++emitted;
            const QDateTime end = allDay ? QDateTime(day.addDays(1), QTime(0, 0), zone) : start.addMSecs(duration);
            append(start, end, day, true);
            if (outputLimit)
                return fail(error, "Occurrence query exceeds output limit");
        }
        work += dates.work();
        if (work > maxSteps || dates.exhaustedBudget())
            return fail(error, "Occurrence query exceeds work limit");
    }
    if (occurrences.size() > 100000)
        return fail(error, "Occurrence query exceeds output limit");
    result = QJsonObject{{"requestId", request.value("requestId")}, {"occurrences", occurrences}, {"warnings", warnings}};
    return true;
}
