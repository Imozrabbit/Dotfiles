#include "series_group.h"
#include "helper.h"
#include "recurrence.h"
#include "calendar_json.h"
#include "synced_recurrence.h"
#include "calendar_lock.h"
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QDateTime>
#include <QTimeZone>
#include <QRegularExpression>
#include <libical/ical.h>
#include <cerrno>
#include <cstdlib>
#include <fcntl.h>
#include <filesystem>
#include <set>
#include <map>
#include <cmath>
#include <memory>
#include <algorithm>
#include <sys/stat.h>
#include <unistd.h>

namespace fs = std::filesystem;
namespace {
constexpr size_t maxFileBytes = 32 * 1024 * 1024;
constexpr size_t maxSourceBytes = 16 * 1024 * 1024;
constexpr size_t maxJournalBytes = 64 * 1024 * 1024; // Before + after + Base64 overhead.
constexpr const char *journalName = ".calendar-series-transaction.json";

bool validDirectory(const fs::path &directory, QString &error) {
    auto path = directory.lexically_normal();
    while (path.has_relative_path() && path.filename().empty())
        path = path.parent_path();
    struct stat info{};
    if (lstat(path.c_str(), &info) == 0 && S_ISDIR(info.st_mode))
        return true;
    error = "transaction directory is missing or unsafe";
    return false;
}

bool validCacheTarget(const fs::path &root, const std::string &output, const QString &sourceId, QString &error) {
    static const QRegularExpression sourceIdentity("^[A-Za-z0-9_-]{1,256}$");
    if (!sourceIdentity.match(sourceId).hasMatch() || fs::path(output).extension() != ".json" || output.find('\0') != std::string::npos) {
        error = "group source or output is invalid";
        return false;
    }
    struct stat outputInfo{};
    const int outputStatus = lstat(output.c_str(), &outputInfo);
    const int outputError = errno;
    std::error_code pathError;
    const auto cachePath = fs::weakly_canonical(output, pathError);
    if (pathError || (outputStatus == 0 && !S_ISREG(outputInfo.st_mode))
            || (outputStatus < 0 && outputError != ENOENT)) {
        error = "group cache output is unavailable or unsafe";
        return false;
    }
    const auto journalPath = fs::weakly_canonical(root / journalName, pathError);
    if (pathError || cachePath == journalPath) {
        error = "group cache output aliases transaction journal";
        return false;
    }
    return true;
}

fs::path memberPath(const fs::path &directory, const std::string &uid) {
    return directory / (QCryptographicHash::hash(QByteArray::fromStdString(uid), QCryptographicHash::Sha256).toHex().toStdString() + ".ics");
}

// Read a regular file without following symlinks, including dangling symlinks.
bool readFile(const fs::path &path, std::optional<std::string> &result, QString &error, size_t limit = maxFileBytes) {
    result.reset();
    const int fd = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        if (errno == ENOENT)
            return true;
        error = "transaction file unavailable or unsafe";
        return false;
    }
    struct stat info{};
    bool ok = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_size >= 0 && static_cast<size_t>(info.st_size) <= limit;
    std::string contents;
    char buffer[16384];
    while (ok) {
        const auto count = read(fd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR)
            continue;
        if (count < 0) {
            ok = false;
            break;
        }
        if (count == 0)
            break;
        contents.append(buffer, static_cast<size_t>(count));
        ok = contents.size() <= limit;
    }
    close(fd);
    if (!ok) {
        error = "transaction file is not regular, exceeds limit, or cannot be read";
        return false;
    }
    result = std::move(contents);
    return true;
}

bool syncPath(const fs::path &path, bool directory, QString &error) {
    const int fd = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (directory ? O_DIRECTORY : 0));
    const bool ok = fd >= 0 && fsync(fd) == 0;
    if (fd >= 0)
        close(fd);
    if (!ok)
        error = "could not durably sync transaction";
    return ok;
}

bool replace(const fs::path &directory, const fs::path &path, const std::optional<std::string> &contents, QString &error) {
    if (contents) {
        std::string detail;
        if (!writeAtomicallyFile(path.string(), *contents, detail)) {
            error = QString::fromStdString(detail);
            return false;
        }
        if (!syncPath(path, false, error))
            return false;
    } else if (unlink(path.c_str()) != 0 && errno != ENOENT) {
        error = "could not remove transaction file";
        return false;
    }
    return syncPath(directory, true, error);
}

QJsonValue encoded(const std::optional<std::string> &contents) {
    return contents ? QJsonValue(QString::fromLatin1(QByteArray::fromStdString(*contents).toBase64())) : QJsonValue(QJsonValue::Null);
}

bool decoded(const QJsonValue &value, std::optional<std::string> &contents) {
    contents.reset();
    if (value.isNull())
        return true;
    if (!value.isString())
        return false;
    const auto bytes = QByteArray::fromBase64Encoding(value.toString().toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
    if (!bytes || bytes.decoded.size() > static_cast<qsizetype>(maxFileBytes)
            || QString::fromLatin1(bytes.decoded.toBase64()) != value.toString())
        return false;
    contents = bytes.decoded.toStdString();
    return true;
}

bool validChanges(const std::vector<SeriesFileChange> &changes, QString &error) {
    std::set<std::string> uids;
    size_t beforeBytes = 0, afterBytes = 0;
    if (changes.empty() || changes.size() > 366) {
        error = "transaction member count is invalid";
        return false;
    }
    for (const auto &change : changes) {
        if (change.uid.empty() || change.uid.size() > 1024 || change.uid.find('\0') != std::string::npos
                || !uids.insert(change.uid).second || (!change.before && !change.after)) {
            error = "transaction member identity is invalid";
            return false;
        }
        if (change.before)
            beforeBytes += change.uid.size() + change.before->size();
        if (change.after)
            afterBytes += change.uid.size() + change.after->size();
        if (beforeBytes > maxSourceBytes || afterBytes > maxSourceBytes) {
            error = "transaction data exceeds limit";
            return false;
        }
    }
    return true;
}

void interrupt(const std::string &point) {
#ifdef CALENDAR_GROUP_TEST_HOOKS
    const char *wanted = std::getenv("CALENDAR_GROUP_INTERRUPT");
    if (wanted && point == wanted)
        _exit(75);
#else
    (void)point;
#endif
}

bool injectedFailure(size_t index) {
#ifdef CALENDAR_GROUP_TEST_HOOKS
    const char *wanted = std::getenv("CALENDAR_GROUP_FAIL");
    return wanted && "replace:" + std::to_string(index) == wanted;
#else
    (void)index;
    return false;
#endif
}

bool loadJournal(const fs::path &root, QJsonObject &journal, std::vector<SeriesFileChange> &changes, QString &error) {
    std::optional<std::string> text;
    if (!readFile(root / journalName, text, error, maxJournalBytes))
        return false;
    if (!text)
        return true;
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(QByteArray::fromStdString(*text), &parseError);
    journal = document.object();
    const auto phase = journal.value("phase").toString();
    if (parseError.error != QJsonParseError::NoError || !document.isObject() || journal.size() != 3
            || journal.value("version") != 1 || (phase != "prepared" && phase != "committed")
            || !journal.value("changes").isArray()) {
        error = "transaction journal schema is invalid";
        return false;
    }
    for (const auto &value : journal.value("changes").toArray()) {
        const auto item = value.toObject();
        SeriesFileChange change;
        change.uid = item.value("uid").toString().toStdString();
        if (!value.isObject() || item.size() != 3 || !decoded(item.value("before"), change.before)
                || !decoded(item.value("after"), change.after)) {
            error = "transaction journal member is invalid";
            return false;
        }
        changes.push_back(std::move(change));
    }
    return validChanges(changes, error);
}
} // namespace

bool recoverSeriesGroups(const std::string &directory, QString &error) {
    error.clear();
    const fs::path root(directory);
    if (!validDirectory(root, error))
        return false;
    QJsonObject journal;
    std::vector<SeriesFileChange> changes;
    if (!loadJournal(root, journal, changes, error))
        return false;
    if (journal.isEmpty())
        return true;
    if (journal.value("phase") == "prepared") {
        // Check the entire set first; never undo some members then discover newer data.
        for (const auto &change : changes) {
            std::optional<std::string> current;
            if (!readFile(memberPath(root, change.uid), current, error))
                return false;
            if (current != change.before && current != change.after) {
                error = "transaction recovery blocked by newer member content";
                return false;
            }
        }
        for (size_t index = 0; index < changes.size(); ++index) {
            const auto &change = changes[index];
            const auto path = memberPath(root, change.uid);
            std::optional<std::string> current;
            if (!readFile(path, current, error))
                return false;
            if (current == change.before)
                continue;
            if (current != change.after) {
                error = "transaction recovery blocked by newer member content";
                return false;
            }
            if (!replace(root, path, change.before, error))
                return false;
            interrupt("rollback:" + std::to_string(index));
        }
    }
    return replace(root, root / journalName, {}, error);
}

bool prepareSeriesFiles(const std::string &directory, const std::vector<SeriesFileChange> &changes, QString &error) {
    error.clear();
    const fs::path root(directory);
    if (!validChanges(changes, error) || !recoverSeriesGroups(directory, error))
        return false;
    QJsonArray entries;
    for (const auto &change : changes) {
        std::optional<std::string> current;
        if (!readFile(memberPath(root, change.uid), current, error))
            return false;
        if (current != change.before) {
            error = "group member changed; reopen series";
            return false;
        }
        entries.append(QJsonObject{{"uid", QString::fromStdString(change.uid)}, {"before", encoded(change.before)}, {"after", encoded(change.after)}});
    }
    QJsonObject journal{{"version", 1}, {"phase", "prepared"}, {"changes", entries}};
    const auto serialized = QJsonDocument(journal).toJson(QJsonDocument::Compact);
    if (serialized.size() > qsizetype(maxJournalBytes)) {
        error = "transaction journal exceeds limit";
        return false;
    }
    if (!replace(root, root / journalName, serialized.toStdString(), error))
        return false;
    interrupt("prepared");
    return true;
}

bool checkPreparedSeriesFiles(const std::string &directory, QString &error) {
    error.clear();
    QJsonObject journal;
    std::vector<SeriesFileChange> changes;
    if (!validDirectory(directory, error) || !loadJournal(directory, journal, changes, error))
        return false;
    if (journal.value("phase") != "prepared") {
        error = "prepared group transaction is missing";
        return false;
    }
    for (const auto &change : changes) {
        std::optional<std::string> current;
        if (!readFile(memberPath(directory, change.uid), current, error))
            return false;
        if (current != change.before && current != change.after) {
            error = "prepared group changed; recovery requires review";
            return false;
        }
    }
    return true;
}

bool finishSeriesFiles(const std::string &directory, QString &error, bool &sourceCommitted) {
    error.clear();
    sourceCommitted = false;
    const fs::path root(directory);
    if (!checkPreparedSeriesFiles(directory, error))
        return false;
    QJsonObject journal;
    std::vector<SeriesFileChange> changes;
    if (!loadJournal(root, journal, changes, error))
        return false;
    for (const auto &change : changes) {
        std::optional<std::string> current;
        if (!readFile(memberPath(root, change.uid), current, error))
            return false;
        if (current != change.after) {
            error = "group replacement set is incomplete";
            return false;
        }
        if (change.after && !syncPath(memberPath(root, change.uid), false, error))
            return false;
    }
    if (!syncPath(root, true, error))
        return false;
    journal["phase"] = "committed";
    sourceCommitted = true;
    if (!replace(root, root / journalName, QJsonDocument(journal).toJson(QJsonDocument::Compact).toStdString(), error)) {
        error += "; recovery required";
        return false;
    }
    interrupt("committed");
    return replace(root, root / journalName, {}, error);
}

bool commitSeriesFiles(const std::string &directory, const std::vector<SeriesFileChange> &changes,
                       QString &error, bool &sourceCommitted) {
    sourceCommitted = false;
    const fs::path root(directory);
    if (!prepareSeriesFiles(directory, changes, error))
        return false;
    for (size_t index = 0; index < changes.size(); ++index) {
        const auto &change = changes[index];
        const auto path = memberPath(root, change.uid);
        std::optional<std::string> current;
        if (!readFile(path, current, error) || current != change.before || injectedFailure(index) || !replace(root, path, change.after, error)) {
            if (error.isEmpty())
                error = "group member changed during transaction";
            QString recoveryError;
            if (!recoverSeriesGroups(directory, recoveryError))
                error += "; recovery required: " + recoveryError;
            return false;
        }
        interrupt("replace:" + std::to_string(index));
    }
    return finishSeriesFiles(directory, error, sourceCommitted);
}

bool buildSeriesGroup(const QJsonObject &input, QJsonObject &result, QString &error) {
    error.clear();
    result = {};
    const auto uid = input.value("uid").toString();
    static const QRegularExpression identity("^[A-Za-z0-9@_.:-]{1,256}$");
    if (!identity.match(uid).hasMatch() || input.contains("ical")) {
        error = "group identity or source is invalid";
        return false;
    }
    QJsonObject master;
    for (const auto key : {"uid", "title", "description", "location", "start", "end", "allDay", "recurrence", "reminders"})
        master[key] = input.value(key);
    if (input.value("allDay") != true)
        master["timezone"] = input.value("timezone");
    for (const auto key : {"title", "description", "location"}) {
        if (!master.value(key).isString()) {
            error = "group fields are invalid";
            return false;
        }
    }
    if (!master.value("reminders").isArray()) {
        error = "group reminders are invalid";
        return false;
    }
    std::set<int> reminders;
    for (const auto &value : master.value("reminders").toArray()) {
        const auto item = value.toObject();
        const double minutes = item.value("minutesBefore").toDouble(-1);
        if (!value.isObject() || item.size() != 1 || !std::isfinite(minutes) || std::floor(minutes) != minutes
                || minutes < 0 || minutes > 2147483647 || !reminders.insert(static_cast<int>(minutes)).second) {
            error = "group reminders are invalid";
            return false;
        }
    }
    if (!validateRecurrenceMaster(master, error))
        return false;
    auto rule = master.value("recurrence").toObject();
    const auto dates = rule.value("pattern").toObject().value("dates").toArray();
    if (rule.value("frequency") != "yearly" || dates.isEmpty() || dates.size() > 366) {
        error = "group requires bounded yearly date pairs";
        return false;
    }
    std::map<int, QJsonObject> pairs;
    for (const auto &value : dates) {
        const auto pair = value.toObject();
        pairs[pair.value("month").toInt() * 32 + pair.value("day").toInt()] = pair;
    }
    QJsonArray selections;
    QJsonArray membership;
    for (const auto &[key, pair] : pairs) {
        selections.append(pair);
        QByteArray seed = uid.toUtf8();
        seed.append('\0');
        seed.append(QByteArray::number(key));
        const auto memberUid = QString::fromLatin1(QCryptographicHash::hash(seed, QCryptographicHash::Sha256).toHex()) + "@quickshell-group";
        membership.append(QJsonObject{{"uid", memberUid}, {"month", pair.value("month")}, {"day", pair.value("day")}});
    }
    rule["pattern"] = QJsonObject{{"dates", selections}};
    master["recurrence"] = rule;
    QJsonObject normalized;
    if (!normalizeRecurrenceMaster(master, normalized, error))
        return false;
    master = normalized;
    rule = master.value("recurrence").toObject();
    const bool allDay = master.value("allDay").toBool();
    const QTimeZone zone(master.value("timezone").toString().toUtf8());
    const auto start = QDateTime::fromString(master.value("start").toString(), Qt::ISODate);
    const auto end = QDateTime::fromString(master.value("end").toString(), Qt::ISODate);
    if (!allDay && (start.time().msec() != 0 || end.time().msec() != 0)) {
        error = "iCalendar recurrence requires whole-second timestamps";
        return false;
    }
    auto memberEnds = rule.value("ends").toObject();
    if (memberEnds.value("mode") == "count") {
        QJsonObject queryMaster;
        for (const auto key : {"uid", "start", "end", "allDay", "timezone", "recurrence"}) {
            if (master.contains(key))
                queryMaster[key] = master.value(key);
        }
        QJsonObject expanded;
        if (!expandCalendarRange(QJsonObject{{"requestId", "group-cutoff"}, {"rangeStartMs", -62135596800000.0},
                {"rangeEndMs", 253402300800000.0}, {"events", QJsonArray{queryMaster}}}, expanded, error))
            return false;
        const auto occurrences = expanded.value("occurrences").toArray();
        if (occurrences.size() != memberEnds.value("count").toInt() || !expanded.value("warnings").toArray().isEmpty()) {
            error = "group count exceeds supported dates/work limit";
            return false;
        }
        const auto lastStart = occurrences.last().toObject().value("start").toString();
        const auto cutoff = allDay ? QDate::fromString(lastStart, Qt::ISODate)
            : QDateTime::fromString(lastStart, Qt::ISODate).toTimeZone(zone).date();
        memberEnds = QJsonObject{{"mode", "date"}, {"date", cutoff.toString(Qt::ISODate)}};
    }
    const auto metadata = QJsonDocument(QJsonObject{{"version", 1}, {"master", master}, {"members", membership}}).toJson(QJsonDocument::Compact);
    if (metadata.size() > 128 * 1024) {
        error = "group metadata exceeds limit";
        return false;
    }
    QJsonArray members;
    size_t bytes = 0;
    for (const auto &value : membership) {
        auto member = value.toObject();
        auto memberMaster = master;
        auto memberRule = rule;
        memberRule["pattern"] = QJsonObject{{"dates", QJsonArray{QJsonObject{{"month", member.value("month")}, {"day", member.value("day")}}}}};
        memberRule["ends"] = memberEnds;
        memberMaster["uid"] = member.value("uid");
        memberMaster["recurrence"] = memberRule;
        if (!normalizeRecurrenceMaster(memberMaster, normalized, error, true))
            return false;
        Event event;
        event.uid = member.value("uid").toString().toStdString();
        event.summary = master.value("title").toString().toStdString();
        event.description = master.value("description").toString().toStdString();
        event.location = master.value("location").toString().toStdString();
        event.allDay = allDay;
        event.startTime = normalized.value("start").toString().toStdString();
        event.endTime = normalized.value("end").toString().toStdString();
        for (const auto &reminder : master.value("reminders").toArray())
            event.reminders.push_back(reminder.toObject().value("minutesBefore").toInt());
        event.recurrence = QJsonDocument(memberRule).toJson(QJsonDocument::Compact).toStdString();
        event.timezone = master.value("timezone").toString().toStdString();
        const auto source = serializeEvent(event);
        auto *calendar = source.empty() ? nullptr : icalparser_parse_string(source.c_str());
        auto *component = calendar ? icalcomponent_get_first_component(calendar, ICAL_VEVENT_COMPONENT) : nullptr;
        if (!component) {
            if (calendar)
                icalcomponent_free(calendar);
            error = "could not serialize group member";
            return false;
        }
        auto *property = icalcomponent_get_first_property(component, ICAL_X_PROPERTY);
        while (property) {
            auto *next = icalcomponent_get_next_property(component, ICAL_X_PROPERTY);
            if (QString::fromUtf8(icalproperty_get_x_name(property)).compare("X-QUICKSHELL-RECURRENCE", Qt::CaseInsensitive) == 0) {
                icalcomponent_remove_property(component, property);
                icalproperty_free(property);
            }
            property = next;
        }
        for (const auto &[name, data] : std::vector<std::pair<const char *, QByteArray>>{{"X-QUICKSHELL-GROUP-ID", uid.toUtf8()},
                {"X-QUICKSHELL-GROUP-RULE", metadata.toBase64()}}) {
            auto *item = icalproperty_new_x(data.constData());
            icalproperty_set_x_name(item, name);
            icalcomponent_add_property(component, item);
        }
        char *text = icalcomponent_as_ical_string_r(calendar);
        const QByteArray serialized = text ? QByteArray(text) : QByteArray{};
        if (text)
            icalmemory_free_buffer(text);
        icalcomponent_free(calendar);
        bytes += serialized.size() + member.value("uid").toString().toUtf8().size();
        if (serialized.isEmpty() || bytes > maxSourceBytes) {
            error = "serialized group exceeds transaction limit";
            return false;
        }
        member["ical"] = QString::fromUtf8(serialized);
        members.append(member);
    }
    result = QJsonObject{{"master", master}, {"members", members}};
    return true;
}

namespace {
bool validateSeriesSources(const std::map<std::string, std::string> &input, const QString &uid,
                           QJsonObject &result, QString &error) {
    error.clear();
    result = {};
    std::map<std::string, std::string> sources;
    QJsonObject metadata;
    for (const auto &[sourceUid, raw] : input) {
        using Calendar = std::unique_ptr<icalcomponent, decltype(&icalcomponent_free)>;
        Calendar calendar(icalparser_parse_string(raw.c_str()), icalcomponent_free);
        auto *event = calendar ? icalcomponent_get_first_component(calendar.get(), ICAL_VEVENT_COMPONENT) : nullptr;
        if (!event)
            continue;
        bool matches = false;
        int idCount = 0, ruleCount = 0, groupCount = 0;
        QByteArray encodedRule;
        for (auto *property = icalcomponent_get_first_property(event, ICAL_X_PROPERTY); property;
             property = icalcomponent_get_next_property(event, ICAL_X_PROPERTY)) {
            const auto name = QString::fromUtf8(icalproperty_get_x_name(property));
            if (!name.startsWith("X-QUICKSHELL-GROUP-", Qt::CaseInsensitive))
                continue;
            ++groupCount;
            if (name.compare("X-QUICKSHELL-GROUP-ID", Qt::CaseInsensitive) == 0) {
                ++idCount;
                matches = matches || QString::fromUtf8(icalproperty_get_x(property)) == uid;
            } else if (name.compare("X-QUICKSHELL-GROUP-RULE", Qt::CaseInsensitive) == 0) {
                ++ruleCount;
                encodedRule = icalproperty_get_x(property);
            }
        }
        if (!matches)
            continue;
        if (idCount != 1 || ruleCount != 1 || groupCount != 2 || encodedRule.size() > 192 * 1024
                || icalcomponent_get_next_component(calendar.get(), ICAL_VEVENT_COMPONENT)) {
            error = "group metadata or membership is inconsistent";
            return false;
        }
        const auto decodedRule = QByteArray::fromBase64Encoding(encodedRule, QByteArray::AbortOnBase64DecodingErrors);
        QJsonParseError parseError;
        const auto document = decodedRule ? QJsonDocument::fromJson(decodedRule.decoded, &parseError) : QJsonDocument{};
        const auto candidate = document.object();
        if (!decodedRule || parseError.error != QJsonParseError::NoError || !document.isObject()
                || candidate.size() != 3 || candidate.value("version") != 1
                || !candidate.value("master").isObject() || !candidate.value("members").isArray()
                || candidate.value("master").toObject().value("uid") != uid
                || (!metadata.isEmpty() && metadata != candidate)) {
            error = "group metadata is invalid or divergent";
            return false;
        }
        metadata = candidate;
        const auto parsed = parseCalendar(raw);
        if (!parsed.error.empty() || parsed.events.size() != 1) {
            error = "group member source is invalid";
            return false;
        }
        const auto memberUid = parsed.events.front().uid;
        if (memberUid != sourceUid || !sources.emplace(memberUid, raw).second) {
            error = "group member identity is invalid";
            return false;
        }
    }
    if (sources.empty()) {
        error = "group not found";
        return false;
    }
    QJsonObject expected;
    if (!buildSeriesGroup(metadata.value("master").toObject(), expected, error))
        return false;
    QJsonArray membership, members, revisions;
    for (const auto &value : expected.value("members").toArray()) {
        auto member = value.toObject();
        const auto memberUid = member.value("uid").toString().toStdString();
        const auto found = sources.find(memberUid);
        if (found == sources.end()) {
            error = "group member is missing";
            return false;
        }
        const auto generated = parseCalendar(member.value("ical").toString().toStdString());
        const auto current = parseCalendar(found->second);
        if (!generated.error.empty() || !current.error.empty() || generated.events.size() != 1 || current.events.size() != 1) {
            error = "group member source is invalid";
            return false;
        }
        const auto &a = generated.events.front();
        const auto &b = current.events.front();
        if (a.uid != b.uid || a.summary != b.summary || a.description != b.description || a.location != b.location
                || a.allDay != b.allDay || a.reminders != b.reminders
                || recurrenceSourceSignature(member.value("ical").toString().toStdString()) != recurrenceSourceSignature(found->second)) {
            error = "group member was edited externally; group is protected";
            return false;
        }
        auto identity = member;
        identity.remove("ical");
        membership.append(identity);
        const auto revision = QString::fromStdString(eventRevision(b));
        revisions.append(QJsonObject{{"uid", member.value("uid")}, {"revision", revision}});
        member["ical"] = QString::fromStdString(found->second);
        member["revision"] = revision;
        members.append(member);
    }
    if (sources.size() != static_cast<size_t>(members.size()) || metadata.value("master") != expected.value("master")
            || metadata.value("members") != membership) {
        error = "group membership is inconsistent or spoofed";
        return false;
    }
    const auto revision = QString::fromLatin1(QCryptographicHash::hash(QJsonDocument(revisions).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex());
    result = QJsonObject{{"master", expected.value("master")}, {"members", members}, {"revision", revision}};
    return true;
}

std::set<QString> groupIds(const Event &event, bool &tagged, int *propertyCount = nullptr) {
    std::set<QString> ids;
    int count = 0;
    tagged = false;
    using Calendar = std::unique_ptr<icalcomponent, decltype(&icalcomponent_free)>;
    Calendar calendar(event.ical.empty() ? nullptr : icalparser_parse_string(event.ical.c_str()), icalcomponent_free);
    for (auto *component = calendar ? icalcomponent_get_first_component(calendar.get(), ICAL_VEVENT_COMPONENT) : nullptr;
         component; component = icalcomponent_get_next_component(calendar.get(), ICAL_VEVENT_COMPONENT)) {
        for (auto *property = icalcomponent_get_first_property(component, ICAL_X_PROPERTY); property;
             property = icalcomponent_get_next_property(component, ICAL_X_PROPERTY)) {
            const auto name = QString::fromUtf8(icalproperty_get_x_name(property));
            tagged = tagged || name.startsWith("X-QUICKSHELL-GROUP-", Qt::CaseInsensitive);
            if (name.compare("X-QUICKSHELL-GROUP-ID", Qt::CaseInsensitive) == 0) {
                ++count;
                ids.insert(QString::fromUtf8(icalproperty_get_x(property)));
            }
        }
    }
    if (propertyCount)
        *propertyCount = count;
    return ids;
}
} // namespace

bool inspectSeriesSources(const std::map<std::string, std::string> &sources, const QString &uid,
                          QJsonObject &result, QString &error) {
    error.clear();
    result = {};
    return validateSeriesSources(sources, uid, result, error);
}

QString seriesSourceGroup(const Event &event, bool &tagged, bool &ambiguous) {
    int count = 0;
    const auto ids = groupIds(event, tagged, &count);
    ambiguous = tagged && (count != 1 || ids.size() != 1 || ids.begin()->isEmpty());
    return tagged && !ambiguous ? *ids.begin() : QString{};
}

bool inspectSeriesGroup(const std::string &directory, const QString &uid,
                        QJsonObject &result, QString &error) {
    error.clear();
    result = {};
    const fs::path root(directory);
    if (!validDirectory(root, error))
        return false;
    std::optional<std::string> pending;
    if (!readFile(root / journalName, pending, error, maxJournalBytes))
        return false;
    if (pending) {
        error = "group transaction recovery required";
        return false;
    }
    std::map<std::string, std::string> sources;
    std::map<std::string, fs::path> paths;
    std::error_code ec;
    fs::directory_iterator iterator(root, ec), end;
    for (; !ec && iterator != end; iterator.increment(ec)) {
        if (iterator->path().extension() != ".ics")
            continue;
        std::optional<std::string> raw;
        if (!readFile(iterator->path(), raw, error))
            return false;
        if (!raw)
            continue;
        const auto parsed = parseCalendar(*raw);
        for (const auto &event : parsed.events) {
            bool tagged;
            if (!groupIds(event, tagged).count(uid))
                continue;
            if (parsed.events.size() != 1 || !sources.emplace(event.uid, *raw).second) {
                error = "group member source or identity is invalid";
                return false;
            }
            paths[event.uid] = iterator->path();
        }
    }
    if (ec) {
        error = "could not scan group directory";
        return false;
    }
    if (!validateSeriesSources(sources, uid, result, error))
        return false;
    for (const auto &value : result.value("members").toArray()) {
        const auto memberUid = value.toObject().value("uid").toString().toStdString();
        if (paths[memberUid].filename() != memberPath(root, memberUid).filename()) {
            result = {};
            error = "group member path is invalid";
            return false;
        }
    }
    return true;
}

void reconstructSeriesGroups(std::vector<Event> &events, std::vector<std::string> &warnings) {
    std::map<QString, std::map<std::string, std::string>> groups;
    std::set<std::string> identities;
    for (auto &event : events) {
        identities.insert(event.uid);
        bool tagged;
        int idCount;
        const auto ids = groupIds(event, tagged, &idCount);
        if (!tagged)
            continue;
        event.readOnly = true;
        event.recurrence.clear();
        event.timezone.clear();
        if (idCount != 1) {
            warnings.push_back("group member " + event.uid + ": group identity is missing or ambiguous; protected");
            continue;
        }
        for (const auto &id : ids)
            groups[id][event.uid] = event.ical;
    }
    std::vector<Event> logical;
    std::set<std::string> consumed;
    for (const auto &[id, sources] : groups) {
        QJsonObject verified;
        QString error;
        if (!validateSeriesSources(sources, id, verified, error) || identities.count(id.toStdString())) {
            if (error.isEmpty())
                error = "logical group identity collides with another event";
            warnings.push_back("group " + id.toStdString() + ": " + error.toStdString() + "; members protected");
            continue;
        }
        const auto master = verified.value("master").toObject();
        Event event;
        event.uid = id.toStdString();
        event.summary = master.value("title").toString().toStdString();
        event.description = master.value("description").toString().toStdString();
        event.location = master.value("location").toString().toStdString();
        event.startTime = master.value("start").toString().toStdString();
        event.endTime = master.value("end").toString().toStdString();
        event.allDay = master.value("allDay").toBool();
        event.timezone = master.value("timezone").toString().toStdString();
        event.recurrence = QJsonDocument(master.value("recurrence").toObject()).toJson(QJsonDocument::Compact).toStdString();
        for (const auto &reminder : master.value("reminders").toArray())
            event.reminders.push_back(reminder.toObject().value("minutesBefore").toInt());
        QJsonArray members;
        for (const auto &value : verified.value("members").toArray()) {
            const auto member = value.toObject();
            members.append(QJsonObject{{"uid", member.value("uid")}, {"revision", member.value("revision")}});
            consumed.insert(member.value("uid").toString().toStdString());
        }
        event.seriesGroup = QJsonDocument(QJsonObject{{"version", 1}, {"members", members}}).toJson(QJsonDocument::Compact).toStdString();
        event.groupRevision = verified.value("revision").toString().toStdString();
        event.readOnly = false;
        logical.push_back(std::move(event));
    }
    events.erase(std::remove_if(events.begin(), events.end(), [&](const Event &event) { return consumed.count(event.uid); }), events.end());
    events.insert(events.end(), logical.begin(), logical.end());
}

bool mutateSeriesGroup(const std::string &directory, const std::string &output,
                       const QJsonObject &request, QString &error, bool &sourceCommitted) {
    error.clear();
    sourceCommitted = false;
    const fs::path root(directory);
    if (!validDirectory(root, error))
        return false;
    std::string lockError;
    CalendarLock lock(root, lockError);
    if (!lock.acquired()) {
        error = QString::fromStdString(lockError);
        return false;
    }
    const auto operation = request.value("operation").toString();
    const auto sourceId = request.value("sourceId").toString();
    if (!QStringList{"create", "update", "delete"}.contains(operation)) {
        error = "group request operation is invalid";
        return false;
    }
    if (!validCacheTarget(root, output, sourceId, error))
        return false;
    if (!recoverSeriesGroups(directory, error))
        return false;
    const auto event = request.value("event").toObject();
    const auto uid = operation == "delete" ? request.value("uid").toString() : event.value("uid").toString();
    QJsonObject current;
    bool exists = inspectSeriesGroup(directory, uid, current, error);
    bool ordinarySource = false;
    if (!exists && error == "group not found") {
        std::optional<std::string> raw;
        if (!readFile(memberPath(root, uid.toStdString()), raw, error))
            return false;
        if (raw) {
            const auto parsed = parseCalendar(*raw);
            if (!parsed.error.empty() || parsed.events.size() != 1 || parsed.events.front().uid != uid.toStdString()
                    || (!parsed.events.front().ical.empty() && parsed.events.front().recurrence.empty())) {
                error = "ordinary source is invalid or read-only";
                return false;
            }
            const auto revision = QString::fromStdString(eventRevision(parsed.events.front()));
            current = QJsonObject{{"revision", revision}, {"members", QJsonArray{QJsonObject{{"uid", uid},
                {"ical", QString::fromStdString(*raw)}, {"revision", revision}}}}};
            exists = true;
            ordinarySource = true;
            error.clear();
        }
    }
    if (operation == "create") {
        if (exists || error != "group not found") {
            if (exists)
                error = "group already exists";
            return false;
        }
        error.clear();
    } else if (!exists || request.value("revision").toString().isEmpty()
            || request.value("revision") != current.value("revision")) {
        if (exists)
            error = "group changed; reopen series";
        return false;
    }
    QJsonObject built;
    bool groupedTarget = false;
    std::string ordinaryGenerated;
    if (operation != "delete") {
        const auto rule = event.value("recurrence").toObject();
        groupedTarget = rule.value("frequency") == "yearly" && rule.value("pattern").toObject().value("dates").toArray().size() > 1;
        if (groupedTarget) {
            if (!buildSeriesGroup(event, built, error))
                return false;
        } else {
            Event target;
            std::string detail;
            if (!syncedEventFromJson(event, target, detail) || (ordinaryGenerated = serializeEvent(target)).empty()) {
                error = detail.empty() ? "could not serialize ordinary target" : QString::fromStdString(detail);
                return false;
            }
            built = QJsonObject{{"members", QJsonArray{QJsonObject{{"uid", uid}, {"ical", QString::fromStdString(ordinaryGenerated)}}}}};
        }
    }
    std::map<std::string, SeriesFileChange> changes;
    for (const auto &value : current.value("members").toArray()) {
        const auto member = value.toObject();
        const auto memberUid = member.value("uid").toString().toStdString();
        changes[memberUid] = {memberUid, member.value("ical").toString().toStdString(), {}};
    }
    std::string transitionSource;
    if (operation == "update" && ordinarySource && groupedTarget)
        transitionSource = current.value("members").toArray().first().toObject().value("ical").toString().toStdString();
    if (operation == "update" && !ordinarySource && groupedTarget) {
        const auto neutral = built.value("members").toArray().first().toObject().value("ical").toString().toStdString();
        const auto digest = [](const std::string &source) {
            return QCryptographicHash::hash(QByteArray::fromStdString(source), QCryptographicHash::Sha256);
        };
        std::set<std::string> targetUids;
        for (const auto &value : built.value("members").toArray())
            targetUids.insert(value.toObject().value("uid").toString().toStdString());
        std::map<std::string, QByteArray> opaque;
        std::set<QByteArray> signatures, surviving;
        for (const auto &[memberUid, change] : changes) {
            std::string merged, detail;
            if (!mergeEventSource(*change.before, neutral, merged, detail)) {
                error = QString::fromStdString(detail);
                return false;
            }
            const auto signature = digest(merged);
            opaque[memberUid] = signature;
            signatures.insert(signature);
            if (targetUids.count(memberUid))
                surviving.insert(signature);
        }
        if (signatures.size() == 1)
            transitionSource = *changes.begin()->second.before;
        const auto empty = digest(neutral);
        for (const auto &[memberUid, signature] : opaque) {
            if (!targetUids.count(memberUid) && signature != empty && !surviving.count(signature) && transitionSource.empty()) {
                error = "removed group members contain distinct opaque data; cannot update losslessly";
                return false;
            }
        }
    }
    if (operation == "update" && !ordinarySource && !groupedTarget) {
        std::optional<std::string> lossless;
        for (const auto &value : current.value("members").toArray()) {
            const auto source = value.toObject().value("ical").toString().toStdString();
            std::string merged, detail;
            if (!mergeEventSource(source, ordinaryGenerated, merged, detail)) {
                error = QString::fromStdString(detail);
                return false;
            }
            if (lossless && *lossless != merged) {
                error = "group members contain distinct opaque data; cannot collapse losslessly";
                return false;
            }
            lossless = std::move(merged);
        }
        built = QJsonObject{{"members", QJsonArray{QJsonObject{{"uid", uid}, {"ical", QString::fromStdString(*lossless)}}}}};
    }
    for (const auto &value : built.value("members").toArray()) {
        const auto member = value.toObject();
        const auto memberUid = member.value("uid").toString().toStdString();
        auto &change = changes[memberUid];
        change.uid = memberUid;
        std::string source = member.value("ical").toString().toStdString();
        if (change.before || !transitionSource.empty()) {
            std::string detail, merged;
            if (!mergeEventSource(change.before ? *change.before : transitionSource, source, merged, detail)) {
                error = QString::fromStdString(detail);
                return false;
            }
            source = std::move(merged);
        }
        change.after = std::move(source);
    }
    std::vector<SeriesFileChange> prepared;
    for (auto &[memberUid, change] : changes)
        prepared.push_back(std::move(change));
    if (!commitSeriesFiles(directory, prepared, error, sourceCommitted))
        return false;
    std::string detail;
    if (!rebuildSyncedCache(directory, output, sourceId.toStdString(), detail)) {
        error = "group committed but cache rebuild failed: " + QString::fromStdString(detail);
        return false;
    }
    return true;
}

bool recoverSeriesCache(const std::string &directory, const std::string &output,
                        const QString &sourceId, QString &error, bool &sourcesSafe) {
    error.clear();
    sourcesSafe = false;
    const fs::path root(directory);
    if (!validDirectory(root, error) || !validCacheTarget(root, output, sourceId, error))
        return false;
    std::string lockError;
    CalendarLock lock(root, lockError);
    if (!lock.acquired()) {
        error = QString::fromStdString(lockError);
        return false;
    }
    if (!recoverSeriesGroups(directory, error))
        return false;
    sourcesSafe = true;
    std::string detail;
    if (!rebuildSyncedCache(directory, output, sourceId.toStdString(), detail)) {
        error = "group sources recovered but cache rebuild failed: " + QString::fromStdString(detail);
        return false;
    }
    return true;
}

bool checkSeriesTarget(const std::string &directory, const std::string &output,
                       const QString &sourceId, QString &error) {
    error.clear();
    return validDirectory(directory, error) && validCacheTarget(directory, output, sourceId, error);
}
