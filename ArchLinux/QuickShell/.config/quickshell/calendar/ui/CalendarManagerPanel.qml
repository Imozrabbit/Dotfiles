pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../common/Theme.js" as Theme

Item {
    id: root

    required property var calendarService
    signal closeRequested
    signal conversionReviewRequested
    signal conflictResolutionRequested
    readonly property int ordinaryConflictCount: root.calendarService.conflictService?.conflicts?.length || 0
    readonly property var conversionSession: root.calendarService.caldav?.conversionSession || null
    readonly property bool conversionOpen: root.conversionSession !== null && !root.conversionSession.remoteAttempted
    readonly property bool remoteDeletionOpen: root.conversionSession?.kind === "remote-delete"
    readonly property bool localPreservationOpen: root.conversionSession?.kind === "local-preserve"
    readonly property bool attachmentOpen: root.conversionSession?.kind === "local-to-synced"
    readonly property bool lifecycleOpen: !root.formMode && !root.confirmingDeletion && (root.conversionOpen || root.remoteDeletionOpen)
    property bool formMode: false
    property bool attachmentMode: false
    property string expandedActionId: ""
    property string expandedActionKind: ""
    readonly property int formTextInset: 5
    property string editingId: ""
    readonly property bool editingConflicted: root.editingId.length > 0 && root.conflictCount(root.editingId) > 0
    property string nameText: ""
    property string idText: ""
    property string colorText: "#7b9acc"
    property string typeText: "local"
    property string errorMessage: ""
    property string confirmingId: ""
    property var confirmingProfile: null
    property string confirmingRevision: ""
    readonly property bool confirmingSubscription: root.confirmingId.length > 0 && (root.confirmingProfile?.type || root.calendarService.calendarById(root.confirmingId)?.type) === "subscription"
    readonly property bool confirmingSynced: root.confirmingId.length > 0 && root.confirmingProfile?.type === "synced"
    readonly property bool confirmingDeletion: root.confirmingId.length > 0 && ["local", "imported", "subscription", "synced"].includes(root.confirmingProfile?.type || root.calendarService.calendarById(root.confirmingId)?.type)
    property string removalMessage: ""
    property string sourcePath: ""
    readonly property bool importPending: root.calendarService.importBusy
    readonly property bool operationPending: root.importPending || root.calendarService.subscriptionBusy || root.calendarService.caldavBusy || root.calendarService.localRemovalBusy === true
    property bool awaitingImportResult: false
    property int subscriptionToken: 0
    property int localRemovalToken: 0
    property string intervalText: "10"
    property string intervalUnit: "minutes"
    property string editingRevision: ""
    property var editingProfile: null
    property bool pickerOpen: false
    property string pickerPath: Quickshell.env("HOME")
    property string serverUrl: ""
    property string usernameText: ""
    property string passwordFileText: ""
    property var remoteCalendars: []
    property int selectedRemoteIndex: -1
    property string discoveredHomeHref: ""
    property string remoteNameText: ""
    property string remoteCollectionIdText: ""
    readonly property var remotePickerEntries: root.remoteCalendars.map(calendar => ({
                kind: "existing",
                id: calendar.id,
                href: calendar.href,
                label: calendar.id
            })).concat(root.discoveredHomeHref && (root.editingId.length === 0 || root.attachmentMode) ? [
        {
            kind: "create",
            label: "Create new remote calendar…"
        }
    ] : [])
    readonly property bool remoteCreateSelected: root.typeText === "synced" && root.remotePickerEntries[root.selectedRemoteIndex]?.kind === "create"
    property int caldavToken: 0
    onServerUrlChanged: root.invalidateDiscovery()
    onUsernameTextChanged: root.invalidateDiscovery()
    onPasswordFileTextChanged: root.invalidateDiscovery()
    onTypeTextChanged: {
        root.pickerOpen = false;
        if (root.editingId.length === 0)
            root.intervalText = root.typeText === "synced" ? "5" : "10";
    }

    function invalidateDiscovery() {
        root.remoteCalendars = [];
        root.selectedRemoteIndex = -1;
        root.discoveredHomeHref = "";
    }

    function closeCardActions() {
        root.expandedActionId = "";
        root.expandedActionKind = "";
    }

    function toggleCardActions(id, kind) {
        if (root.operationPending || root.confirmingDeletion)
            return;
        const collapse = root.expandedActionId === id && root.expandedActionKind === kind;
        root.expandedActionId = collapse ? "" : id;
        root.expandedActionKind = collapse ? "" : kind;
    }

    function connectCalDav() {
        root.invalidateDiscovery();
        const result = root.calendarService.caldav.discover(root.serverUrl, root.usernameText, root.passwordFileText);
        root.caldavToken = result.pending ? result.token : 0;
        root.errorMessage = result.ok ? "Connecting..." : result.message;
    }

    function syncedConnection() {
        const selected = root.remotePickerEntries[root.selectedRemoteIndex];
        if (!selected)
            return null;
        const connection = {
            url: root.serverUrl,
            username: root.usernameText,
            passwordFile: root.passwordFileText
        };
        return selected.kind === "create" ? root.attachmentMode ? Object.assign(connection, {
            createRemote: true,
            remoteName: root.remoteNameText,
            collectionId: root.remoteCollectionIdText,
            homeHref: root.discoveredHomeHref
        }) : connection : Object.assign(connection, {
            remoteId: selected.id,
            remoteHref: selected.href
        });
    }

    function beginCreate() {
        root.closeCardActions();
        root.cancelRemove();
        root.formMode = true;
        root.attachmentMode = false;
        root.editingId = "";
        root.editingProfile = null;
        root.nameText = "";
        root.idText = "";
        root.colorText = "#7b9acc";
        root.typeText = "local";
        root.errorMessage = "";
        root.sourcePath = "";
        root.serverUrl = "";
        root.usernameText = "";
        root.passwordFileText = "";
        root.remoteNameText = "";
        root.remoteCollectionIdText = "";
        root.invalidateDiscovery();
        root.intervalText = "10";
        root.intervalUnit = "minutes";
        root.editingRevision = root.calendarService.subscriptions.revision;
    }

    function beginEdit(profile) {
        if (!profile || (root.conversionOpen && !root.remoteDeletionOpen) || root.calendarService.caldav.conversionBlocked?.(profile.id))
            return;
        if (root.conflictCount(profile.id) > 0) {
            root.errorMessage = "Resolve calendar conflicts first";
            return;
        }
        root.closeCardActions();
        root.cancelRemove();
        root.formMode = true;
        root.attachmentMode = false;
        root.editingId = profile.id;
        root.editingProfile = {
            id: profile.id,
            name: profile.name,
            color: profile.color,
            type: profile.type,
            visible: profile.visible
        };
        root.nameText = profile.name;
        root.idText = profile.id;
        root.colorText = profile.color;
        root.typeText = profile.type;
        root.errorMessage = "";
        root.sourcePath = "";
        root.editingRevision = profile.type === "synced" ? root.calendarService.caldav.revision : root.calendarService.subscriptions.revision;
        if (profile.type === "subscription" || profile.type === "synced") {
            const record = profile.type === "synced" ? root.calendarService.caldav.recordForId(profile.id) : root.calendarService.subscriptionForId(profile.id);
            if (!record) {
                root.errorMessage = "Subscription settings unavailable; no legacy adoption was attempted.";
                return;
            }
            root.sourcePath = record.url;
            if (profile.type === "synced") {
                root.serverUrl = record.url;
                root.usernameText = record.username;
                root.passwordFileText = record.passwordFile;
                root.remoteCalendars = [
                    {
                        id: record.remoteId,
                        href: record.remoteHref
                    }
                ];
                root.selectedRemoteIndex = 0;
            }
            root.intervalUnit = record.intervalSeconds % 86400 === 0 ? "days" : record.intervalSeconds % 3600 === 0 ? "hours" : "minutes";
            root.intervalText = String(record.intervalSeconds / (root.intervalUnit === "days" ? 86400 : root.intervalUnit === "hours" ? 3600 : 60));
        }
    }

    function showList() {
        root.closeCardActions();
        root.pickerOpen = false;
        root.formMode = false;
        root.attachmentMode = false;
        root.editingId = "";
        root.editingProfile = null;
        root.errorMessage = "";
        root.confirmingId = "";
        root.confirmingProfile = null;
        root.confirmingRevision = "";
        root.removalMessage = "";
        root.sourcePath = "";
        root.awaitingImportResult = false;
        root.subscriptionToken = 0;
        root.localRemovalToken = 0;
        root.caldavToken = 0;
        root.invalidateDiscovery();
        root.syncConversionView();
    }

    function saveProfile() {
        if (root.operationPending)
            return;
        if (root.editingConflicted) {
            root.errorMessage = "Resolve calendar conflicts first";
            return;
        }
        if (root.typeText === "subscription" && root.editingId.length === 0 && root.idText.trim().length === 0)
            root.idText = "url-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8);
        const draft = {
            id: root.idText,
            name: root.nameText,
            color: root.colorText,
            type: root.typeText
        };
        const importing = root.typeText === "imported" && root.editingId.length === 0;
        const seconds = Number(root.intervalText) * (root.intervalUnit === "days" ? 86400 : root.intervalUnit === "hours" ? 3600 : 60);
        if (["subscription", "synced"].includes(root.typeText) && (!Number.isInteger(seconds) || seconds < 300 || seconds > 2147483647)) {
            root.errorMessage = "Refresh interval must be at least 5 minutes, in whole seconds.";
            return;
        }
        if (root.typeText === "synced" && !root.syncedConnection()) {
            root.errorMessage = "Connect and select one remote calendar before Add.";
            return;
        }
        const result = root.attachmentMode ? root.calendarService.beginAttachment(root.editingId, root.syncedConnection(), seconds, root.editingProfile, root.editingRevision) : root.remoteCreateSelected ? root.calendarService.caldav.createSynced(draft, root.syncedConnection(), root.remoteNameText, root.remoteCollectionIdText, root.discoveredHomeHref, seconds) : root.typeText === "synced" ? root.calendarService.caldav.saveSynced(draft, root.syncedConnection(), seconds, root.editingId, root.editingId ? root.editingRevision : root.calendarService.caldav.revision, root.editingProfile) : root.typeText === "subscription" ? root.calendarService.saveSubscription(draft, root.sourcePath, seconds, root.editingId, root.editingRevision, root.editingProfile) : importing ? root.calendarService.importIcsProfile(draft, root.sourcePath, "", "file") : root.editingId.length > 0 ? root.calendarService.updateProfile(root.editingId, {
            name: root.nameText,
            color: root.colorText
        }) : root.calendarService.createProfile(draft);
        if (!result.ok) {
            root.errorMessage = result.message;
            return;
        }
        if (result.pending) {
            if (root.attachmentMode) {
                if (root.remoteCreateSelected) {
                    root.caldavToken = result.token;
                    root.errorMessage = "Creating remote calendar and preparing attachment...";
                    return;
                }
                root.showList();
                root.removalMessage = "Preparing attachment; local calendar and server remain unchanged until review finishes...";
                return;
            }
            if (root.typeText === "synced") {
                root.caldavToken = result.token;
                root.errorMessage = "Saving synced calendar...";
                return;
            }
            if (root.typeText === "subscription") {
                root.subscriptionToken = result.token;
                root.errorMessage = "Saving subscription settings...";
                return;
            }
            root.awaitingImportResult = true;
            root.errorMessage = "Importing ICS source...";
            return;
        }
        root.showList();
    }

    function requestRemove(profile) {
        if (!profile || root.operationPending)
            return;
        root.closeCardActions();
        if (root.confirmingId !== profile.id) {
            root.confirmingId = profile.id;
            root.confirmingProfile = {
                id: profile.id,
                name: profile.name,
                color: profile.color,
                type: profile.type,
                visible: profile.visible
            };
            root.confirmingRevision = profile.type === "synced" ? root.calendarService.caldav.revision : "";
            root.errorMessage = "";
            root.removalMessage = profile.type === "synced" ? "Delete local calendar \"" + profile.name + "\" and stop its synchronization? Unsynced changes and local conflict copies will be permanently deleted. " + (root.remoteUnavailable(profile.id) ? "No server requests will be made. Password file stays unchanged." : "Online calendar and password file remain unchanged.") : profile.type === "subscription" ? "Permanently delete local calendar \"" + profile.name + "\" and stop its subscription? Online calendar stays untouched." : profile.type === "local" ? "Permanently delete local calendar \"" + profile.name + "\" and all its events?" : profile.type === "imported" ? "Delete calendar \"" + profile.name + "\" and all its local files? This cannot be undone." : "Detach profile? Calendar data will remain on disk.";
            return;
        }
        const result = root.confirmingSynced || profile.type === "synced" ? root.calendarService.removeProfile(profile.id, root.confirmingProfile, root.confirmingRevision) : root.calendarService.removeProfile(profile.id);
        if (!result.ok)
            root.errorMessage = result.message;
        else if (result.pending) {
            if (profile.type === "local" || profile.type === "imported")
                root.localRemovalToken = result.token;
            else if (root.confirmingSynced)
                root.caldavToken = result.token;
            else
                root.subscriptionToken = result.token;
            root.errorMessage = "";
            root.removalMessage = "Removing calendar...";
        } else {
            root.confirmingId = "";
            root.removalMessage = "";
            root.syncConversionView();
        }
    }

    function cancelRemove() {
        if (root.operationPending)
            return;
        root.confirmingId = "";
        root.confirmingProfile = null;
        root.confirmingRevision = "";
        root.removalMessage = "";
        root.errorMessage = "";
        root.syncConversionView();
    }

    function refreshProfile(id) {
        if (root.remoteUnavailable(id)) {
            const result = root.calendarService.caldav.recheckAvailability(id);
            root.errorMessage = result.ok ? "" : result.message;
            if (result.pending)
                root.caldavToken = result.token;
            return;
        }
        if (root.conflictCount(id) > 0) {
            root.errorMessage = "Resolve calendar conflicts first";
            return;
        }
        if (root.calendarService.calendarById(id)?.type === "synced") {
            const result = root.calendarService.caldav.refresh(id);
            root.errorMessage = result.ok ? "" : result.message;
            if (result.pending)
                root.caldavToken = result.token;
            return;
        }
        const result = root.calendarService.refreshSubscription(id);
        root.errorMessage = result.ok ? "Refreshing subscription..." : result.message;
        if (result.pending)
            root.subscriptionToken = result.token;
    }

    function requestConversion(profile) {
        if (!profile || root.operationPending)
            return;
        root.closeCardActions();
        if (profile.type === "local") {
            root.beginEdit(profile);
            if (!root.formMode || root.editingId !== profile.id)
                return;
            root.attachmentMode = true;
            root.typeText = "synced";
            root.editingRevision = root.calendarService.caldav.revision;
            root.intervalText = "5";
            root.intervalUnit = "minutes";
            root.serverUrl = "";
            root.usernameText = "";
            root.passwordFileText = "";
            root.remoteNameText = "";
            root.remoteCollectionIdText = "";
            root.invalidateDiscovery();
            return;
        }
        if (root.remoteUnavailable(profile.id)) {
            root.requestLocalPreservation(profile);
            return;
        }
        root.cancelRemove();
        const result = root.calendarService.beginConversion(profile.id);
        root.errorMessage = result.ok ? "" : result.message;
        if (result.pending)
            root.removalMessage = "Preparing local conversion...";
        else if (result.ok)
            root.openConversionReview();
    }

    function requestRemoteDeletion(profile) {
        if (!profile || root.operationPending)
            return;
        root.closeCardActions();
        root.cancelRemove();
        const result = root.calendarService.beginRemoteDeletion(profile.id);
        root.errorMessage = result.ok ? "" : result.message;
        if (result.pending)
            root.removalMessage = "Preparing preserved local copy; server remains unchanged...";
        else if (result.ok) {
            root.syncConversionView();
            root.openConversionReview();
        }
    }

    function remoteUnavailable(id) {
        return ["deleted", "unavailable"].includes(root.calendarService.caldav.recordForId(id)?.status?.remoteState);
    }

    function requestLocalPreservation(profile) {
        if (!profile || root.operationPending || !root.remoteUnavailable(profile.id))
            return;
        root.closeCardActions();
        root.cancelRemove();
        const result = root.calendarService.caldav.beginLocalPreservation(profile.id);
        root.errorMessage = result.ok ? "" : result.message;
        if (result.pending)
            root.removalMessage = "Preparing current local events; no server requests or final sync...";
        else if (result.ok) {
            root.syncConversionView();
            root.openConversionReview();
        }
    }

    function openConversionReview() {
        root.calendarService.caldav.conversionIndex = root.attachmentOpen ? Math.max(0, root.conversionSession.conflicts.findIndex(conflict => !root.calendarService.caldav.conversionChoices.some(choice => choice.uid === conflict.uid))) : 0;
        if (root.conversionSession?.conflicts.length && (!(root.remoteDeletionOpen || root.attachmentOpen) || root.conversionSession.phase === "review"))
            root.conversionReviewRequested();
    }

    function syncConversionView() {
        if (!root.conversionSession || root.formMode || root.confirmingDeletion)
            return;
        if (root.attachmentOpen) {
            const caldav = root.calendarService.caldav;
            root.errorMessage = root.operationPending ? "" : caldav.conversionError;
            root.removalMessage = root.operationPending ? "Refreshing remote snapshot, activating calendar and synchronizing..." : caldav.conversionNeedsRetry ? "Calendar attachment paused. Retry finishes activation or cleanup. If synchronization may have started, synced data and history stay intact." : "Choose Local or Remote for every differing event or complete series. Unique events from both sides stay. After the last choice, attachment and synchronization start automatically.";
            return;
        }
        if (root.localPreservationOpen) {
            const caldav = root.calendarService.caldav;
            const name = root.calendarService.calendarById(root.conversionSession.id)?.name || root.conversionSession.profile?.name;
            root.errorMessage = root.operationPending ? "" : caldav.conversionError;
            root.removalMessage = root.operationPending ? "Preserving local calendar without final sync or server requests..." : caldav.conversionNeedsRetry ? "Local preservation paused. Retry rebuilds local review or completes local activation/cleanup. No server requests, uploads or DELETE." : caldav.conversionReady ? "Keep \"" + name + "\" as a local calendar? Preserve currently available local events and unsynced changes. Events never downloaded cannot be recovered. No final sync, server requests or uploads; password file stays unchanged." : "Review locally stored versions to preserve. Server cards show previously captured versions, not live data. No server requests or uploads.";
            return;
        }
        if (root.remoteDeletionOpen) {
            const caldav = root.calendarService.caldav;
            if (root.operationPending) {
                root.errorMessage = "";
                root.removalMessage = caldav.pending?.action === "remote-delete-cancel" ? "Restoring previous synchronization..." : caldav.pending?.action === "remote-delete-retry" ? "Checking outcome or finishing local cleanup..." : "Preparing preservation or deleting remote calendar...";
            } else {
                root.errorMessage = caldav.conversionError;
                const target = root.conversionSession.target;
                const name = root.calendarService.calendarById(root.conversionSession.id)?.name || root.conversionSession.profile?.name || root.conversionSession.id;
                const refreshed = caldav.conversionResult?.reviewChanged ? "Remote contents changed or review was interrupted; confirm again. " : "";
                root.removalMessage = caldav.conversionNeedsRetry ? root.conversionSession.remoteAttempted ? "Preserved events retained. Retry performs one read-only check or finishes local activation/cleanup; it never repeats DELETE or uploads. Close keeps this operation pending." : "Review interrupted or could not finish. Retry rebuilds review without DELETE; Cancel restores previous synchronization." : caldav.conversionReady ? refreshed + "Delete from server, keep local: \"" + name + "\" (collection \"" + target.remoteId + "\", " + target.url + " → " + target.remoteHref + ")? The entire remote collection and its events disappear from the server and other syncing clients lose access. Only this machine keeps the reviewed local calendar. No final upload. Do not edit from other devices during the final check/delete gap; no server-wide lock is guaranteed. Password file stays unchanged." : refreshed + "Synchronization paused. Review each local/remote version to keep locally. Choices stay offline; nothing is uploaded.";
            }
            return;
        }
        if (root.operationPending) {
            root.errorMessage = "";
            root.removalMessage = root.calendarService.caldav.pending?.action === "convert-cancel" ? "Cancelling conversion..." : "Converting calendar...";
        } else {
            root.errorMessage = root.calendarService.caldav.conversionError;
            const name = root.calendarService.calendarById(root.conversionSession.id)?.name || root.conversionSession.id;
            root.removalMessage = root.conversionSession.remoteAttempted ? "" : root.calendarService.caldav.conversionReady ? "Sync \"" + name + "\" once, then convert it to a local calendar? Other pending additions, edits and deletions may also synchronize. Choices marked \"Keep local, leave server unchanged\" stay local. Online calendar and password file remain." : "Synchronization paused. Review every conflict before converting this calendar.";
        }
    }

    function showConversionResult(autoReview) {
        const result = root.calendarService.caldav.conversionResult;
        if (!result) {
            root.syncConversionView();
            return;
        }
        if (result.cancelled || result.rolledBack || result.completed || (result.converted && !root.remoteDeletionOpen && result.kind !== "local-to-synced")) {
            root.showList();
            root.errorMessage = !result.ok || result.activationWarning || result.cleanupWarning ? result.message : "";
            root.removalMessage = root.errorMessage ? "" : result.completed ? result.kind === "local-to-synced" ? "Calendar attached and synchronized." : result.kind === "local-preserve" ? "Calendar kept locally; no server changes attempted." : "Remote calendar deleted; reviewed events kept locally." : result.converted ? "Calendar converted to local." : "";
        } else if (!result.ok)
            root.errorMessage = root.calendarService.caldav.conversionError || result.message;
        root.syncConversionView();
        if (autoReview && (result.action === "attach-begin" || result.action === "convert-begin" || result.action === "remote-delete-begin" || result.action === "local-preserve-begin" || result.reviewChanged) && result.ok && !root.calendarService.caldav.conversionReady)
            root.openConversionReview();
    }

    function confirmConversion() {
        if (!root.lifecycleOpen)
            return;
        const result = root.calendarService.caldav.finishConversion();
        if (!result.ok)
            root.errorMessage = result.message;
        else {
            root.errorMessage = "";
            root.removalMessage = root.remoteDeletionOpen ? "Deleting remote calendar; preserving local events..." : "Converting calendar...";
        }
    }

    function retryConversion() {
        const result = root.calendarService.caldav.retryConversion();
        if (!result.ok)
            root.errorMessage = result.message;
        else {
            root.errorMessage = "";
            root.removalMessage = "Checking remote outcome or finishing local cleanup...";
        }
    }

    function closePanel() {
        if (root.operationPending)
            return;
        if (root.confirmingDeletion) {
            root.cancelRemove();
            return;
        }
        if (root.conversionOpen && root.calendarService.caldav.conversionCanCancel !== false) {
            const result = root.calendarService.caldav.cancelConversion();
            if (!result.ok)
                root.errorMessage = result.message;
            else
                root.removalMessage = "Cancelling conversion...";
        } else
            root.closeRequested();
    }

    function conflictCount(id) {
        return root.calendarService.conflictService?.conflicts?.filter(conflict => conflict.calendarId === id).length || 0;
    }

    function subscriptionStatus(id, compact) {
        const backend = root.calendarService.calendarById(id)?.type === "synced" ? root.calendarService.caldav : root.calendarService.subscriptions;
        const conversion = backend.conversions?.find(session => session.id === id);
        if (conversion)
            return compact ? conversion.disconnected ? "Sync disconnected" : conversion.kind === "remote-delete" ? "Remote deletion paused" : "Conversion paused" : (conversion.disconnected ? "Sync disconnected. " : conversion.kind === "remote-delete" ? "Sync paused for remote deletion. " : "Sync paused for conversion. ") + "Recovery files: " + conversion.recoveryPaths.join(", ");
        const record = backend.recordForId(id);
        if (!backend.ready || !record)
            return compact ? "Unavailable" : backend.errorMessage || "Calendar settings unavailable";
        const status = record.status || {};
        if (root.remoteUnavailable(id))
            return compact ? (status.remoteState === "deleted" ? "Remote calendar deleted" : "Remote calendar unavailable") + " · Sync paused" : status.error + " Keep as local preserves this machine's available events; delete from this device removes local events including unsynced changes. Check again only tests availability.";
        const count = root.conflictCount(id);
        const conflicts = count > 0 ? count + (count === 1 ? " conflict" : " conflicts") : "";
        const success = new Date(Number(status.lastSuccessMs));
        const last = success.getTime() > 0 ? (compact ? "Updated " : "Last success: ") + Qt.formatDateTime(success, compact ? "dd MMM, hh:mm" : "dd MMM yyyy, hh:mm:ss t") : "No successful refresh yet";
        if (compact)
            return status.busy ? "Refreshing" : conflicts || (status.error ? "Refresh failed" : last);
        return (status.busy ? "Refreshing · " : "") + (conflicts ? conflicts + " · Resolve calendar conflicts first · " : "") + (status.error ? status.error + " · " : "") + last;
    }

    Component.onCompleted: {
        root.calendarService.subscriptions.reload();
        root.calendarService.caldav.reload();
        root.showConversionResult(false);
    }
    onConversionSessionChanged: Qt.callLater(root.syncConversionView)
    onOperationPendingChanged: {
        if (root.operationPending)
            root.closeCardActions();
        root.syncConversionView();
    }

    Connections {
        target: root.calendarService.caldav
        ignoreUnknownSignals: true
        function onConversionResultChanged() {
            Qt.callLater(() => root.showConversionResult(true));
        }
        function onConversionChoicesChanged() {
            root.syncConversionView();
        }
    }
    onVisibleChanged: {
        if (visible)
            root.calendarService.caldav.reload();
        else
            root.closeCardActions();
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.48)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
                root.closePanel();
            }
        }
    }

    function pickerLocalPath(path) {
        return path.replace(/^\/+proc\/self\/root(?=\/|$)/, "").replace(/^\/+/, "/") || "/";
    }

    function navigatePicker(path) {
        root.pickerPath = root.pickerLocalPath(path);
    }

    function pickerParent() {
        const path = root.pickerPath.replace(/\/+$/, "");
        return path.slice(0, path.lastIndexOf("/")) || "/";
    }

    function pickerFolderUrl() {
        const path = root.pickerPath.replace(/^\/+/, "");
        // ponytail: Linux /proc/self/root bypasses Qt's second URL parse; remove when Qt fixes resolvePath.
        return path ? "file:////proc/self/root/" + path.split("/").map(encodeURIComponent).join("/") : "file:///";
    }

    FolderListModel {
        id: folderModel
        folder: root.pickerFolderUrl()
        showDirs: true
        showFiles: true
        showHidden: true
        showDirsFirst: true
        nameFilters: root.typeText === "synced" ? ["*"] : ["*.ics"]
        sortField: FolderListModel.Name
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(460, Math.max(0, parent.width - 48))
        height: Math.min(parent.height - 48, root.formMode ? 680 : 420)
        color: Theme.surface
        radius: 13
        border.width: 1
        border.color: Theme.border
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => mouse.accepted = true
        }

        Rectangle {
            id: panelHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 13
            height: 50
            radius: 13
            color: Theme.surfaceRaised

            Text {
                anchors.centerIn: parent
                text: root.formMode ? (root.attachmentMode ? "Attach local calendar" : root.editingId.length > 0 ? "Edit calendar" : "New calendar") : "Manage calendars"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 21
                font.weight: Font.DemiBold
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.top: panelHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.margins: 20
            spacing: 10

            Controls.ScrollView {
                id: managerScroll
                objectName: "calendarManagerScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                contentHeight: root.formMode ? panelContent.implicitHeight : availableHeight
                Controls.ScrollBar.vertical.policy: root.formMode ? Controls.ScrollBar.AlwaysOff : Controls.ScrollBar.AsNeeded
                Loader {
                    id: panelContent
                    enabled: !root.operationPending
                    width: managerScroll.availableWidth
                    height: root.formMode ? implicitHeight : managerScroll.availableHeight
                    sourceComponent: root.formMode ? formComponent : listComponent
                }
            }

            Controls.ScrollView {
                id: messageScroll
                objectName: "calendarManagerMessages"
                visible: root.errorMessage.length > 0 || root.removalMessage.length > 0
                Layout.fillWidth: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: messageText.implicitHeight
                Layout.maximumHeight: contentColumn.height / 2
                Layout.leftMargin: root.formMode ? root.formTextInset : 0
                Layout.rightMargin: root.formMode ? root.formTextInset : 0
                contentWidth: availableWidth
                contentHeight: messageText.implicitHeight
                clip: true
                Text {
                    id: messageText
                    width: messageScroll.availableWidth
                    text: root.errorMessage.length > 0 ? root.errorMessage : root.removalMessage
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    color: root.errorMessage.length > 0 ? Theme.currentTime : Theme.textMuted
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }

        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 58

            ActionButton {
                id: footerPrimary
                objectName: "calendarManagerPrimary"
                anchors.left: parent.left
                anchors.leftMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                minimumWidth: 86
                enabled: !root.operationPending && !root.editingConflicted
                label: root.lifecycleOpen ? root.calendarService.caldav.conversionNeedsRetry ? "Retry" : root.calendarService.caldav.conversionReady ? root.remoteDeletionOpen ? "Delete remote" : root.localPreservationOpen ? "Keep local" : "Convert" : "Review conflicts" : root.confirmingDeletion ? "Delete" : root.formMode ? (root.attachmentMode ? root.remoteCreateSelected ? "Create and attach" : "Attach and sync" : root.remoteCreateSelected ? "Create and add" : root.typeText === "imported" && root.editingId.length === 0 ? "Import" : root.typeText === "synced" && root.editingId.length === 0 ? "Add" : "Save") : "New calendar"
                primary: root.formMode || root.lifecycleOpen
                destructive: root.confirmingDeletion || (root.lifecycleOpen && root.remoteDeletionOpen && root.calendarService.caldav.conversionReady)
                activeFocusOnTab: enabled
                Accessible.role: Accessible.Button
                Accessible.name: root.lifecycleOpen && root.remoteDeletionOpen && root.calendarService.caldav.conversionReady ? "Delete from server, keep local" : label
                Accessible.onPressAction: clicked()
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                        return;
                    clicked();
                    event.accepted = true;
                }
                onClicked: root.lifecycleOpen ? root.calendarService.caldav.conversionNeedsRetry ? root.retryConversion() : root.calendarService.caldav.conversionReady ? root.confirmConversion() : root.openConversionReview() : root.confirmingDeletion ? root.requestRemove(root.calendarService.calendarById(root.confirmingId)) : root.formMode ? root.saveProfile() : root.beginCreate()
            }

            ActionButton {
                x: footerPrimary.x + footerPrimary.width + (footerCancel.x - footerPrimary.x - footerPrimary.width - width) / 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                visible: root.lifecycleOpen && root.calendarService.caldav.conversionReady && root.conversionSession.conflicts.length > 0
                enabled: !root.operationPending
                label: card.width < 420 ? "Choices" : "Review choices"
                minimumWidth: card.width < 420 ? 60 : 80
                onClicked: root.openConversionReview()
            }

            ActionButton {
                objectName: "calendarManagerConflicts"
                width: Math.max(0, Math.min(implicitWidth, footerCancel.x - footerPrimary.x - footerPrimary.width - 16))
                x: footerPrimary.x + footerPrimary.width + (footerCancel.x - footerPrimary.x - footerPrimary.width - width) / 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                visible: !root.formMode && root.confirmingId.length === 0 && !root.conversionSession && root.ordinaryConflictCount > 0
                enabled: visible && !root.operationPending
                label: (card.width < 420 ? "Conflicts (" : "Resolve conflicts (") + root.ordinaryConflictCount + ")"
                primary: true
                accentColor: Theme.warning
                minimumWidth: 0
                activeFocusOnTab: true
                border.width: activeFocus ? 1 : 0
                border.color: Theme.text
                Accessible.role: Accessible.Button
                Accessible.name: "Resolve calendar conflicts (" + root.ordinaryConflictCount + " unresolved)"
                Accessible.onPressAction: clicked()
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                        return;
                    clicked();
                    event.accepted = true;
                }
                onClicked: root.conflictResolutionRequested()
            }

            ActionButton {
                id: footerCancel
                anchors.right: parent.right
                objectName: "calendarManagerCancel"
                anchors.rightMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                minimumWidth: 86
                // Cancel discards discovery results; read-only worker finishes its own cleanup.
                enabled: !root.operationPending || root.calendarService.caldav?.pending?.action === "discover"
                label: root.lifecycleOpen ? root.calendarService.caldav.conversionCanCancel !== false ? "Cancel" : "Close" : root.confirmingDeletion || root.formMode ? "Cancel" : "Close"
                activeFocusOnTab: enabled
                border.color: activeFocus ? Theme.text : Theme.border
                Accessible.role: Accessible.Button
                Accessible.name: label
                Accessible.onPressAction: clicked()
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                        return;
                    clicked();
                    event.accepted = true;
                }
                onClicked: root.lifecycleOpen ? root.closePanel() : root.confirmingDeletion ? root.cancelRemove() : root.formMode ? root.showList() : root.closePanel()
            }
        }
    }

    Connections {
        target: root.calendarService
        function onCaldavResultChanged() {
            const result = root.calendarService.caldavResult;
            const attachmentCreation = result?.action === "attach-begin" && root.attachmentMode;
            if ((!attachmentCreation && result?.action?.startsWith("attach-")) || result?.action?.startsWith("convert-") || result?.action?.startsWith("remote-delete-") || result?.action === "local-preserve-begin")
                return;
            if (!result || !root.caldavToken || result.token !== root.caldavToken)
                return;
            root.caldavToken = 0;
            if ((result.action === "create" || attachmentCreation) && result.remoteCreated && result.remoteId && result.remoteHref) {
                const created = {
                    id: result.remoteId,
                    href: result.remoteHref
                };
                const existing = root.remoteCalendars.findIndex(calendar => calendar.href === created.href);
                if (existing < 0)
                    root.remoteCalendars = root.remoteCalendars.concat([created]);
                root.selectedRemoteIndex = existing < 0 ? root.remoteCalendars.length - 1 : existing;
            } else if ((result.action === "create" || attachmentCreation) && result.creationUncertain) {
                root.invalidateDiscovery(); // Reconnect/select explicitly; never turn unknown ownership into Add.
            }
            if (!result.ok) {
                root.errorMessage = result.message;
                if (result.action === "remove")
                    root.removalMessage = "";
            } else if (result.action === "discover") {
                root.remoteCalendars = result.calendars;
                root.discoveredHomeHref = result.homeHref || "";
                root.selectedRemoteIndex = result.calendars.length === 1 ? 0 : -1;
                root.errorMessage = result.calendars.length ? "" : "No calendars found.";
            } else if (result.action === "save" || result.action === "create" || attachmentCreation)
                root.showList();
            else if (result.action === "remove") {
                root.confirmingId = "";
                root.confirmingProfile = null;
                root.confirmingRevision = "";
                root.removalMessage = "";
                root.errorMessage = result.cleanupWarning ? result.message : "";
                root.syncConversionView();
            } else
                root.errorMessage = "";
        }
        function onLocalRemovalResultChanged() {
            const result = root.calendarService.localRemovalResult;
            if (!result || !root.localRemovalToken || result.token !== root.localRemovalToken)
                return;
            root.localRemovalToken = 0;
            root.errorMessage = !result.ok || result.cleanupWarning ? result.message : "";
            if (result.ok) {
                root.confirmingId = "";
                root.removalMessage = "";
                root.syncConversionView();
            }
        }
        function onImportResultChanged() {
            const result = root.calendarService.importResult;
            if (!result || !root.awaitingImportResult)
                return;
            root.awaitingImportResult = false;
            if (!result.ok)
                root.errorMessage = result.message;
            else {
                root.showList();
                if (result.cleanupWarning)
                    root.errorMessage = result.message;
            }
        }
        function onSubscriptionResultChanged() {
            const result = root.calendarService.subscriptionResult;
            if (!result || !root.subscriptionToken || result.token !== root.subscriptionToken)
                return;
            root.subscriptionToken = 0;
            if (!result.ok)
                root.errorMessage = result.message;
            else if (result.action === "save")
                root.showList();
            else {
                root.errorMessage = result.cleanupWarning ? result.message : "";
                root.confirmingId = "";
                root.removalMessage = "";
                root.syncConversionView();
            }
        }
    }

    Component {
        id: listComponent

        ListView {
            clip: true
            spacing: 7
            model: root.calendarService.calendars
            delegate: Rectangle {
                id: calendarEntry
                required property var modelData
                readonly property int conflictCount: root.conflictCount(calendarEntry.modelData.id)
                readonly property bool conversionTarget: root.conversionSession?.id === calendarEntry.modelData.id
                readonly property bool managedSynced: calendarEntry.modelData.type === "synced" && root.calendarService.caldav.recordForId(calendarEntry.modelData.id) !== null
                readonly property bool remoteUnavailable: calendarEntry.managedSynced && root.remoteUnavailable(calendarEntry.modelData.id)
                readonly property bool canConvert: (calendarEntry.modelData.type === "local" && calendarEntry.modelData.ready) || calendarEntry.managedSynced
                readonly property bool canRemove: ["local", "imported", "subscription", "synced"].includes(calendarEntry.modelData.type)
                readonly property bool actionsExpanded: root.expandedActionId === calendarEntry.modelData.id && (root.expandedActionKind === "conversion" ? calendarEntry.canConvert : root.expandedActionKind === "removal" && calendarEntry.canRemove)
                width: ListView.view.width
                height: calendarEntry.actionsExpanded ? 92 : 52
                color: calendarEntry.conversionTarget ? Qt.alpha(Theme.accent, 0.10) : Theme.background
                radius: Theme.radius
                border.width: calendarEntry.conversionTarget ? 2 : 1
                border.color: calendarEntry.conversionTarget ? Theme.accent : Theme.border
                HoverHandler {
                    id: actionsHover
                }

                RowLayout {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 52
                    anchors.leftMargin: 13
                    anchors.rightMargin: 7
                    spacing: 10

                    Rectangle {
                        Layout.minimumWidth: 9
                        Layout.preferredWidth: 9
                        Layout.maximumWidth: 9
                        Layout.preferredHeight: 9
                        radius: 5
                        color: calendarEntry.modelData.color
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: calendarEntry.modelData.name
                            textFormat: Text.PlainText
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            id: calendarSummary
                            objectName: calendarEntry.remoteUnavailable ? "calendarRemoteWarning" : ""
                            readonly property string details: (calendarEntry.modelData.errorMessage ? calendarEntry.modelData.errorMessage + "\n" : calendarEntry.modelData.missing ? "Calendar data is missing\n" : "") + (["subscription", "synced"].includes(calendarEntry.modelData.type) ? root.subscriptionStatus(calendarEntry.modelData.id) : text)
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: calendarEntry.modelData.type + (calendarEntry.modelData.missing ? " · Missing" : calendarEntry.modelData.errorMessage ? " · Error" : ["subscription", "synced"].includes(calendarEntry.modelData.type) ? " · " + root.subscriptionStatus(calendarEntry.modelData.id, true) : "")
                            textFormat: Text.PlainText
                            color: Theme.textMuted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Accessible.description: calendarSummary.details
                            HoverHandler {
                                id: summaryHover
                            }
                            Controls.ToolTip {
                                id: summaryTooltip
                                parent: calendarActions.hoveredControl || calendarSummary
                                readonly property point targetPosition: parent.mapToItem(root, 0, 0)
                                x: Math.max(6 - targetPosition.x, Math.min((parent.width - width) / 2, root.width - width - 6 - targetPosition.x))
                                y: targetPosition.y + parent.height + height + 12 <= root.height ? parent.height + 6 : -height - 6
                                margins: 6
                                visible: calendarActions.hoveredControl !== null || (["subscription", "synced"].includes(calendarEntry.modelData.type) && summaryHover.hovered)
                                delay: 400
                                text: calendarActions.hoveredControl === conversionButton ? "Conversion options" : calendarActions.hoveredControl === removalButton ? "Removal options" : calendarActions.hoveredControl ? "Resolve calendar conflicts first" : calendarSummary.details
                                font.family: Theme.font
                                font.pixelSize: 11
                                padding: 6
                                leftPadding: 8
                                rightPadding: 8
                                width: Math.min(300, Math.max(0, root.width - 48), implicitWidth)
                                background: Rectangle {
                                    color: Theme.surfaceRaised
                                    radius: Theme.radius
                                    border.width: 1
                                    border.color: Theme.border
                                }
                                contentItem: Text {
                                    text: summaryTooltip.text
                                    textFormat: Text.PlainText
                                    font: summaryTooltip.font
                                    color: Theme.text
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    RowLayout {
                        id: calendarActions
                        readonly property Item hoveredControl: actionsHover.hovered ? [conversionButton, removalButton, refreshButton, settingsButton].find(button => button.visible && (button === conversionButton || button === removalButton || (calendarActions.enabled && calendarEntry.conflictCount > 0 && !(button === refreshButton && calendarEntry.remoteUnavailable))) && button.contains(button.mapFromItem(calendarEntry, actionsHover.point.position.x, actionsHover.point.position.y))) || null : null
                        Layout.fillWidth: false
                        Layout.alignment: Qt.AlignRight
                        spacing: 4
                        enabled: !root.conversionOpen || root.remoteDeletionOpen

                        GlyphButton {
                            id: conversionButton
                            objectName: calendarEntry.modelData.type === "local" ? "calendarConvertToRemote" : "calendarConvertToLocal"
                            visible: calendarEntry.canConvert
                            enabled: visible && !root.operationPending && root.calendarService.caldav.ready && !(root.remoteDeletionOpen && root.calendarService.caldav.conversionBlocked?.(calendarEntry.modelData.id)) && !root.calendarService.caldav.conversions?.find(session => session.id === calendarEntry.modelData.id)?.remoteAttempted
                            label: ""
                            Canvas {
                                id: conversionSymbol
                                objectName: "calendarConversionSymbol"
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                readonly property color ink: conversionButton.iconColor
                                onInkChanged: requestPaint()
                                onPaint: {
                                    const context = getContext("2d");
                                    context.clearRect(0, 0, width, height);
                                    context.strokeStyle = conversionSymbol.ink;
                                    context.lineWidth = 1.5;
                                    context.lineCap = "round";
                                    context.lineJoin = "round";
                                    context.beginPath();
                                    context.moveTo(2, 5);
                                    context.lineTo(14, 5);
                                    context.moveTo(11, 2);
                                    context.lineTo(14, 5);
                                    context.lineTo(11, 8);
                                    context.moveTo(14, 11);
                                    context.lineTo(2, 11);
                                    context.moveTo(5, 8);
                                    context.lineTo(2, 11);
                                    context.lineTo(5, 14);
                                    context.stroke();
                                }
                            }
                            activeFocusOnTab: enabled
                            border.width: activeFocus || (calendarEntry.actionsExpanded && root.expandedActionKind === "conversion") ? 1 : 0
                            border.color: Theme.accent
                            Accessible.role: Accessible.Button
                            Accessible.name: "Conversion options"
                            Accessible.expanded: calendarEntry.actionsExpanded && root.expandedActionKind === "conversion"
                            Accessible.onPressAction: conversionButton.clicked()
                            Keys.onPressed: event => {
                                if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                    return;
                                conversionButton.clicked();
                                event.accepted = true;
                            }
                            onClicked: {
                                conversionButton.forceActiveFocus();
                                root.toggleCardActions(calendarEntry.modelData.id, "conversion");
                            }
                        }

                        GlyphButton {
                            id: refreshButton
                            objectName: calendarEntry.remoteUnavailable ? "calendarCheckRemote" : "calendarRefresh"
                            visible: ["subscription", "synced"].includes(calendarEntry.modelData.type)
                            label: "󰑐"
                            enabled: (calendarEntry.conflictCount === 0 || calendarEntry.remoteUnavailable) && (calendarEntry.modelData.type === "synced" ? root.calendarService.caldav.ready && !root.calendarService.caldav.conversionBlocked?.(calendarEntry.modelData.id) && !root.calendarService.caldav.recordForId(calendarEntry.modelData.id)?.status?.busy : root.calendarService.subscriptions.ready && !root.calendarService.subscriptionForId(calendarEntry.modelData.id)?.status?.busy)
                            Accessible.role: Accessible.Button
                            Accessible.name: calendarEntry.remoteUnavailable ? "Check remote availability" : "Refresh calendar"
                            Accessible.description: calendarEntry.remoteUnavailable ? "Read-only availability check; does not synchronize or upload" : calendarEntry.conflictCount > 0 ? "Resolve calendar conflicts first" : ""
                            activeFocusOnTab: enabled
                            Accessible.onPressAction: refreshButton.clicked()
                            Keys.onPressed: event => {
                                if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                    return;
                                refreshButton.clicked();
                                event.accepted = true;
                            }
                            onClicked: root.refreshProfile(calendarEntry.modelData.id)
                        }

                        GlyphButton {
                            visible: calendarEntry.modelData.type !== "imported" || calendarEntry.modelData.ready
                            label: calendarEntry.modelData.visible ? "󰈈" : "󰈉"
                            enabled: !root.calendarService.caldav.conversionBlocked?.(calendarEntry.modelData.id)
                            onClicked: root.calendarService.setCalendarVisible(calendarEntry.modelData.id, !calendarEntry.modelData.visible)
                        }
                        GlyphButton {
                            id: settingsButton
                            visible: calendarEntry.modelData.type !== "imported" || calendarEntry.modelData.ready
                            label: "󰏫"
                            enabled: calendarEntry.conflictCount === 0 && !root.calendarService.caldav.conversionBlocked?.(calendarEntry.modelData.id)
                            Accessible.role: Accessible.Button
                            Accessible.name: "Edit calendar settings"
                            Accessible.description: calendarEntry.conflictCount > 0 ? "Resolve calendar conflicts first" : ""
                            onClicked: root.beginEdit(calendarEntry.modelData)
                        }
                        GlyphButton {
                            id: removalButton
                            objectName: "calendarRemovalOptions"
                            visible: calendarEntry.canRemove
                            label: "󰆴"
                            enabled: !root.calendarService.caldav.conversionBlocked?.(calendarEntry.modelData.id) && (calendarEntry.modelData.type !== "synced" || root.calendarService.caldav.ready)
                            activeFocusOnTab: enabled
                            border.width: activeFocus || (calendarEntry.actionsExpanded && root.expandedActionKind === "removal") ? 1 : 0
                            border.color: Theme.accent
                            Accessible.role: Accessible.Button
                            Accessible.name: "Removal options"
                            Accessible.expanded: calendarEntry.actionsExpanded && root.expandedActionKind === "removal"
                            Accessible.onPressAction: removalButton.clicked()
                            Keys.onPressed: event => {
                                if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                    return;
                                removalButton.clicked();
                                event.accepted = true;
                            }
                            onClicked: {
                                removalButton.forceActiveFocus();
                                root.toggleCardActions(calendarEntry.modelData.id, "removal");
                            }
                        }
                    }
                }
                RowLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: 13
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    height: 28
                    spacing: 6
                    visible: calendarEntry.actionsExpanded
                    enabled: visible && !root.operationPending && (!root.conversionOpen || root.remoteDeletionOpen)
                    Item {
                        Layout.fillWidth: true
                    }
                    ActionButton {
                        objectName: calendarEntry.modelData.type === "local" ? "calendarAttachRemote" : "calendarConvertLocal"
                        visible: root.expandedActionKind === "conversion" && !calendarEntry.remoteUnavailable
                        enabled: visible && conversionButton.enabled
                        label: calendarEntry.modelData.type === "local" ? "Attach to remote" : "Convert to local"
                        Layout.preferredHeight: 28
                        activeFocusOnTab: enabled
                        Accessible.role: Accessible.Button
                        Accessible.name: calendarEntry.modelData.type === "local" ? "Attach to remote calendar" : label
                        Accessible.onPressAction: clicked()
                        Keys.onPressed: event => {
                            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                return;
                            clicked();
                            event.accepted = true;
                        }
                        onClicked: root.requestConversion(calendarEntry.modelData)
                    }
                    ActionButton {
                        objectName: "calendarKeepLocal"
                        visible: root.expandedActionKind === "conversion" && calendarEntry.remoteUnavailable
                        enabled: visible && conversionButton.enabled
                        label: "Keep local"
                        Layout.preferredHeight: 28
                        activeFocusOnTab: enabled
                        Accessible.role: Accessible.Button
                        Accessible.name: "Keep as local calendar"
                        Accessible.onPressAction: clicked()
                        Keys.onPressed: event => {
                            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                return;
                            clicked();
                            event.accepted = true;
                        }
                        onClicked: root.requestLocalPreservation(calendarEntry.modelData)
                    }
                    ActionButton {
                        objectName: calendarEntry.remoteUnavailable ? "calendarDeleteUnavailable" : "calendarDeleteLocal"
                        visible: root.expandedActionKind === "removal"
                        enabled: visible && removalButton.enabled
                        label: "Delete local"
                        Layout.preferredHeight: 28
                        destructive: true
                        activeFocusOnTab: enabled
                        Accessible.role: Accessible.Button
                        Accessible.name: "Delete calendar from this device"
                        Accessible.onPressAction: clicked()
                        Keys.onPressed: event => {
                            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                return;
                            clicked();
                            event.accepted = true;
                        }
                        onClicked: root.requestRemove(calendarEntry.modelData)
                    }
                    ActionButton {
                        objectName: "calendarDeleteRemote"
                        visible: root.expandedActionKind === "removal" && calendarEntry.managedSynced && !calendarEntry.remoteUnavailable
                        enabled: visible && root.calendarService.caldav.ready && !root.calendarService.caldav.conversionBlocked?.(calendarEntry.modelData.id)
                        label: "Delete remote"
                        Layout.preferredHeight: 28
                        destructive: true
                        activeFocusOnTab: enabled
                        Accessible.role: Accessible.Button
                        Accessible.name: "Delete from server, keep local"
                        Accessible.onPressAction: clicked()
                        Keys.onPressed: event => {
                            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                return;
                            clicked();
                            event.accepted = true;
                        }
                        onClicked: root.requestRemoteDeletion(calendarEntry.modelData)
                    }
                }
            }
        }
    }

    Component {
        id: formComponent

        ColumnLayout {
            enabled: !root.operationPending && !root.editingConflicted
            opacity: enabled ? 1 : 0.4
            spacing: 5

            FormHint {
                visible: root.editingConflicted
                text: "Resolve calendar conflicts first"
            }

            FieldLabel {
                text: "NAME"
            }
            FormField {
                text: root.nameText
                enabled: !root.attachmentMode
                placeholderText: "Calendar name"
                onTextEdited: root.nameText = text
            }
            FieldLabel {
                text: "ID"
                Layout.topMargin: 10
            }
            FormField {
                text: root.idText
                placeholderText: "lowercase-id"
                enabled: root.editingId.length === 0
                onTextEdited: root.idText = text
            }
            FieldLabel {
                text: "TYPE"
                Layout.topMargin: 10
            }
            InlineWheelField {
                id: typePicker
                label: ""
                model: ["local", "imported", "subscription", "synced"]
                currentIndex: root.typeText === "synced" ? 3 : root.typeText === "subscription" ? 2 : root.typeText === "imported" ? 1 : 0
                displayText: root.typeText
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                enabled: root.editingId.length === 0
                onExpansionRequested: expanded = !expanded
                onCollapseRequested: expanded = false
                onSelectionRequested: (index, value) => root.typeText = String(value)
            }
            FieldLabel {
                visible: root.typeText === "subscription"
                text: "DIRECT CALENDAR URL"
                Layout.topMargin: 10
            }
            FieldLabel {
                visible: root.typeText === "synced"
                text: "CALDAV SERVER URL"
                Layout.topMargin: 10
            }
            FormField {
                objectName: "calendarCalDavServer"
                visible: root.typeText === "synced"
                enabled: root.editingId.length === 0 || root.attachmentMode
                text: root.serverUrl
                placeholderText: "https://server/"
                onTextEdited: root.serverUrl = text
            }
            FieldLabel {
                visible: root.typeText === "synced"
                text: "USERNAME"
                Layout.topMargin: 10
            }
            FormField {
                visible: root.typeText === "synced"
                enabled: root.editingId.length === 0 || root.attachmentMode
                text: root.usernameText
                onTextEdited: root.usernameText = text
            }
            FieldLabel {
                visible: root.typeText === "synced"
                text: "EXISTING PASSWORD FILE"
                Layout.topMargin: 10
            }
            Controls.Button {
                id: passwordSelector
                objectName: "calendarCalDavPassword"
                visible: root.typeText === "synced"
                enabled: root.editingId.length === 0 || root.attachmentMode
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                leftPadding: 10
                rightPadding: 10
                text: root.passwordFileText || "Choose an existing password file"
                onClicked: root.pickerOpen = !root.pickerOpen
                contentItem: Text {
                    text: passwordSelector.text
                    textFormat: Text.PlainText
                    color: root.passwordFileText.length > 0 ? Theme.text : Theme.textMuted
                    font.family: Theme.font
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
                background: Rectangle {
                    color: passwordSelector.down ? Qt.darker(Theme.surfaceRaised, 1.2) : Theme.background
                    radius: Theme.radius
                    border.width: 1
                    border.color: Theme.border
                }
            }
            ActionButton {
                visible: root.typeText === "synced" && (root.editingId.length === 0 || root.attachmentMode)
                label: "Connect"
                onClicked: root.connectCalDav()
            }
            InlineWheelField {
                objectName: "calendarCalDavRemote"
                visible: root.typeText === "synced"
                enabled: (root.editingId.length === 0 || root.attachmentMode) && root.remotePickerEntries.length > 0
                label: ""
                model: root.remotePickerEntries.map(entry => entry.label)
                currentIndex: root.selectedRemoteIndex
                displayText: root.remotePickerEntries[root.selectedRemoteIndex]?.label || "Select remote calendar"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                onExpansionRequested: expanded = !expanded
                onCollapseRequested: expanded = false
                onSelectionRequested: (index, value) => root.selectedRemoteIndex = index
            }
            FieldLabel {
                visible: root.remoteCreateSelected
                text: "REMOTE CALENDAR NAME"
                Layout.topMargin: 10
            }
            FormField {
                objectName: "calendarCalDavRemoteName"
                visible: root.remoteCreateSelected
                text: root.remoteNameText
                placeholderText: "Display name on server"
                Accessible.name: "Remote calendar name"
                onTextEdited: root.remoteNameText = text
            }
            FieldLabel {
                visible: root.remoteCreateSelected
                text: "COLLECTION IDENTIFIER"
                Layout.topMargin: 10
            }
            FormField {
                objectName: "calendarCalDavCollectionId"
                visible: root.remoteCreateSelected
                text: root.remoteCollectionIdText
                placeholderText: "lowercase-id, independent of local ID"
                Accessible.name: "Collection identifier"
                onTextEdited: root.remoteCollectionIdText = text
            }
            FormField {
                objectName: "calendarSubscriptionUrl"
                visible: root.typeText === "subscription"
                text: root.sourcePath
                placeholderText: "Direct HTTP(S) or webcal calendar link"
                onTextEdited: root.sourcePath = text
            }
            FieldLabel {
                visible: ["subscription", "synced"].includes(root.typeText)
                text: "REFRESH INTERVAL · MINIMUM 5 MINUTES"
                Layout.topMargin: 10
            }
            RowLayout {
                visible: ["subscription", "synced"].includes(root.typeText)
                Layout.fillWidth: true
                FormField {
                    objectName: "calendarSubscriptionInterval"
                    text: root.intervalText
                    placeholderText: "10"
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onTextEdited: root.intervalText = text
                }
                InlineWheelField {
                    label: ""
                    model: ["minutes", "hours", "days"]
                    currentIndex: root.intervalUnit === "days" ? 2 : root.intervalUnit === "hours" ? 1 : 0
                    displayText: root.intervalUnit
                    Layout.preferredWidth: 125
                    Layout.preferredHeight: 34
                    onExpansionRequested: expanded = !expanded
                    onCollapseRequested: expanded = false
                    onSelectionRequested: (index, value) => root.intervalUnit = String(value)
                }
            }
            FormHint {
                visible: root.typeText === "subscription"
                text: "Read-only feed. Refreshes in background even when calendar is closed. No login/SSO."
            }
            FormHint {
                visible: root.typeText === "synced"
                text: root.attachmentMode ? "Select an existing remote collection or create a new one. ID, name, color, visibility and events stay. Create and attach creates the remote before automatic attachment/sync; a created remote stays if attachment fails or is cancelled. Avoid edits on other devices during the final refresh/sync gap. Password file stays yours." : "Editable, two-way sync. Remote identity is fixed after Add. Password file stays yours."
            }
            FormHint {
                visible: !root.attachmentMode && ["subscription", "synced"].includes(root.typeText) && root.editingId.length > 0
                text: root.subscriptionStatus(root.editingId)
            }
            ActionButton {
                visible: !root.attachmentMode && ["subscription", "synced"].includes(root.typeText) && root.editingId.length > 0
                label: "Refresh now"
                enabled: root.typeText === "synced" ? root.calendarService.caldav.ready && !root.calendarService.caldav.recordForId(root.editingId)?.status?.busy : root.calendarService.subscriptions.ready && !root.calendarService.subscriptionForId(root.editingId)?.status?.busy
                onClicked: root.refreshProfile(root.editingId)
            }
            FieldLabel {
                text: "COLOR"
                Layout.topMargin: 10
            }
            RowLayout {
                Layout.fillWidth: true
                FormField {
                    text: root.colorText
                    enabled: !root.attachmentMode
                    placeholderText: "#rrggbb"
                    onTextEdited: root.colorText = text
                }
                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: Theme.radius
                    color: root.colorText
                    border.width: 1
                    border.color: Theme.border
                }
            }
            FieldLabel {
                visible: root.typeText === "imported" && root.editingId.length === 0
                text: "ICS FILE"
                Layout.topMargin: 10
            }
            Rectangle {
                id: sourceSelector
                objectName: "calendarIcsSource"
                visible: root.typeText === "imported" && root.editingId.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: sourceSelectorMouse.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : Theme.background
                radius: Theme.radius
                border.width: 1
                border.color: Theme.border
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 30
                    text: root.sourcePath.length > 0 ? root.sourcePath : "Choose an .ics file"
                    textFormat: Text.PlainText
                    color: root.sourcePath.length > 0 ? Theme.text : Theme.textMuted
                    font.family: Theme.font
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: Theme.textMuted
                    font.family: Theme.font
                    font.pixelSize: 17
                }
                MouseArea {
                    id: sourceSelectorMouse
                    anchors.fill: parent
                    enabled: !root.importPending
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.pickerOpen = !root.pickerOpen
                }
            }
            FormHint {
                visible: root.typeText === "imported"
                text: root.editingId.length === 0 ? "Read-only. File moves into calendar storage after successful import." : "Read-only calendar. Remove and import again to use a different file."
            }
            Controls.Popup {
                id: sourcePicker
                readonly property Item selector: root.typeText === "synced" ? passwordSelector : sourceSelector
                // Follow the manager when PanelWindow recreates its window.
                parent: root
                z: 1000
                implicitWidth: selector.width
                implicitHeight: 280
                padding: 8
                modal: true
                dim: true
                closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
                Controls.Overlay.modal: Rectangle {
                    color: Qt.rgba(0, 0, 0, 0.4)
                }
                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
                function positionPicker() {
                    const position = selector.mapToItem(parent, 0, selector.height - height);
                    x = position.x;
                    y = position.y;
                }
                onOpened: positionPicker()
                onClosed: root.pickerOpen = false
                contentItem: ColumnLayout {
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 5
                            text: root.pickerPath
                            textFormat: Text.PlainText
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            elide: Text.ElideMiddle
                        }
                        GlyphButton {
                            objectName: "calendarFilePickerCancel"
                            label: ""
                            Layout.rightMargin: 5
                            onClicked: sourcePicker.close()
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        color: sourceParentMouse.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : Theme.surfaceRaised
                        radius: Theme.radius
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            text: "  .."
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                        }
                        MouseArea {
                            id: sourceParentMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.navigatePicker(root.pickerParent())
                        }
                    }
                    ListView {
                        id: sourceEntries
                        objectName: "calendarFilePickerEntries"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: folderModel
                        spacing: 2
                        delegate: Rectangle {
                            id: entry
                            required property string fileName
                            required property bool fileIsDir
                            required property string filePath
                            required property url fileUrl
                            width: sourceEntries.width
                            height: 28
                            radius: Theme.radius
                            color: entryMouse.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : entryHover.hovered ? Theme.surfaceRaised : "transparent"
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                text: (entry.fileIsDir ? "  " : "  ") + entry.fileName
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideMiddle
                            }
                            HoverHandler {
                                id: entryHover
                                enabled: entry.enabled
                                cursorShape: Qt.PointingHandCursor
                            }
                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (entry.fileIsDir) {
                                        root.navigatePicker(entry.filePath);
                                    } else {
                                        if (root.typeText === "synced")
                                            root.passwordFileText = root.pickerLocalPath(entry.filePath);
                                        else
                                            root.sourcePath = root.pickerLocalPath(entry.filePath);
                                        sourcePicker.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Connections {
                target: root
                function onPickerOpenChanged() {
                    if (root.pickerOpen && root.formMode && (root.editingId.length === 0 || root.attachmentMode) && ["imported", "synced"].includes(root.typeText))
                        sourcePicker.open();
                    else
                        sourcePicker.close();
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }
    }

    component FieldLabel: Text {
        Layout.leftMargin: root.formTextInset
        color: Theme.textMuted
        font.pixelSize: 9
        font.letterSpacing: 1.2
        font.weight: Font.DemiBold
    }

    component FormHint: Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.leftMargin: root.formTextInset
        Layout.rightMargin: root.formTextInset
        textFormat: Text.PlainText
        color: Theme.textMuted
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }

    component FormField: Controls.TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        color: Theme.text
        placeholderTextColor: Theme.textMuted
        selectionColor: Theme.accent
        selectedTextColor: Theme.background
        font.pixelSize: 13
        font.family: Theme.font
        leftPadding: 10
        rightPadding: 10
        background: Rectangle {
            radius: Theme.radius
            color: Theme.background
            border.width: 1
            border.color: Theme.border
        }
    }

    component GlyphButton: Rectangle {
        id: glyphButton
        opacity: enabled ? 1 : 0.4
        required property string label
        property bool destructive: false
        readonly property color iconColor: glyphButton.destructive ? Theme.currentTime : glyphHover.hovered ? Theme.text : Theme.textMuted
        signal clicked
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        radius: Theme.radius
        color: glyphMouse.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : glyphHover.hovered ? Theme.surfaceRaised : "transparent"

        Text {
            anchors.fill: parent
            text: glyphButton.label
            color: glyphButton.iconColor
            font.family: Theme.fontMono
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        HoverHandler {
            id: glyphHover
            enabled: glyphButton.enabled
            cursorShape: Qt.PointingHandCursor
        }
        MouseArea {
            id: glyphMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: glyphButton.clicked()
        }
    }
}
