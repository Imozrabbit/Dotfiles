#include "subscriptions.h"
#include "caldav.h"
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSet>
#include <iostream>
#include <sys/resource.h>

namespace SubscriptionBackend {
namespace {
bool present(const QString &path) { return QFileInfo::exists(path) || QFileInfo(path).isSymLink(); }

bool recoveryPending(const Paths &p) {
    const auto state = QFileInfo(p.state).path();
    for (const auto &name : QStringList{"group-recovery", "group-resolution.json", "subscriptions/change.json"})
        if (present(state + '/' + name)) return true;
    const QDir caldav(state + "/caldav");
    if (!caldav.entryList({"conversion-*.json", "attachment-*.json", "remote-delete-*.json"},
                         QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot).isEmpty()) return true;
    return false;
}

bool plan(QJsonObject &result, QString &error, bool verifyEffective) {
    const auto p = paths();
    const auto c = CalDavBackend::paths();
    Config subscriptions;
    CalDavBackend::Config caldav;
    QJsonObject registry;
    if (recoveryPending(p)) { error = "Calendar recovery is pending; no deployment was planned"; return false; }
    if (!loadRegistry(p, registry, error) || !loadConfig(p, subscriptions, error)
        || !CalDavBackend::loadConfig(c, caldav, error)) return false;
    QMap<QString, QString> profiles, configured;
    for (const auto &value : registry.value("profiles").toArray()) {
        const auto profile = value.toObject();
        profiles[profile.value("id").toString()] = profile.value("type").toString();
    }
    for (const auto &record : subscriptions.records) configured[record.id] = "subscription";
    for (const auto &record : caldav.records) {
        if (configured.contains(record.id)) { error = "Calendar ID belongs to two sync backends"; return false; }
        configured[record.id] = "synced";
    }
    for (auto it = profiles.begin(); it != profiles.end(); ++it) {
        if ((it.value() == "synced" || it.value() == "subscription") && configured.value(it.key()) != it.value()) {
            error = "Calendar sync layout is unmanaged; migration requires separate review"; return false;
        }
        const QDir collection(p.data + '/' + it.key());
        if (!collection.entryList({".calendar-series-*"}, QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot).isEmpty()) {
            error = "Calendar series recovery is pending"; return false;
        }
    }
    for (auto it = configured.begin(); it != configured.end(); ++it) if (profiles.value(it.key()) != it.value()) {
        error = "Calendar profiles and managed sync settings differ"; return false;
    }
    auto definitions = unitDefinitions(p, subscriptions);
    const auto caldavDefinitions = CalDavBackend::unitDefinitions(c, caldav);
    for (auto it = caldavDefinitions.begin(); it != caldavDefinitions.end(); ++it) {
        if (definitions.contains(it.key()) && definitions.value(it.key()) != it.value()) {
            error = "Managed sync backends disagree about shared units"; return false;
        }
        definitions[it.key()] = it.value();
    }
    if (verifyEffective && !definitions.isEmpty()) {
        if (!command("/bin/sh", {p.broker, "verify-group-guard"}, 15000)) {
            error = "Effective calendar recovery guard differs; no service was started"; return false;
        }
        if (!caldav.records.isEmpty() && !CalDavBackend::verifyManagedDaemon(c, error)) return false;
    }
    QJsonObject files;
    for (auto it = definitions.begin(); it != definitions.end(); ++it) files[it.key()] = QString::fromUtf8(it.value());
    QSet<QString> names;
    for (const auto &name : unitNames(subscriptions)) names.insert(name);
    if (!caldav.records.isEmpty()) names.insert("pimsync.service");
    for (const auto &record : caldav.records) {
        names.insert("quickshell-calendar-caldav-" + record.id + ".timer");
        names.insert("quickshell-calendar-caldav@" + record.id + ".service");
    }
    auto units = names.values();
    units.sort();
    result = {{"ok", true}, {"schema", 1}, {"dataSchema", 1}, {"files", files}, {"units", QJsonArray::fromStringList(units)}};
    return true;
}
} // namespace

int deploymentPlan(bool verifyEffective) {
    const struct rlimit noCore{0, 0};
    QString error;
    QJsonObject result;
    if (setrlimit(RLIMIT_CORE, &noCore) != 0 || !plan(result, error, verifyEffective)) {
        result = {{"ok", false}, {"field", "storage"}, {"message", error.isEmpty() ? QString("Could not inspect Calendar deployment safely") : error}};
    }
    std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << '\n';
    return result.value("ok").toBool() ? 0 : 1;
}
} // namespace SubscriptionBackend
