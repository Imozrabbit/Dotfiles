import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import "../common/CalendarMath.js" as CalendarMath
import "../common/EventMutation.js" as EventMutation

QtObject {
    id: root

    property ProfileRegistryStore registry: ProfileRegistryStore {}
    property CalendarConflictManager conflictService: CalendarConflictManager {
        profiles: root.registry.ready ? root.registry.profiles : []
        caldav: root.caldav
        mutationBlocked: root.caldavRemovalBusy
    }
    property var profileStoreObjects: []
    readonly property bool importBusy: root.importer.busy
    property var importResult: null
    readonly property bool subscriptionBusy: root.subscriptions.busy
    property var subscriptionResult: null
    readonly property bool caldavBusy: root.caldav.busy
    readonly property bool caldavRemovalBusy: root.caldav.pending?.action === "remove"
    property var caldavResult: null
    readonly property bool localRemovalBusy: root.registry.localRemovalPending !== null
    readonly property var localRemovalResult: root.registry.localRemovalResult
    property var pendingEventMutation: null
    property var pendingLocalMutation: null
    property string systemTimezone: ""
    property int syncReloadAttempts: 0
    readonly property string syncBrokerPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/conflict-broker.sh"
    readonly property string nativeHelperPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/calendar-sync-helper"
    signal eventMutationFinished(var result)
    signal calendarRemoved(string calendarId)
    signal calendarConverted(string calendarId)
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
        if (root.caldav.conversionBlocked(calendarId))
            return {
                ok: false,
                message: "Calendar conversion is running"
            };
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

    function persistStore(store, rawEvents, sourceCalendarId) {
        if (root.caldavRemovalBusy)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        if (root.localRemovalBusy)
            return {
                ok: false,
                field: "storage",
                message: "Local calendar removal is running"
            };
        if (!store || !store.ready)
            return root.storageUnavailable();
        if (root.caldav.conversionBlocked(store.profile.id) || (sourceCalendarId && root.caldav.conversionBlocked(sourceCalendarId)))
            return {
                ok: false,
                field: "storage",
                message: "Calendar conversion is running"
            };
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
        const memberUids = pending.memberUids || [];
        const retainedMember = pending.store.rawEvents.some(candidate => memberUids.includes(candidate.sourceUid));
        const grouped = expected && expected.recurrence && expected.recurrence.frequency === "yearly" && expected.recurrence.pattern.dates.length > 1;
        const groupReflected = !retainedMember && (grouped ? event && event.seriesGroup && event.seriesGroup.members.length === expected.recurrence.pattern.dates.length : !event || !event.seriesGroup);
        const reflected = normalized && expected && ["title", "description", "location", "allDay", "startMs", "endMs"].every(key => normalized[key] === expected[key]) && JSON.stringify(normalized.reminders) === JSON.stringify(expected.reminders) && JSON.stringify(normalized.recurrence || null) === JSON.stringify(expected.recurrence || null) && (!expected.recurrence || expected.allDay || normalized.timezone === expected.timezone);
        if (pending.operation === "delete" ? present || retainedMember : !reflected || !groupReflected) {
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
        const conversionId = eventData.calendarId || root.rawEvents.find(event => event.uid === uid)?.calendarId;
        if (root.caldav.conversionBlocked(conversionId))
            return {
                ok: false,
                field: "storage",
                message: "Calendar conversion is running"
            };
        if (root.pendingLocalMutation || root.pendingEventMutation || syncProcess.running || root.caldavRemovalBusy)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        const current = uid ? root.rawEvents.find(event => event.uid === uid) : null;
        if (!root.conflictService.stateValidForId(current ? current.calendarId : eventData.calendarId))
            return {
                ok: false,
                field: "storage",
                message: root.conflictService.errorMessage || "Calendar conflict state is not ready"
            };

        if (current && (root.conflictService.isConflicted(current) || current.seriesGroup && current.seriesGroup.members.some(member => root.conflictService.isConflicted(member.uid, current.calendarId))))
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
        const grouped = Boolean(current && current.seriesGroup) || Boolean(event.recurrence && event.recurrence.frequency === "yearly" && event.recurrence.pattern.dates.length > 1);
        const store = root.storeForId(event ? event.calendarId : current.calendarId);
        if (!store || store.profile.type !== "synced")
            return root.storageUnavailable();

        root.pendingEventMutation = {
            operation,
            store,
            sourceUid: event.sourceUid || event.uid.replace(store.profile.id + ":", ""),
            cacheUid: event.uid,
            memberUids: current && current.seriesGroup ? current.seriesGroup.members.map(member => member.uid) : [],
            result: operation === "delete" ? {
                ok: true,
                uid: candidate.uid
            } : {
                ok: true,
                event
            }
        };
        syncProcess.command = [root.syncBrokerPath, grouped ? "mutate-group" : "mutate", root.syncDirectoryForId(store.profile.id), store.filePath, store.profile.id, operation];
        if (grouped)
            syncProcess.command = syncProcess.command.concat([root.pendingEventMutation.sourceUid]);
        if (root.caldav.recordForId(store.profile.id))
            syncProcess.command = ["/usr/bin/env", "CALENDAR_ID=" + store.profile.id].concat(syncProcess.command);
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

    function createEvent(eventData, normalized) {
        if (root.pendingLocalMutation || root.pendingEventMutation || root.caldavRemovalBusy)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        const store = root.storeForId(eventData.calendarId);
        if (store && store.profile.type === "synced" && eventData.recurrence && !normalized)
            return root.prepareLocalMutation("create", "", eventData);
        if (store && store.profile.type === "synced")
            return root.syncedMutation("create", "", eventData);
        if (!store || store.profile.type !== "local")
            return root.storageUnavailable();
        if (eventData.recurrence && !normalized)
            return root.prepareLocalMutation("create", "", eventData);
        const result = EventMutation.createEvent(root.rawEvents, root.calendars, eventData, normalized ? eventData.uid : root.availableUid());
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

    function updateEvent(uid, eventData, normalized) {
        if (root.pendingLocalMutation || root.pendingEventMutation || root.caldavRemovalBusy)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        const current = root.rawEvents.find(event => event.uid === uid);
        const oldStore = current ? root.storeForId(current.calendarId) : null;
        if (oldStore && oldStore.profile.type === "synced" && (eventData.recurrence || (eventData.recurrence === undefined && current.recurrence)) && !normalized)
            return root.prepareLocalMutation("update", uid, eventData);
        if (oldStore && oldStore.profile.type === "synced")
            return root.syncedMutation("update", uid, eventData);
        if (!oldStore || oldStore.profile.type !== "local")
            return root.storageUnavailable();
        if ((eventData.recurrence || (eventData.recurrence === undefined && current.recurrence)) && !normalized)
            return root.prepareLocalMutation("update", uid, eventData);
        const result = EventMutation.updateEvent(root.rawEvents, root.calendars, uid, eventData);
        if (!result.ok)
            return result;
        const newStore = root.storeForId(result.event.calendarId);
        if (!newStore || newStore.profile.type !== "local")
            return root.storageUnavailable();
        const destinationEvents = newStore === oldStore ? [] : newStore.rawEvents.slice();
        const destinationSaved = newStore === oldStore ? {
            ok: true
        } : root.persistStore(newStore, result.rawEvents, oldStore.profile.id);
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
        if (root.pendingLocalMutation || root.pendingEventMutation || root.caldavRemovalBusy)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
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

    function prepareLocalMutation(operation, uid, eventData) {
        if (root.pendingLocalMutation || root.pendingEventMutation || root.localRemovalBusy || root.caldavRemovalBusy)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        const data = Object.assign({}, eventData);
        if (data.allDay !== true && !data.timezone) {
            const current = root.rawEvents.find(event => event.uid === uid);
            data.timezone = current && current.timezone || root.systemTimezone;
        }
        const candidate = operation === "create" ? EventMutation.createEvent(root.rawEvents, root.calendars, data, root.availableUid()) : EventMutation.updateEvent(root.rawEvents, root.calendars, uid, data);
        if (!candidate.ok)
            return candidate;
        root.pendingLocalMutation = {
            operation,
            uid: candidate.event.uid,
            revision: eventData.revision,
            snapshot: JSON.stringify(root.rawEvents)
        };
        normalizeProcess.command = [root.nativeHelperPath, "normalize"];
        normalizeProcess.running = true;
        normalizeProcess.write(JSON.stringify(candidate.event) + "\n");
        return {
            ok: true,
            pending: true
        };
    }

    function finishLocalNormalization(exitCode, text, detail) {
        const pending = root.pendingLocalMutation;
        if (!pending)
            return;
        root.pendingLocalMutation = null;
        if (exitCode !== 0 || pending.snapshot !== JSON.stringify(root.rawEvents)) {
            root.eventMutationFinished({
                ok: false,
                field: "storage",
                message: exitCode !== 0 ? detail || "Could not prepare repeating event" : "Calendar changed while preparing event; reopen it"
            });
            return;
        }
        let event;
        try {
            event = JSON.parse(text);
        } catch (error) {
            root.eventMutationFinished({
                ok: false,
                field: "storage",
                message: "Repeating event helper returned invalid data"
            });
            return;
        }
        if (!event || event.uid !== pending.uid) {
            root.eventMutationFinished({
                ok: false,
                field: "storage",
                message: "Repeating event identity changed unexpectedly"
            });
            return;
        }
        if (pending.revision !== undefined)
            event.revision = pending.revision;
        const result = pending.operation === "create" ? root.createEvent(event, true) : root.updateEvent(pending.uid, event, true);
        if (!result.pending)
            root.eventMutationFinished(result);
    }

    property Process timezoneProcess: Process {
        command: [root.nativeHelperPath, "system-timezone"]
        running: true
        stdout: StdioCollector {
            id: timezoneOutput
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                return;
            try {
                const result = JSON.parse(timezoneOutput.text);
                if (typeof result.timezone === "string" && result.timezone.length > 0)
                    root.systemTimezone = result.timezone;
            } catch (error) {
                console.error("Could not read configured calendar timezone");
            }
        }
    }

    property Process normalizeProcess: Process {
        id: normalizeProcess
        stdinEnabled: true
        stdout: StdioCollector {
            id: normalizedOutput
        }
        stderr: StdioCollector {
            id: normalizationError
        }
        onExited: (exitCode, exitStatus) => root.finishLocalNormalization(exitCode, normalizedOutput.text, normalizationError.text.trim())
    }

    function holidaysInRange(start, end) {
        const startMs = start instanceof Date ? start.getTime() : Number(start);
        const endMs = end instanceof Date ? end.getTime() : Number(end);
        if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs)
            return [];
        return root.holidays.filter(event => CalendarMath.rangesOverlap(event.startMs, event.endMs, startMs, endMs)).sort((left, right) => left.startMs - right.startMs || String(left.uid).localeCompare(String(right.uid)));
    }

    function createProfile(draft) {
        if (draft && draft.type === "synced")
            return {
                ok: false,
                field: "source",
                message: "Connect and add synced calendars through calendar manager"
            };
        if (draft && draft.type === "subscription")
            return {
                ok: false,
                field: "source",
                message: "Add subscriptions through subscription settings with a direct URL"
            };
        return root.registry.createProfile(draft);
    }

    function updateProfile(id, changes) {
        if (root.caldav.conversionBlocked(id))
            return {
                ok: false,
                message: "Calendar conversion is running"
            };
        if (root.conflictService.conflicts.some(conflict => conflict.calendarId === id))
            return {
                ok: false,
                field: "storage",
                message: "Resolve calendar conflicts first"
            };
        if (root.registry.profiles.find(profile => profile.id === id)?.type === "subscription")
            return {
                ok: false,
                field: "source",
                message: "Edit subscription settings through calendar manager"
            };
        return root.registry.updateProfile(id, changes);
    }

    function importIcsProfile(draft, sourcePath, replacingId, sourceKind) {
        const result = root.importer.begin(draft, sourcePath, replacingId, sourceKind);
        if (result.pending)
            root.importResult = null;
        return result;
    }

    readonly property string converterPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/convert"

    function removeProfile(id, expectedProfile, expectedRevision) {
        if (root.caldav.conversionBlocked(id))
            return {
                ok: false,
                message: "Calendar conversion is running"
            };
        const type = root.registry.profiles.find(profile => profile.id === id)?.type;
        if (expectedProfile?.type === "synced" && type !== "synced")
            return {
                ok: false,
                field: "storage",
                message: "Calendar profile changed; confirm removal again"
            };
        if (type === "synced") {
            if (root.pendingLocalMutation || root.pendingEventMutation || root.conflictService.busy)
                return {
                    ok: false,
                    field: "storage",
                    message: "Another calendar change is running"
                };
            const result = root.caldav.removeSynced(id, expectedProfile, expectedRevision);
            if (result.pending)
                root.caldavResult = null;
            return result;
        }
        if (type === "imported")
            return root.registry.removeLocalProfile(id, root.nativeHelperPath);
        if (type === "local") {
            const store = root.storeForId(id);
            if (root.pendingLocalMutation || root.pendingEventMutation || !store || store.initializing || (!store.ready && !store.errorMessage))
                return {
                    ok: false,
                    field: "storage",
                    message: "Another calendar change is running"
                };
            return root.registry.removeLocalProfile(id, root.nativeHelperPath);
        }
        if (type === "subscription") {
            const result = root.subscriptions.remove(id);
            if (result.pending)
                root.subscriptionResult = null;
            return result;
        }
        return root.registry.removeProfile(id);
    }

    function beginConversion(id) {
        if (root.pendingLocalMutation || root.pendingEventMutation || root.conflictService.busy || root.localRemovalBusy)
            return {
                ok: false,
                message: "Another calendar change is running"
            };
        return root.caldav.beginConversion(id);
    }

    function beginAttachment(id, connection, intervalSeconds, expectedProfile, expectedRevision) {
        const store = root.storeForId(id);
        if (root.pendingLocalMutation || root.pendingEventMutation || root.conflictService.busy || root.localRemovalBusy || !store?.ready || store.initializing)
            return {
                ok: false,
                message: "Local calendar is not ready or another change is running"
            };
        return root.caldav.beginAttachment(id, connection, intervalSeconds, expectedProfile, expectedRevision);
    }

    function beginRemoteDeletion(id) {
        if (root.pendingLocalMutation || root.pendingEventMutation || root.conflictService.busy || root.localRemovalBusy)
            return {
                ok: false,
                message: "Another calendar change is running"
            };
        return root.caldav.beginRemoteDeletion(id);
    }

    function subscriptionForId(id) {
        return root.subscriptions.recordForId(id);
    }

    function saveSubscription(draft, url, intervalSeconds, replacingId, expectedRevision, expectedProfile) {
        const result = root.subscriptions.save(draft, url, intervalSeconds, replacingId, expectedRevision, expectedProfile);
        if (result.pending)
            root.subscriptionResult = null;
        return result;
    }

    function refreshSubscription(id) {
        const result = root.subscriptions.refresh(id);
        if (result.pending)
            root.subscriptionResult = null;
        return result;
    }

    property CalendarSubscriptionService subscriptions: CalendarSubscriptionService {
        registry: root.registry
        helperPath: root.nativeHelperPath
        onFinished: result => root.subscriptionResult = result
    }

    property CalendarCalDavService caldav: CalendarCalDavService {
        registry: root.registry
        helperPath: root.nativeHelperPath
        conflicts: root.conflictService.conflicts
        onFinished: result => {
            root.caldavResult = result;
            if (result.ok && result.action === "remove" && result.removed)
                root.calendarRemoved(result.id);
            if (result.converted && ((result.ok && result.disconnected) || result.kind === "local-to-synced"))
                root.calendarConverted(result.id);
        }
    }

    property CalendarImportService importer: CalendarImportService {
        registry: root.registry
        helperPath: root.nativeHelperPath
        onFinished: result => root.importResult = result
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
            mutationBlocked: !root.caldav.ready || root.caldav.conversionBlocked(modelData.id)
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
