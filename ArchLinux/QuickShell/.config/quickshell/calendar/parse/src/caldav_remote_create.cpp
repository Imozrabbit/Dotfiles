#include "caldav_remote.h"
#include <QFileInfo>
#include <algorithm>
#include <cmath>

namespace CalDavBackend {
using namespace SubscriptionBackend;

bool createRemoteAndAdd(const Paths &p, const QJsonObject &request, QJsonObject &result, QString &error) {
    const auto profile = request.value("profile").toObject();
    const auto id = profile.value("id").toString();
    const auto name = request.value("remoteName").toString(), identifier = request.value("collectionId").toString();
    const auto home = request.value("homeHref").toString();
    auto target = recordFromJson(request);
    target.id = id;
    result = {{"id", id}, {"remoteCreated", false}, {"creationUncertain", false}};
    auto reject = [&](const QString &field, const QString &message) {
        result["field"] = field; error = message; return false;
    };
    if (!validId(id)) return reject("id", "Choose a valid unused local calendar ID");
    if (!validProfile(profile) || profile.value("type") != "synced") return reject("storage", "Use a valid synced calendar profile");
    if (!validId(identifier)) return reject("collectionId", "Use a lowercase collection identifier, at most 128 characters, with digits, hyphens or underscores");
    if (!validRemoteName(name)) return reject("remoteName", "Use a nonempty single-line remote name, at most 512 characters, without controls");
    const double interval = request.value("intervalSeconds").toDouble(300);
    if ((request.contains("intervalSeconds") && !request.value("intervalSeconds").isDouble()) || !std::isfinite(interval)
        || std::floor(interval) != interval || interval < 300 || interval > 2147483647)
        return reject("interval", "Refresh interval must be at least 5 minutes, in whole seconds");
    target.interval = int(interval);
    {
        // Hold the normal settings lease across validation and remote creation, not nested Add.
        Lease lease;
        Config config;
        QJsonObject registry;
        if (!lease.acquire(p, error) || !loadConfig(p, config, error) || !loadRegistry(p, registry, error)
            || !conversionAllowed(p, id, error)) return false;
        if (request.value("expectedRevision") != revision(config.original) || !request.contains("expectedProfile")
            || !request.value("expectedProfile").isNull()) return reject("storage", "Calendar settings changed; reopen the form before creating");
        const auto profiles = registry.value("profiles").toArray();
        if (std::any_of(profiles.begin(), profiles.end(), [&](const auto &value) { return value.toObject().value("id") == id; })
            || std::any_of(config.records.begin(), config.records.end(), [&](const auto &record) { return record.id == id; }))
            return reject("id", "Choose an unused local calendar ID; existing local calendars cannot be attached here");
        QStringList collisions{p.data + '/' + id, p.data + '/' + id + ".json", p.data + '/' + id + ".sync.json"};
        for (const auto &suffix : QStringList{"", "-wal", "-shm", "-journal"}) collisions.append(p.status + '/' + target.pair() + ".status" + suffix);
        for (const auto &path : collisions) if (QFileInfo::exists(path) || QFileInfo(path).isSymLink())
            return reject("id", "Calendar ID collides with retained local files or pair state");
        if (!command("/bin/sh", {p.broker, "check-recovery"}, 10000))
            return reject("storage", "Resolve the pending calendar operation before creating");
        if (!validateConnection(target, error)) return false;
        const auto outcome = createRemoteCollection(target, home, name, identifier, error);
        result["remoteId"] = target.remoteId; result["remoteHref"] = target.remoteHref; result["homeHref"] = home;
        if (outcome == RemoteOutcome::Refused) {
            if (error.contains("already exists") || error.contains("HTTP 412")) result["field"] = "collectionId";
            return false;
        }
        if (outcome == RemoteOutcome::Uncertain) {
            RemoteSnapshot snapshot;
            QString inspected;
            const auto presence = inspectRemote(target, home, snapshot, inspected);
            result["creationUncertain"] = true;
            result["remotePresent"] = presence == RemotePresence::Present;
            return reject("storage", "Remote creation outcome is uncertain; nothing was added locally. Connect and select the exact calendar before Add; do not repeat creation automatically.");
        }
        result["remoteCreated"] = true;
        RemoteSnapshot verified;
        if (!snapshotRemote(target, verified, error) || verified.homeHref != home) {
            error = "Remote calendar created; adding it locally failed. Connect and select the created calendar to retry Add. " + error;
            return false;
        }
    }
    auto add = request;
    add["url"] = target.url; add["remoteId"] = target.remoteId; add["remoteHref"] = target.remoteHref;
    QJsonObject added;
    const bool ok = settings(p, add, added, error); // Revalidates revisions after releasing lease.
    for (auto it = added.begin(); it != added.end(); ++it) result[it.key()] = it.value();
    if (!ok) error = "Remote calendar created; adding it locally failed. Retry Add to the created calendar, not creation. " + error;
    return ok;
}
}
