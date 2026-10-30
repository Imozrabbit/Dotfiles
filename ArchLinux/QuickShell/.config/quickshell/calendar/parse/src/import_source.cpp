#include "import_source.h"
#include "calendar_lock.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QUrl>
#include <cerrno>
#include <csignal>
#include <dirent.h>
#include <iostream>
#include <set>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>

namespace {
constexpr qint64 inputLimit = 16 * 1024 * 1024;
const QByteArray ownerMarker("quickshell-calendar-import-v1\n");

struct FileHandle {
    explicit FileHandle(int descriptor) : fd(descriptor) {}
    ~FileHandle() {
        if (fd >= 0)
            close(fd);
    }
    FileHandle(const FileHandle &)            = delete;
    FileHandle &operator=(const FileHandle &) = delete;
    int fd;
};

QString anchor(int descriptor) {
    return "/proc/" + QString::number(getpid()) + "/fd/" + QString::number(descriptor);
}

bool ownedDirectory(const QString &path, struct stat &stamp) {
    return lstat(QFile::encodeName(path).constData(), &stamp) == 0 && S_ISDIR(stamp.st_mode) && stamp.st_uid == geteuid() && (stamp.st_mode & 0777) == 0700;
}

bool sameDirectory(const QString &path, const struct stat &stamp) {
    struct stat current{};
    return ownedDirectory(path, current) && current.st_dev == stamp.st_dev && current.st_ino == stamp.st_ino;
}

bool markedJob(const QString &path) {
    const QFileInfo marker(path + "/owner");
    if (!marker.isFile() || marker.isSymLink() || marker.ownerId() != geteuid() || marker.size() != ownerMarker.size())
        return false;
    QFile file(marker.filePath());
    return file.open(QIODevice::ReadOnly) && file.readAll() == ownerMarker;
}

bool cleanJob(int base, int job, const QByteArray &name) {
    // Never recurse or chmod: an unexpected entry preserves the whole job/markers.
    DIR *directory = fdopendir(dup(job));
    if (!directory)
        return false;
    rewinddir(directory);
    const std::set<std::string> allowed{"source.ics", "pending.json", "owner", ".calendar-sync.lock"};
    std::set<std::string> entries;
    bool valid = true;
    errno      = 0;
    while (const dirent *entry = readdir(directory)) {
        const std::string filename(entry->d_name);
        if (filename == "." || filename == "..")
            continue;
        struct stat stamp{};
        if (!allowed.count(filename) || fstatat(job, filename.c_str(), &stamp, AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(stamp.st_mode) || stamp.st_uid != geteuid()) {
            valid = false;
            break;
        }
        entries.insert(filename);
    }
    valid = valid && errno == 0;
    closedir(directory);
    if (!valid)
        return false;
    for (const char *file : {"source.ics", "pending.json"}) {
        if (entries.count(file) && unlinkat(job, file, 0) != 0)
            return false;
    }
    bool removedMarkers = true;
    for (const char *file : {"owner", ".calendar-sync.lock"}) {
        if (entries.count(file) && unlinkat(job, file, 0) != 0) {
            removedMarkers = false;
            break;
        }
    }
    if (removedMarkers && unlinkat(base, name.constData(), AT_REMOVEDIR) == 0)
        return true;
    // A concurrent unexpected file can prevent rmdir; retain recognizable ownership.
    FileHandle marker(openat(job, "owner", O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600));
    if (marker.fd >= 0)
        (void)write(marker.fd, ownerMarker.constData(), static_cast<size_t>(ownerMarker.size()));
    FileHandle lock(openat(job, ".calendar-sync.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600));
    return false;
}

void childDiesWithParent(QProcess &process, rlim_t fileLimit = 0, int output = -1) {
    const pid_t parent = getpid();
    process.setChildProcessModifier([parent, fileLimit, output] {
        if (prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent)
            _exit(1);
        const struct rlimit noCore{0, 0};
        if (setrlimit(RLIMIT_CORE, &noCore) != 0)
            _exit(1);
        if (fileLimit > 0) {
            const struct rlimit maximum{fileLimit, fileLimit};
            if (setrlimit(RLIMIT_FSIZE, &maximum) != 0)
                _exit(1);
        }
        if (output >= 0 && dup2(output, STDOUT_FILENO) < 0)
            _exit(1);
    });
    process.setStandardOutputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
}

bool runProcess(QProcess &process, int timeout) {
    if ((process.state() == QProcess::Starting && !process.waitForStarted(5000)) || process.error() == QProcess::FailedToStart || (process.state() != QProcess::NotRunning && !process.waitForFinished(timeout))) {
        process.kill();
        process.waitForFinished(5000);
        return false;
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

bool download(const QUrl &url, int job) {
    // Source is sent through stdin, not argv or a persistent URL/credential file.
    const QString scheme    = url.scheme().toLower();
    const QString protocols = scheme == "https" ? "=https" : "=http,https";
    FileHandle output(openat(job, "source.ics", O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600));
    if (output.fd < 0)
        return false;
    QProcess process;
    childDiesWithParent(process, static_cast<rlim_t>(inputLimit), output.fd);
    process.start("curl", {"--disable", "--silent", "--fail", "--compressed", "--location", "--max-redirs", "5",
                           "--proto", protocols, "--proto-redir", protocols, "--connect-timeout", "10", "--max-time", "30",
                           "--max-filesize", QString::number(inputLimit), "--output", "-", "--config", "-"});
    if (!process.waitForStarted(5000))
        return false;
    QByteArray encoded = url.toEncoded();
    encoded.replace("\\", "\\\\");
    encoded.replace("\"", "\\\"");
    process.write("url = \"" + encoded + "\"\n");
    process.closeWriteChannel();
    struct stat stamp{};
    return runProcess(process, 35000) && fstat(output.fd, &stamp) == 0 && stamp.st_size <= inputLimit;
}
} // namespace

int runImportSession(const char *dataDirectory, const char *sourceId, const char *kind) {
    auto fail               = [](const char *message) { std::cerr << message << '\n'; return 1; };
    const QString mode      = QString::fromUtf8(kind);
    const QString id        = QString::fromUtf8(sourceId);
    const QString directory = QString::fromUtf8(dataDirectory);
    if ((mode != "file" && mode != "url") || !QRegularExpression("^[a-z0-9][a-z0-9_-]*$").match(id).hasMatch() || !QDir::isAbsolutePath(directory) || directory.contains(QChar::Null))
        return fail("Invalid import request");
    QFile input;
    if (!input.open(stdin, QIODevice::ReadOnly))
        return fail("Could not read import request");
    const QByteArray line = input.readLine(16385);
    QJsonParseError error;
    const QJsonDocument request = QJsonDocument::fromJson(line, &error);
    if (line.size() > 16384 || error.error != QJsonParseError::NoError || !request.isObject() || request.object().size() != 1 || !request.object().value("source").isString())
        return fail("Invalid import source");
    QString source = request.object().value("source").toString();
    QUrl url;
    if (source.isEmpty() || source.contains(QChar::Null))
        return fail("Choose an ICS file, folder or direct calendar link");
    if (mode == "url") {
        source = source.trimmed();
        if (QRegularExpression("[\\x00-\\x20\\x7f]").match(source).hasMatch())
            return fail("Calendar link contains invalid whitespace or control characters");
        url = QUrl(source, QUrl::StrictMode);
        if (url.scheme().compare("webcal", Qt::CaseInsensitive) == 0 || url.scheme().compare("webcals", Qt::CaseInsensitive) == 0)
            url.setScheme("https");
        if (!url.isValid() || url.host().isEmpty() || url.authority().contains('@') || !url.fragment().isEmpty() || (url.scheme().toLower() != "https" && url.scheme().toLower() != "http"))
            return fail("Use a direct HTTP(S) calendar link without login credentials or fragments");
    }
    const QString data = QDir(directory).canonicalPath();
    if (data.isEmpty())
        return fail("Calendar data directory is unavailable");
    const QString base = data + "/.imports";
    if (::mkdir(QFile::encodeName(base).constData(), 0700) != 0 && errno != EEXIST)
        return fail("Could not prepare private import directory");
    struct stat baseStamp{};
    if (!ownedDirectory(base, baseStamp))
        return fail("Import directory must be a real, owned directory with mode 0700");
    FileHandle baseHandle(open(QFile::encodeName(base).constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    struct stat openedBase{};
    if (baseHandle.fd < 0 || fstat(baseHandle.fd, &openedBase) != 0 || openedBase.st_dev != baseStamp.st_dev || openedBase.st_ino != baseStamp.st_ino)
        return fail("Import directory changed while opening it");
    const QString baseAnchor = anchor(baseHandle.fd);
    std::string lockError;
    // Serialize orphan cleanup only; every marked active job holds its own lease.
    {
        CalendarLock baseLock(baseAnchor.toStdString(), lockError);
        if (!baseLock.acquired())
            return fail("Another import is preparing its workspace; try again");
        for (const QFileInfo &entry : QDir(baseAnchor).entryInfoList({"import-*"}, QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks)) {
            struct stat stamp{};
            if (!ownedDirectory(entry.filePath(), stamp) || !markedJob(entry.filePath()))
                continue;
            const QFileInfo lock(entry.filePath() + "/.calendar-sync.lock");
            if (!lock.isFile() || lock.isSymLink() || lock.ownerId() != geteuid())
                continue;
            CalendarLock lease(entry.filePath().toStdString(), lockError);
            FileHandle oldJob(openat(baseHandle.fd, QFile::encodeName(entry.fileName()).constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
            if (lease.acquired() && oldJob.fd >= 0 && sameDirectory(base, baseStamp) && sameDirectory(entry.filePath(), stamp))
                cleanJob(baseHandle.fd, oldJob.fd, QFile::encodeName(entry.fileName()));
        }
    }
    QTemporaryDir job(baseAnchor + "/import-XXXXXXXX");
    job.setAutoRemove(false);
    const QByteArray jobName = QFile::encodeName(QFileInfo(job.path()).fileName());
    const QString visibleJob = base + "/" + QString::fromLocal8Bit(jobName);
    FileHandle jobHandle(openat(baseHandle.fd, jobName.constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    struct stat jobStamp{};
    if (!job.isValid() || jobHandle.fd < 0 || !ownedDirectory(job.path(), jobStamp))
        return fail("Could not create private import workspace");
    const QString jobAnchor = anchor(jobHandle.fd);
    CalendarLock lease(jobAnchor.toStdString(), lockError);
    auto finish = [&](int status) {
        if (!sameDirectory(base, baseStamp) || !sameDirectory(visibleJob, jobStamp) || !cleanJob(baseHandle.fd, jobHandle.fd, jobName))
            return fail("Import workspace cleanup failed; preserve .imports for inspection");
        return status;
    };
    if (!lease.acquired())
        return finish(fail("Could not lock import workspace"));
    QFile marker(jobAnchor + "/owner");
    if (!marker.open(QIODevice::WriteOnly | QIODevice::NewOnly) || marker.write(ownerMarker) != ownerMarker.size())
        return finish(fail("Could not mark import workspace"));
    marker.close();
    if (mode == "url") {
        if (!download(url, jobHandle.fd))
            return finish(fail("Could not download calendar: check the direct link, network and 16 MiB limit; login is not supported"));
        source = jobAnchor + "/source.ics";
    }
    if (!sameDirectory(base, baseStamp) || !sameDirectory(visibleJob, jobStamp))
        return finish(fail("Import workspace changed during download"));
    QProcess converter;
    childDiesWithParent(converter);
    converter.start(QCoreApplication::applicationFilePath(), {"prepare", source, jobAnchor + "/pending.json", id});
    if (!runProcess(converter, 65000))
        return finish(fail("Could not import source: expected a valid ICS file or folder"));
    if (!sameDirectory(base, baseStamp) || !sameDirectory(visibleJob, jobStamp))
        return finish(fail("Import workspace changed during conversion"));
    const QByteArray ready = QJsonDocument(QJsonObject{{"directory", visibleJob}, {"staged", jobAnchor + "/pending.json"}}).toJson(QJsonDocument::Compact);
    std::cout << ready.constData() << '\n'
              << std::flush;
    // Hold the lease while QML commits; EOF after shell shutdown also cleans the job.
    const QByteArray command = input.readLine(64).trimmed();
    return finish(command.isEmpty() || command == "finish" ? 0 : fail("Invalid import completion request"));
}
