pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../history" as History
import "../images" as Images
import "Policy.js" as Policy

Scope {
    id: root
    property var screens: []
    property string focusedScreenName: ""
    property var records: []
    property var entries: []
    property var toasts: []
    readonly property bool dnd: memory.dnd
    readonly property bool ready: archive.ready
    readonly property bool busy: archive.busy
    readonly property string lastError: archive.lastError || images.lastError
    readonly property var document: archive.document
    readonly property var pending: archive.pending
    readonly property var captureJob: {
        const job = images?.job;
        if (!job)
            return null;
        const record = root.records.find(value => value.captureToken === job.token);
        return Object.assign({}, job, {
            screenName: record?.screenName || root.selectScreen()
        });
    }
    property var links: ({})
    property bool linksLoaded: false
    property bool restored: false
    property int captureSequence: 0

    PersistentProperties {
        id: memory
        reloadableId: "command-center-native-links"
        property string linksJson: "{}"
        property bool dnd: false
        onLoaded: {
            try {
                root.links = JSON.parse(memory.linksJson);
            } catch (_) {
                root.links = {};
            }
            root.linksLoaded = true;
            root.restoreArchive();
            root.applyDnd();
        }
    }

    Component {
        id: recordFactory
        Record {}
    }

    function setDnd(enabled: bool): bool {
        // Observe queued replacements under DND before clearing it.
        if (root.dnd && !enabled)
            root.applyDnd();
        memory.dnd = enabled;
        return root.dnd;
    }

    function toggleDnd(): bool {
        return root.setDnd(!root.dnd);
    }

    function applyDnd(): void {
        if (!root.dnd || !root.linksLoaded)
            return;
        for (const record of root.records.slice()) {
            record.observe();
            if (record.closing || record.data.urgency === 2)
                continue;
            record.dndSuppressed = true;
            record.shown = false;
            if (record.data.transient)
                root.expire(record);
        }
        root.saveLinks();
        root.rebuild();
    }

    function selectScreen(): string {
        return (root.screens.find(screen => screen.name === root.focusedScreenName) ?? root.screens[0])?.name || "";
    }

    function thumbnailPath(name: var): string {
        return typeof name === "string" && /^notification-[A-Za-z0-9]{10}\.png$/.test(name) ? images.directory + "/" + name : "";
    }

    function createRecord(properties: var): var {
        const record = recordFactory.createObject(root, properties);
        record.updated.connect(value => root.changed(value));
        record.closed.connect(value => root.withdrawn(value));
        record.expired.connect(value => root.expire(value));
        root.records = root.records.concat([record]);
        return record;
    }

    function accept(notification: var): void {
        const key = "native-" + notification.id;
        if (root.records.some(record => record.key === key))
            return;
        const data = Policy.snapshot(notification);
        const signature = JSON.stringify(data);
        const saved = notification.lastGeneration ? root.links[String(notification.id)] : null;
        const carried = saved && Number.isSafeInteger(saved.revision) && Number.isSafeInteger(saved.archiveId);
        const changed = carried && saved.signature !== Qt.md5(signature);
        const dndSuppressed = data.urgency !== 2 && (root.dnd || (carried === true && !changed && saved.dndSuppressed === true));
        const now = Date.now();
        const screenName = carried && root.screens.some(screen => screen.name === saved.screenName) ? saved.screenName : root.selectScreen();
        const record = root.createRecord({
            notification,
            key,
            data,
            signature,
            archiveId: carried ? saved.archiveId : 0,
            revision: carried ? saved.revision + (changed ? 1 : 0) : 1,
            receivedAt: carried ? saved.receivedAt : now,
            updatedAt: carried ? changed ? Math.max(now, saved.updatedAt + 1) : saved.updatedAt : now,
            thumbnail: carried && !changed ? saved.thumbnail || "" : "",
            dndSuppressed,
            shown: !dndSuppressed && (!carried || changed || !saved.durable || data.transient || data.urgency === 2),
            screenName
        });
        if (root.ready)
            root.persist(record);
        root.saveLinks();
        root.rebuild();
        if (record.dndSuppressed && record.data.transient)
            root.expire(record);
    }

    function saveLinks(): void {
        if (!root.linksLoaded)
            return;
        const links = {};
        const durable = new Map(archive.document.entries.map(entry => [entry.id, entry.revision ?? 0]));
        for (const record of root.records) {
            if (!record.notification || record.closing)
                continue;
            links[String(record.notification.id)] = {
                archiveId: record.archiveId,
                revision: record.revision,
                receivedAt: record.receivedAt,
                updatedAt: record.updatedAt,
                thumbnail: record.thumbnail,
                screenName: record.screenName,
                signature: Qt.md5(record.signature),
                dndSuppressed: record.dndSuppressed,
                durable: durable.get(record.archiveId) === record.revision
            };
        }
        memory.linksJson = JSON.stringify(links);
    }

    function archived(record: var): var {
        return {
            id: record.archiveId,
            receivedAt: record.receivedAt,
            appName: record.data.appName,
            summary: record.data.summary,
            body: record.data.body,
            appIcon: record.data.appIcon,
            updatedAt: record.updatedAt,
            revision: record.revision,
            urgency: record.data.urgency,
            imageExpected: record.data.imageExpected,
            thumbnail: record.thumbnail
        };
    }

    function persist(record: var): void {
        if (!root.ready || record.closing || !record.notification)
            return;
        if (record.data.transient) {
            if (record.archiveId)
                archive.remove([record.archiveId]);
            record.archiveId = 0;
            record.thumbnail = "";
            return;
        }
        if (!record.archiveId)
            record.archiveId = archive.nextId;
        if (archive.isClearing(record.archiveId, record.revision))
            return;
        const existing = archive.pending.entries.find(entry => entry.id === record.archiveId);
        const next = root.archived(record);
        if (!existing || JSON.stringify(existing) !== JSON.stringify(next))
            archive.upsert(next);
        if (record.data.source && !record.thumbnail && !record.captureToken) {
            const token = record.key + ":" + record.revision + ":" + (++root.captureSequence);
            record.captureToken = token;
            if (!images.request(token, record.data.source))
                record.captureToken = "";
        }
    }

    function restoreArchive(): void {
        if (!root.ready || !root.linksLoaded || root.restored)
            return;
        root.restored = true;
        for (const record of root.records)
            root.persist(record);
        for (const entry of archive.document.entries) {
            if (entry.urgency !== 2 || root.records.some(record => record.archiveId === entry.id) || !archive.pending.entries.some(value => value.id === entry.id))
                continue;
            root.createRecord({
                key: "saved-" + entry.id,
                archiveId: entry.id,
                revision: entry.revision ?? 0,
                receivedAt: entry.receivedAt,
                updatedAt: entry.updatedAt ?? entry.receivedAt,
                thumbnail: entry.thumbnail || "",
                shown: true,
                screenName: root.selectScreen(),
                data: {
                    appName: entry.appName,
                    summary: entry.summary,
                    body: entry.body,
                    appIcon: entry.appIcon,
                    urgency: 2,
                    timeout: 0,
                    transient: false,
                    actions: [],
                    hasInlineReply: false,
                    imageExpected: entry.imageExpected === true
                }
            });
        }
        root.saveLinks();
        root.rebuild();
        root.reconcile();
    }

    function changed(record: var): void {
        if (record.closing)
            return;
        if (record.captureToken)
            images.cancel(record.captureToken);
        record.captureToken = "";
        record.thumbnail = "";
        record.dndSuppressed = root.dnd && record.data.urgency !== 2;
        if (!record.shown && !record.dndSuppressed)
            record.screenName = root.selectScreen();
        record.shown = !record.dndSuppressed;
        record.restart();
        root.persist(record);
        root.saveLinks();
        root.rebuild();
        if (record.dndSuppressed && record.data.transient)
            root.expire(record);
    }

    function removeRecord(record: var): void {
        record.closing = true;
        if (record.captureToken)
            images.cancel(record.captureToken);
        root.records = root.records.filter(value => value !== record);
        root.saveLinks();
        root.rebuild();
        record.destroy();
        root.reconcile();
    }

    function withdrawn(record: var): void {
        if (record.archiveId)
            archive.remove([record.archiveId]);
        root.removeRecord(record);
    }

    function expire(record: var): void {
        if (record.data.transient && record.notification?.tracked)
            record.notification.expire();
        else {
            record.shown = false;
            root.rebuild();
        }
    }

    function valid(key: string, revision: var): var {
        const record = root.records.find(value => value.key === key && !value.closing && value.revision === revision);
        if (!record || !record.notification?.tracked)
            return null;
        if (record.observe())
            return null;
        return record;
    }

    function invoke(key: string, revision: var, identifier: string): bool {
        const record = root.valid(key, revision);
        const action = record?.notification.actions.find(value => value.identifier === identifier);
        if (!action)
            return false;
        action.invoke();
        return true;
    }

    function reply(key: string, revision: var, text: string): bool {
        const record = root.valid(key, revision);
        if (!record?.data.hasInlineReply || text.trim() === "" || text.includes("\0"))
            return false;
        record.notification.sendInlineReply(text);
        return true;
    }

    function copy(key: string, revision: var): bool {
        const record = root.valid(key, revision);
        if (!record?.shown || !record.data.code)
            return false;
        Quickshell.clipboardText = record.data.code;
        if (!record.data.resident)
            record.notification.dismiss();
        return true;
    }

    function dismiss(key: string, revision: var): bool {
        const record = root.records.find(value => value.key === key && value.revision === revision && !value.closing);
        if (!record)
            return false;
        const committed = archive.document.entries.some(entry => entry.id === record.archiveId);
        if (!record.archiveId || (!committed && !root.busy)) {
            if (record.archiveId)
                archive.remove([record.archiveId]);
            if (record.notification?.tracked)
                record.notification.dismiss();
            else
                root.removeRecord(record);
            return true;
        }
        return archive.clear([
            {
                id: record.archiveId,
                revision
            }
        ]);
    }

    function clear(key: var, revision: var): bool {
        const entry = root.entries.find(value => value.id === key && value.revision === revision);
        return entry ? archive.clear([
            {
                id: entry.archiveId,
                revision
            }
        ]) : false;
    }

    function clearGroup(appName: string): bool {
        return archive.clear(root.entries.filter(entry => entry.appName === appName).map(entry => ({
                    id: entry.archiveId,
                    revision: entry.revision
                })));
    }

    function clearAll(): bool {
        return archive.clear(root.entries.map(entry => ({
                    id: entry.archiveId,
                    revision: entry.revision
                })));
    }

    function interact(key: string, hovered: bool, focused: bool): void {
        const record = root.records.find(value => value.key === key && value.shown);
        if (record) {
            record.hovered = hovered;
            record.focused = focused;
        }
    }

    function captureFinished(token: string, success: bool): void {
        images.finish(token, success);
    }

    function reconcile(): void {
        if (!root.ready || !root.restored)
            return;
        const documents = [archive.document, archive.pending, archive.savingDocument].filter(value => value);
        const references = [];
        for (const document of documents) {
            for (const entry of document.entries) {
                if (entry.thumbnail)
                    references.push(entry.thumbnail);
            }
        }
        images.reconcile(references);
    }

    function view(record: var, saved: var, toast: bool): var {
        const data = saved || record.data;
        const revision = saved ? saved.revision ?? 0 : record.revision;
        const live = record?.notification?.tracked === true && record.revision === revision;
        return {
            id: record ? record.key : "saved-" + saved.id,
            archiveId: saved ? saved.id : record.archiveId,
            revision,
            appName: data.appName,
            summary: data.summary,
            body: data.body,
            appIcon: Policy.localImage(data.appIcon),
            time: Qt.formatDateTime(new Date(saved ? saved.updatedAt ?? saved.receivedAt : record.updatedAt), "MMM d, HH:mm"),
            image: toast ? root.thumbnailPath(record.thumbnail) || record.data.source || "" : root.thumbnailPath(saved.thumbnail),
            imageExpected: data.imageExpected === true,
            critical: data.urgency === 2,
            actions: live ? record.data.actions : [],
            hasInlineReply: live && record.data.hasInlineReply === true,
            inlineReplyPlaceholder: live ? record.data.inlineReplyPlaceholder : "",
            code: toast && live ? record.data.code : "",
            screenName: record?.screenName || "",
            dismissEnabled: !record?.archiveId || !root.busy
        };
    }

    function rebuild(): void {
        if (!archive?.document)
            return;
        const byArchive = new Map(root.records.filter(record => record.archiveId).map(record => [record.archiveId, record]));
        const pendingIds = new Set((archive.pending?.entries || []).map(entry => entry.id));
        const clearing = new Map(archive.clearTargets.map(target => [target.id, target.revision]));
        root.entries = archive.document.entries.filter(entry => {
            const record = byArchive.get(entry.id);
            if (record?.shown || (!record && entry.urgency === 2))
                return false;
            return !archive.pending || pendingIds.has(entry.id) || clearing.get(entry.id) === (entry.revision ?? 0);
        }).sort((a, b) => (b.updatedAt ?? b.receivedAt) - (a.updatedAt ?? a.receivedAt) || b.id - a.id).map(entry => root.view(byArchive.get(entry.id), entry, false));
        root.toasts = root.records.filter(record => record.shown).sort((a, b) => b.updatedAt - a.updatedAt).map(record => root.view(record, null, true));
    }

    onScreensChanged: {
        for (const record of root.records) {
            if (!root.screens.some(screen => screen.name === record.screenName))
                record.screenName = root.selectScreen();
        }
        root.saveLinks();
        root.rebuild();
    }
    onReadyChanged: root.restoreArchive()
    onBusyChanged: root.rebuild()
    onDndChanged: root.applyDnd()

    NotificationServer {
        keepOnReload: true
        actionsSupported: true
        inlineReplySupported: true
        persistenceSupported: true
        imageSupported: true
        bodyImagesSupported: true
        onNotification: notification => {
            notification.tracked = true;
            root.accept(notification);
        }
    }

    History.Archive {
        id: archive
        onDocumentChanged: {
            root.saveLinks();
            root.rebuild();
            Qt.callLater(root.reconcile);
        }
        onPendingChanged: {
            root.rebuild();
            Qt.callLater(root.reconcile);
        }
        onCleared: targets => {
            for (const record of root.records.slice()) {
                if (!targets.some(target => target.id === record.archiveId && target.revision === record.revision))
                    continue;
                if (record.notification?.tracked)
                    record.notification.dismiss();
                else
                    root.removeRecord(record);
            }
        }
    }

    Images.Store {
        id: images
        authoritative: archive.ready
        onCompleted: (token, name, success) => {
            const record = root.records.find(value => value.captureToken === token && !value.closing);
            if (record) {
                record.captureToken = "";
                if (success && !record.data.transient && !archive.isClearing(record.archiveId, record.revision)) {
                    record.thumbnail = name;
                    archive.upsert(root.archived(record));
                    root.saveLinks();
                    root.rebuild();
                }
            }
            root.reconcile();
        }
    }
}
