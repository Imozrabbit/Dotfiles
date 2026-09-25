import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import "../common/CalendarMath.js" as CalendarMath
import "../common/EventMutation.js" as EventMutation
import "../common/ProfileMutation.js" as ProfileMutation

QtObject {
    id: root

    property ProfileRegistryStore registry: ProfileRegistryStore {}
    property CalendarConflictService conflictService: CalendarConflictService {}
    property var profileStoreObjects: []
    property var pendingImport: null
    property var importResult: null
    property var pendingEventMutation: null
    property int syncReloadAttempts: 0
    readonly property string syncBrokerPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/conflict-broker.sh"
    signal eventMutationFinished(var result)
    readonly property var calendars: root.registry.profiles.map(profile => {
        const store = root.storeForId(profile.id);
        return Object.assign({}, profile, {
            writable: profile.type === "local" || profile.type === "synced",
            ready: store ? store.ready : false,
            missing: store ? store.missing : true,
            errorMessage: store ? store.errorMessage : "Calendar store is unavailable"
        });
    })

    property ImportedCalendarStore holidayStore: ImportedCalendarStore {
        sourceId: "holidays_fr"
    }

    readonly property var rawEvents: root.collectRawEvents()
    readonly property var events: root.normalizeEvents(root.rawEvents)
    readonly property var holidays: root.normalizeHolidays(root.holidayStore.rawEvents)

    function storeForId(calendarId) {
        return root.profileStoreObjects.find(store => store.profile.id === calendarId) || null;
    }

    function collectRawEvents() {
        const events = [];
        for (const store of root.profileStoreObjects) {
            for (const event of (store.rawEvents || []))
                events.push(event);
        }
        return events;
    }

    function normalizeEvents(rawEvents) {
        const normalized = [];
        for (const event of rawEvents) {
            const result = EventMutation.normalizeEvent(event, root.calendars);
            if (result)
                normalized.push(result);
        }
        return normalized;
    }

    function normalizeHolidays(rawEvents) {
        const normalized = [];
        for (const event of rawEvents) {
            const result = EventMutation.normalizeHoliday(event);
            if (result)
                normalized.push(result);
        }
        return normalized;
    }

    function calendarById(calendarId) {
        return root.calendars.find(calendar => calendar.id === calendarId) || null;
    }

    function setCalendarVisible(calendarId, visible) {
        return root.registry.setVisible(calendarId, visible);
    }

    function availableUid() {
        let uid;
        do {
            uid = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + "@quickshell-calendar";
        } while (root.rawEvents.some(event => event.uid === uid))
        return uid;
    }

    function storageUnavailable() {
        return {
            ok: false,
            field: "storage",
            message: "Calendar storage is not ready"
        };
    }

    function persistStore(store, rawEvents) {
        if (!store || !store.ready)
            return root.storageUnavailable();
        return store.persist(rawEvents.filter(event => event.calendarId === store.profile.id));
    }

    function syncDirectoryForId(calendarId) {
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        const home = dataHome && dataHome.length > 0 ? dataHome : Quickshell.env("HOME") + "/.local/share";
        return home + "/calendars/" + calendarId;
    }

    function finishSyncedMutation() {
        const pending = root.pendingEventMutation;
        if (!pending)
            return;
        const event = pending.store.rawEvents.find(candidate => candidate.sourceUid === pending.sourceUid);
        const present = Boolean(event);
        const normalized = event ? EventMutation.normalizeEvent(event, root.calendars) : null;
        const expected = pending.result.event;
        const reflected = normalized && expected && ["title", "description", "location", "allDay", "startMs", "endMs"].every(key => normalized[key] === expected[key]) && JSON.stringify(normalized.reminders) === JSON.stringify(expected.reminders);
        if (pending.operation === "delete" ? present : !reflected) {
            if (root.syncReloadAttempts++ < 50)
                return;
            root.syncReloadTimer.stop();
            root.pendingEventMutation = null;
            root.eventMutationFinished(Object.assign({}, pending.result, {
                cacheWarning: true,
                message: "Event saved, but calendar cache did not reflect change. Do not retry this change."
            }));
            return;
        }
        root.syncReloadTimer.stop();
        root.pendingEventMutation = null;
        root.eventMutationFinished(pending.operation === "delete" ? {
            ok: true,
            uid: pending.cacheUid
        } : {
            ok: true,
            event: normalized
        });
    }

    function syncedMutation(operation, uid, eventData) {
        if (syncProcess.running)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        if (!root.conflictService.stateValid)
            return {
                ok: false,
                field: "storage",
                message: root.conflictService.errorMessage || "Calendar conflict state is not ready"
            };

        const current = uid ? root.rawEvents.find(event => event.uid === uid) : null;
        if (current && root.conflictService.isConflicted(current.sourceUid || uid))
            return {
                ok: false,
                field: "event",
                message: "Resolve calendar conflict before editing this event"
            };
        if (operation === "update" && (!current || eventData.revision !== current.revision))
            return {
                ok: false,
                field: "event",
                message: "Event changed on another device; reopen it"
            };
        if (operation === "delete" && (!current || eventData.revision !== current.revision))
            return {
                ok: false,
                field: "event",
                message: "Event changed on another device; reopen it"
            };
        const candidate = operation === "create" ? EventMutation.createEvent(root.rawEvents, root.calendars, eventData, root.availableUid()) : operation === "update" ? EventMutation.updateEvent(root.rawEvents, root.calendars, uid, eventData) : EventMutation.deleteEvent(root.rawEvents, root.calendars, uid);
        if (!candidate.ok)
            return candidate;

        const event = candidate.event || current;
        const store = root.storeForId(event ? event.calendarId : current.calendarId);
        if (!store || store.profile.type !== "synced")
            return root.storageUnavailable();

        root.pendingEventMutation = {
            operation,
            store,
            sourceUid: event.sourceUid || event.uid.replace(store.profile.id + ":", ""),
            cacheUid: event.uid,
            result: operation === "delete" ? {
                ok: true,
                uid: candidate.uid
            } : {
                ok: true,
                event
            }
        };
        syncProcess.command = [root.syncBrokerPath, "mutate", root.syncDirectoryForId(store.profile.id), store.filePath, store.profile.id, operation];
        syncProcess.running = true;
        const request = operation === "delete" ? {
            uid: event.sourceUid || uid.replace(store.profile.id + ":", ""),
            revision: current.revision
        } : Object.assign({}, event, {
            uid: event.sourceUid || event.uid.replace(store.profile.id + ":", ""),
            revision: current ? current.revision : undefined
        });
        syncProcess.write(JSON.stringify(request) + "\n");
        return {
            ok: true,
            pending: true
        };
    }

    function createEvent(eventData) {
        const store = root.storeForId(eventData.calendarId);
        if (store && store.profile.type === "synced")
            return root.syncedMutation("create", "", eventData);
        if (!store || store.profile.type !== "local")
            return root.storageUnavailable();
        const result = EventMutation.createEvent(root.rawEvents, root.calendars, eventData, root.availableUid());
        if (!result.ok)
            return result;
        const saved = root.persistStore(store, result.rawEvents);
        if (!saved.ok)
            return saved;
        return {
            ok: true,
            event: result.event
        };
    }

    function updateEvent(uid, eventData) {
        const current = root.rawEvents.find(event => event.uid === uid);
        const oldStore = current ? root.storeForId(current.calendarId) : null;
        if (oldStore && oldStore.profile.type === "synced")
            return root.syncedMutation("update", uid, eventData);
        if (!oldStore || oldStore.profile.type !== "local")
            return root.storageUnavailable();
        const result = EventMutation.updateEvent(root.rawEvents, root.calendars, uid, eventData);
        if (!result.ok)
            return result;
        const newStore = root.storeForId(result.event.calendarId);
        if (!newStore || newStore.profile.type !== "local")
            return root.storageUnavailable();
        const destinationEvents = newStore === oldStore ? [] : newStore.rawEvents.slice();
        const destinationSaved = newStore === oldStore ? {
            ok: true
        } : root.persistStore(newStore, result.rawEvents);
        if (!destinationSaved.ok)
            return destinationSaved;
        const saved = root.persistStore(oldStore, result.rawEvents);
        if (!saved.ok && newStore !== oldStore) {
            const restored = root.persistStore(newStore, destinationEvents);
            if (!restored.ok)
                return Object.assign({}, saved, {
                    message: saved.message + "; destination rollback failed: " + restored.message
                });
        }
        if (!saved.ok)
            return saved;
        return {
            ok: true,
            event: result.event
        };
    }

    function deleteEvent(uid, revision) {
        const current = root.rawEvents.find(event => event.uid === uid);
        const store = current ? root.storeForId(current.calendarId) : null;
        if (store && store.profile.type === "synced")
            return root.syncedMutation("delete", uid, {
                revision
            });
        if (!store || store.profile.type !== "local")
            return root.storageUnavailable();
        const result = EventMutation.deleteEvent(root.rawEvents, root.calendars, uid);
        if (!result.ok)
            return result;
        const saved = root.persistStore(store, result.rawEvents);
        if (!saved.ok)
            return saved;
        return {
            ok: true,
            uid: result.uid
        };
    }

    function eventsInRange(start, end) {
        const startMs = start instanceof Date ? start.getTime() : Number(start);
        const endMs = end instanceof Date ? end.getTime() : Number(end);
        return CalendarMath.filterEventsInRange(root.events, root.calendars, startMs, endMs);
    }

    function holidaysInRange(start, end) {
        const startMs = start instanceof Date ? start.getTime() : Number(start);
        const endMs = end instanceof Date ? end.getTime() : Number(end);
        if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs)
            return [];
        return root.holidays.filter(event => CalendarMath.rangesOverlap(event.startMs, event.endMs, startMs, endMs)).sort((left, right) => left.startMs - right.startMs || String(left.uid).localeCompare(String(right.uid)));
    }

    function createProfile(draft) {
        return root.registry.createProfile(draft);
    }

    function updateProfile(id, changes) {
        return root.registry.updateProfile(id, changes);
    }

    function importIcsProfile(draft, sourcePath, replacingId) {
        if (importProcess.running || importCommitProcess.running || importCleanupProcess.running)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar import is running"
            };
        if (typeof sourcePath !== "string" || sourcePath.length === 0)
            return {
                ok: false,
                field: "source",
                message: "Choose an ICS file or folder"
            };

        const target = ProfileMutation.validateImportTarget(root.registry.profiles, draft.id, replacingId || "");
        if (!target.ok)
            return target;
        const existing = target.replacing ? target.profile : null;
        const candidate = existing ? Object.assign({}, existing, {
            name: draft.name,
            color: draft.color
        }) : Object.assign({
            visible: true
        }, draft);
        const validation = ProfileMutation.validateProfile(candidate);
        if (!validation.ok)
            return validation;

        const registryPath = root.registry.filePath.replace(/\/profiles\.json$/, "");
        const outputPath = registryPath + "/" + validation.profile.id + ".json";
        const temporaryPath = outputPath + ".importing-" + Date.now();
        root.pendingImport = {
            draft: validation.profile,
            existing: Boolean(existing),
            previousProfile: existing ? Object.assign({}, existing) : null,
            sourcePath,
            outputPath,
            temporaryPath
        };
        root.importResult = null;
        importProcess.command = [root.converterPath, sourcePath, temporaryPath, validation.profile.id];
        importProcess.running = true;
        return {
            ok: true,
            pending: true
        };
    }

    readonly property string converterPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/convert"

    function removeProfile(id) {
        return root.registry.removeProfile(id);
    }

    property Process importProcess: Process {
        id: importProcess
        command: []
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            const pending = root.pendingImport;
            if (!pending)
                return;
            if (exitCode !== 0) {
                root.cleanupImport({
                    ok: false,
                    field: "source",
                    message: "Could not import ICS source"
                });
                return;
            }
            root.prepareImportCommit(pending);
        }
        // qmllint enable signal-handler-parameters
    }

    function prepareImportCommit(pending) {
        const registered = pending.existing ? root.registry.updateProfile(pending.draft.id, {
            name: pending.draft.name,
            color: pending.draft.color
        }) : root.registry.createProfile(pending.draft);
        if (!registered.ok) {
            root.cleanupImport(registered);
            return;
        }
        pending.registryResult = registered;
        importCommitProcess.command = [root.converterPath, "commit", pending.temporaryPath, pending.outputPath, pending.existing ? "replace" : "create"];
        importCommitProcess.running = true;
    }

    function cleanupImport(result) {
        root.importCleanupResult = result;
        importCleanupProcess.command = ["rm", "-f", "--", root.pendingImport.temporaryPath];
        importCleanupProcess.running = true;
    }

    property var importCleanupResult: null

    property Process importCommitProcess: Process {
        id: importCommitProcess
        command: []
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            const pending = root.pendingImport;
            if (!pending)
                return;
            if (exitCode === 0) {
                root.pendingImport = null;
                root.importResult = pending.registryResult;
                return;
            }
            const rollback = pending.existing ? root.registry.updateProfile(pending.previousProfile.id, {
                name: pending.previousProfile.name,
                color: pending.previousProfile.color
            }) : root.registry.removeProfile(pending.draft.id);
            root.cleanupImport({
                ok: false,
                field: "storage",
                message: "Could not commit imported calendar" + (rollback.ok ? "" : "; could not restore imported calendar metadata: " + rollback.message)
            });
        }
        // qmllint enable signal-handler-parameters
    }

    property Process importCleanupProcess: Process {
        id: importCleanupProcess
        command: []
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.importCleanupResult.ok)
                root.importCleanupResult = {
                    ok: false,
                    field: "storage",
                    message: "Could not remove temporary imported calendar file"
                };
            root.importResult = root.importCleanupResult;
            root.importCleanupResult = null;
            root.pendingImport = null;
        }
        // qmllint enable signal-handler-parameters
    }

    property Process syncProcess: Process {
        id: syncProcess
        stdinEnabled: true
        command: []
        stderr: StdioCollector {
            id: syncStderr
        }
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            const pending = root.pendingEventMutation;
            if (!pending)
                return;
            if (exitCode === 2 || exitCode === 3) {
                pending.store.profileFile.reload();
                root.pendingEventMutation = null;
                const detail = syncStderr.text.trim();
                root.eventMutationFinished(Object.assign({}, pending.result, {
                    ok: true,
                    cacheWarning: true,
                    message: (exitCode === 2 ? "Event saved, but calendar cache refresh failed. Do not retry this change." : "Event saved, but pimsync could not restart. Do not retry this change.") + (detail.length > 0 ? " " + detail : "")
                }));
                return;
            }
            if (exitCode !== 0) {
                root.pendingEventMutation = null;
                const detail = syncStderr.text.trim();
                root.eventMutationFinished({
                    ok: false,
                    field: "storage",
                    message: detail.length > 0 ? detail : "Could not update synced calendar"
                });
                return;
            }
            root.syncReloadAttempts = 0;
            pending.store.profileFile.reload();
            root.syncReloadTimer.start();
        }
        // qmllint enable signal-handler-parameters
    }

    property Timer syncReloadTimer: Timer {
        interval: 100
        repeat: true
        onTriggered: root.finishSyncedMutation()
    }

    property Instantiator profileStores: Instantiator {
        id: profileStores
        model: root.registry.ready ? root.registry.profiles : []
        delegate: CalendarProfileStore {
            required property var modelData
            profile: modelData
        }
        onObjectAdded: (index, object) => {
            const stores = root.profileStoreObjects.slice();
            stores.splice(index, 0, object);
            root.profileStoreObjects = stores;
        }
        onObjectRemoved: (index, object) => {
            root.profileStoreObjects = root.profileStoreObjects.filter(store => store !== object);
        }
    }
}
