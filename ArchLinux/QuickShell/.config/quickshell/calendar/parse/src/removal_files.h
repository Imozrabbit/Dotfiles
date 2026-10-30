#pragma once

#include "subscriptions.h"
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

// Small shared filesystem/process primitives; each backend owns its removal policy.
namespace CalendarRemoval {
struct Snapshot {
    QByteArray bytes;
    bool exists = false;
    mode_t mode = 0600;
};
inline bool property(const QString &unit, const QString &name, QString &value, QString &error) {
    QProcess process;
    process.start("systemctl", {"--user", "show", "--property=" + name, "--value", unit});
    if (!process.waitForStarted(5000) || !process.waitForFinished(10000)
        || process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        process.kill(); process.waitForFinished(5000);
        error = "Could not read " + name + " for " + unit; return false;
    }
    value = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    return true;
}
inline bool erase(const QString &path, QString &error) {
    if (::unlink(QFile::encodeName(path).constData()) == 0 || errno == ENOENT) return true;
    error = "Could not delete " + path + ": " + QString::fromLocal8Bit(strerror(errno)); return false;
}
inline bool move(const QString &from, const QString &to, QString &error) {
    if (syscall(SYS_renameat2, AT_FDCWD, QFile::encodeName(from).constData(), AT_FDCWD,
                QFile::encodeName(to).constData(), RENAME_NOREPLACE) == 0) return true;
    error = "Could not move " + from + ": " + QString::fromLocal8Bit(strerror(errno)); return false;
}
inline bool publish(const QString &path, const QByteArray &bytes, mode_t mode, QString &error) {
    if (!SubscriptionBackend::ensureDirectory(QFileInfo(path).path(), error)
        || !SubscriptionBackend::writeFile(path, bytes, error)) return false;
    if (mode != 0600 && ::chmod(QFile::encodeName(path).constData(), mode) != 0) {
        error = "Could not restore file mode: " + path; return false;
    }
    return true;
}
inline bool purge(const QString &path, QString &error) {
    std::error_code code;
    std::filesystem::remove_all(QFile::encodeName(path).constData(), code);
    if (!code) return true;
    error = path + ": " + QString::fromStdString(code.message()); return false;
}
inline QString watcherSignature(const QByteArray &bytes) {
    const auto text = QString::fromUtf8(bytes);
    const auto header = text.indexOf("\n[Path]\n");
    const auto end = text.indexOf("Unit=quickshell-calendar-import.service\n", header + 1);
    if (header < 0 || end < 0) return text;
    const auto first = header + 8;
    auto paths = text.mid(first, end - first).split('\n');
    paths.sort(); // Path order is immaterial when reconstructing a lost config's inventory.
    return text.left(first) + paths.join('\n') + text.mid(end);
}
} // namespace CalendarRemoval
