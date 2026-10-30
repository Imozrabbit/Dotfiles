#include "subscriptions.h"
#include "calendar_json.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QUuid>
#include <cerrno>
#include <cstdio>
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace SubscriptionBackend {
namespace {
constexpr qint64 inputLimit = 16 * 1024 * 1024;

struct Descriptor {
    int fd;
    ~Descriptor() { if (fd >= 0) close(fd); }
};

bool sameFile(const struct stat &a, const struct stat &b, bool renamed = false) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
           && a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec
           && (renamed || (a.st_ctim.tv_sec == b.st_ctim.tv_sec && a.st_ctim.tv_nsec == b.st_ctim.tv_nsec));
}

bool moveNew(const QString &from, const QString &to) {
    return syscall(SYS_renameat2, AT_FDCWD, QFile::encodeName(from).constData(), AT_FDCWD,
                   QFile::encodeName(to).constData(), RENAME_NOREPLACE) == 0;
}

bool consumeOriginal(int parent, const QString &parentPath, const QByteArray &name,
                     const struct stat &original, const QByteArray &bytes, QString &retained) {
    struct stat directory{}, namedDirectory{}, selected{};
    if (fstat(parent, &directory) != 0 || lstat(QFile::encodeName(parentPath).constData(), &namedDirectory) != 0
        || directory.st_dev != namedDirectory.st_dev || directory.st_ino != namedDirectory.st_ino
        || fstatat(parent, name.constData(), &selected, AT_SYMLINK_NOFOLLOW) != 0 || !sameFile(original, selected)) return false;
    const auto temporary = (".calendar-import-source-" + QUuid::createUuid().toString(QUuid::Id128)).toUtf8();
    if (mkdirat(parent, temporary.constData(), 0700) != 0) return false;
    Descriptor claim{openat(parent, temporary.constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)};
    const auto claimPath = parentPath + '/' + QString::fromUtf8(temporary);
    bool removed = false;
    if (claim.fd >= 0 && ::renameat2(parent, name.constData(), claim.fd, "source.ics", RENAME_NOREPLACE) == 0) {
        struct stat claimed{};
        QByteArray claimedBytes;
        QString error;
        const auto anchor = "/proc/" + QString::number(getpid()) + "/fd/" + QString::number(claim.fd) + "/source.ics";
        const bool matches = fstatat(claim.fd, "source.ics", &claimed, AT_SYMLINK_NOFOLLOW) == 0
                             && sameFile(original, claimed, true) && readFile(anchor, claimedBytes, error, false, inputLimit)
                             && claimedBytes == bytes;
        removed = matches && unlinkat(claim.fd, "source.ics", 0) == 0;
        if (!removed && ::renameat2(claim.fd, "source.ics", parent, name.constData(), RENAME_NOREPLACE) != 0)
            retained = claimPath;
    }
    if (unlinkat(parent, temporary.constData(), AT_REMOVEDIR) != 0) retained = claimPath;
    return removed && retained.isEmpty();
}

QString parseReason(const std::string &detail) {
    const auto text = QString::fromStdString(detail);
    if (text.contains("UID")) return "Import failed: invalid event identifier.";
    if (text.contains("TZID")) return "Import failed: unknown time zone.";
    if (text.contains("date") || text.contains("time") || text.contains("DTSTART") || text.contains("duration"))
        return "Import failed: invalid event date or duration.";
    return "Import failed: invalid ICS data.";
}
} // namespace

bool importLocal(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease;
    QJsonObject registry;
    QByteArray before;
    if (!lease.acquire(p, error) || !loadRegistry(p, registry, error)
        || !readFile(p.data + "/profiles.json", before, error)) return false;
    if (QJsonDocument::fromJson(before).object() != registry) {
        error = "Import failed: calendar settings changed."; return false;
    }
    const auto profile = request.value("profile").toObject();
    const auto id = profile.value("id").toString();
    if (profile.size() != 5 || !validId(id) || profile.value("type") != "imported"
        || !profile.value("visible").isBool() || !profile.value("name").isString()
        || profile.value("name").toString().trimmed().isEmpty()
        || !QRegularExpression("^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$").match(profile.value("color").toString()).hasMatch()) {
        error = "Import failed: invalid calendar settings."; return false;
    }
    auto profiles = registry.value("profiles").toArray();
    for (const auto &value : profiles) if (value.toObject().value("id") == id) {
        error = "Calendar ID already exists."; return false;
    }
    const auto destination = p.data + '/' + id;
    const auto cache = p.data + '/' + id + ".json";
    struct stat occupied{};
    for (const auto &path : {destination, cache}) {
        if (lstat(QFile::encodeName(path).constData(), &occupied) == 0 || errno != ENOENT) {
            error = "Import failed: calendar files already exist."; return false;
        }
    }
    const auto selected = request.value("source").toString();
    const QFileInfo info(selected);
    const auto parent = QDir(info.absolutePath()).canonicalPath();
    const auto data = QDir(p.data).canonicalPath();
    const auto lexical = QDir::cleanPath(selected);
    if (!QDir::isAbsolutePath(selected) || selected.contains(QChar::Null) || parent.isEmpty()
        || info.suffix().compare("ics", Qt::CaseInsensitive) != 0 || data.isEmpty()
        || parent == data || parent.startsWith(data + '/') || lexical.startsWith(data + '/')) {
        error = "Choose one ICS file outside managed calendar storage."; return false;
    }
    for (const auto &value : profiles) {
        const auto collection = QDir(p.data + '/' + value.toObject().value("id").toString()).canonicalPath();
        if (!collection.isEmpty() && (parent == collection || parent.startsWith(collection + '/'))) {
            error = "Choose an ICS file outside existing calendar collections."; return false;
        }
    }
    Descriptor parentHandle{open(QFile::encodeName(parent).constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)};
    const auto filename = QFile::encodeName(info.fileName());
    const int descriptor = parentHandle.fd < 0 ? -1 : openat(parentHandle.fd, filename.constData(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    QFile original;
    if (descriptor < 0 || !original.open(descriptor, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
        if (descriptor >= 0) close(descriptor);
        error = "Import failed: file could not be read."; return false;
    }
    struct stat stamp{}, afterRead{};
    if (fstat(descriptor, &stamp) != 0 || !S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid() || stamp.st_nlink != 1) {
        error = "Choose an owned ICS file, not a link or folder."; return false;
    }
    if (stamp.st_size < 0 || stamp.st_size > inputLimit) {
        error = "Import failed: file exceeds 16 MiB."; return false;
    }
    const auto bytes = original.read(inputLimit + 1);
    if (original.error() != QFileDevice::NoError || bytes.size() != stamp.st_size
        || fstat(descriptor, &afterRead) != 0 || !sameFile(stamp, afterRead)) {
        error = "Import failed: source changed while reading."; return false;
    }
    QTemporaryDir staging(p.data + "/.import-local-" + id + "-XXXXXX");
    if (!staging.isValid()) { error = "Import failed: storage is unavailable."; return false; }
    if (!writeFile(staging.path() + "/source.ics", bytes, error, true)) return false;
    QByteArray copied;
    if (!readFile(staging.path() + "/source.ics", copied, error, false, inputLimit)) return false;
    const auto parsed = parseCalendar(std::string_view(copied.constData(), size_t(copied.size())));
    if (!parsed.error.empty()) { error = parseReason(parsed.error); return false; }
    const auto json = QByteArray::fromStdString(serializeCalendar(parsed.events, id.toStdString()));
    if (!writeFile(staging.path() + "/pending.json", json, error, true)) return false;
    struct stat stagedDirectory{}, stagedSource{}, stagedCache{};
    if (lstat(QFile::encodeName(staging.path()).constData(), &stagedDirectory) != 0
        || lstat(QFile::encodeName(staging.path() + "/source.ics").constData(), &stagedSource) != 0
        || lstat(QFile::encodeName(staging.path() + "/pending.json").constData(), &stagedCache) != 0) {
        error = "Import failed: staged files changed."; return false;
    }
    QByteArray current;
    if (!readFile(p.data + "/profiles.json", current, error) || current != before) {
        error = "Import failed: calendar settings changed."; return false;
    }
    if (!moveNew(staging.path(), destination)) {
        error = "Import failed: calendar files already exist."; return false;
    }
    staging.setAutoRemove(false);
    bool cachePublished = false;
    const auto rollback = [&] {
        // Claim before verifying: a pathname replacement must never be purged.
        QTemporaryDir recovery(p.data + "/.import-local-rollback-" + id + "-XXXXXX");
        if (!recovery.isValid()) { error += " Cleanup incomplete: " + destination; return false; }
        const auto collection = recovery.path() + "/collection";
        const auto cacheFile = recovery.path() + "/cache.json";
        const bool claimedSource = moveNew(destination, collection);
        if (claimedSource) recovery.setAutoRemove(false);
        const bool claimedCache = cachePublished && moveNew(cache, cacheFile);
        if (claimedCache) recovery.setAutoRemove(false);
        struct stat directory{}, sourceStamp{}, cacheStamp{};
        QByteArray currentSource, currentCache;
        QString ignored;
        QStringList expected{"source.ics"};
        if (!cachePublished) expected.prepend("pending.json");
        bool owned = claimedSource && (!cachePublished || claimedCache)
                     && lstat(QFile::encodeName(collection).constData(), &directory) == 0
                     && directory.st_dev == stagedDirectory.st_dev && directory.st_ino == stagedDirectory.st_ino
                     && QDir(collection).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDir::Name) == expected
                     && lstat(QFile::encodeName(collection + "/source.ics").constData(), &sourceStamp) == 0
                     && sameFile(stagedSource, sourceStamp, true)
                     && readFile(collection + "/source.ics", currentSource, ignored, false, inputLimit) && currentSource == bytes;
        const auto claimedJson = cachePublished ? cacheFile : collection + "/pending.json";
        owned = owned && lstat(QFile::encodeName(claimedJson).constData(), &cacheStamp) == 0
                && sameFile(stagedCache, cacheStamp, true)
                && readFile(claimedJson, currentCache, ignored, false, 64 * 1024 * 1024) && currentCache == json;
        if (owned) {
            if (!QDir(recovery.path()).removeRecursively()) error += " Cleanup incomplete: " + recovery.path();
        } else {
            bool restored = true;
            if (claimedCache && !moveNew(cacheFile, cache)) restored = false;
            if (claimedSource && !moveNew(collection, destination)) restored = false;
            error += " Cleanup incomplete: " + (restored ? destination : recovery.path());
            if (restored) (void)QDir().rmdir(recovery.path());
        }
        return false;
    };
    if (!moveNew(destination + "/pending.json", cache)) {
        error = "Import failed: cache could not be published."; return rollback();
    }
    cachePublished = true;
    if (!readFile(p.data + "/profiles.json", current, error) || current != before) {
        error = "Import failed: calendar settings changed."; return rollback();
    }
    profiles.append(profile);
    registry["profiles"] = profiles;
    QSaveFile output(p.data + "/profiles.json");
    const auto metadata = QJsonDocument(registry).toJson();
    if (!output.open(QIODevice::WriteOnly) || !output.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)
        || output.write(metadata) != metadata.size() || !output.commit()) {
        error = "Import failed: calendar settings could not be saved."; return rollback();
    }
    result = {{"ok", true}, {"id", id}};
    QString retained;
    if (!consumeOriginal(parentHandle.fd, parent, filename, stamp, bytes, retained)) {
        result["cleanupWarning"] = true;
        result["message"] = retained.isEmpty() ? "Imported; original file could not be deleted." : "Imported; source cleanup incomplete: " + retained;
    }
    return true;
}

bool readImported(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    Lease lease;
    QJsonObject registry;
    if (!lease.acquire(p, error, true) || !loadRegistry(p, registry, error)) return false;
    const auto id = request.value("id").toString();
    bool imported = false;
    for (const auto &value : registry.value("profiles").toArray())
        if (value.toObject().value("id") == id && value.toObject().value("type") == "imported") imported = true;
    if (!validId(id) || !imported) { error = "Imported calendar not found."; return false; }
    const auto path = p.data + '/' + id + "/source.ics";
    struct stat stamp{};
    if (lstat(QFile::encodeName(path).constData(), &stamp) != 0 && errno == ENOENT) {
        error = "Calendar file missing."; return false;
    }
    QByteArray bytes;
    if (!readFile(path, bytes, error, false, inputLimit)) { error = "Calendar file invalid."; return false; }
    const auto parsed = parseCalendar(std::string_view(bytes.constData(), size_t(bytes.size())));
    if (!parsed.error.empty()) { error = "Calendar file invalid."; return false; }
    const auto text = QByteArray::fromStdString(serializeCalendar(parsed.events, id.toStdString()));
    QByteArray existing;
    const auto cache = p.data + '/' + id + ".json";
    if (!readFile(cache, existing, error, true, 64 * 1024 * 1024)
        || (existing != text && !writeFile(cache, text, error))) {
        error = "Calendar cache unavailable."; return false;
    }
    result = {{"ok", true}, {"id", id}, {"text", QString::fromUtf8(text)}};
    return true;
}
} // namespace SubscriptionBackend
