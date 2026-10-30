import QtQuick
import "../common/ProfileMutation.js" as ProfileMutation

CalendarSubscriptionService {
    id: root
    backend: "caldav"

    property var conversionSession: null
    property var conversionChoices: []
    property int conversionIndex: 0
    property string conversionError: ""
    property var conversionResult: null
    property string attachmentSubmission: ""
    readonly property string conversionKind: root.conversionSession?.kind || "synced-to-local"
    readonly property bool attachmentLifecycle: root.conversionKind === "local-to-synced"
    readonly property bool preservationLifecycle: ["remote-delete", "local-preserve"].includes(root.conversionKind)
    readonly property bool allowLocalOnly: !root.preservationLifecycle && !root.attachmentLifecycle
    readonly property bool conversionCanCancel: root.conversionSession !== null && (root.attachmentLifecycle ? root.conversionSession.phase === "review" && !root.conversionSession.syncAttempted : root.preservationLifecycle ? ["preparing", "review", "ready", "rollback"].includes(root.conversionSession.phase) && !root.conversionSession.remoteAttempted : !root.conversionSession.remoteAttempted)
    readonly property bool conversionNeedsRetry: root.conversionSession !== null && (root.preservationLifecycle || root.attachmentLifecycle) && (root.conversionSession.phase !== "review" || root.conversionError.length > 0)
    readonly property var conversionConflict: root.conversionSession?.conflicts?.[root.conversionIndex] || null
    readonly property bool conversionReady: root.conversionSession !== null && !root.conversionSession.remoteAttempted && root.conversionError.length === 0 && root.conversionChoices.length === root.conversionSession.conflicts.length && (!(root.preservationLifecycle || root.attachmentLifecycle) || root.conversionSession.phase === "review")

    function advanceAttachment() {
        if (!root.attachmentLifecycle || !root.conversionReady || root.busy || !root.ready)
            return;
        const key = root.conversionSession.session + ":" + root.conversionSession.revision + ":" + JSON.stringify(root.conversionChoices);
        if (key === root.attachmentSubmission)
            return;
        root.attachmentSubmission = key;
        const result = root.finishConversion();
        if (!result.ok)
            root.conversionError = result.message;
    }
    onConversionChoicesChanged: Qt.callLater(root.advanceAttachment)
    onConversionSessionChanged: Qt.callLater(root.advanceAttachment)
    onBusyChanged: Qt.callLater(root.advanceAttachment)
    onReadyChanged: Qt.callLater(root.advanceAttachment)

    function adoptConversion(session) {
        const changed = root.conversionSession?.session !== session.session || root.conversionSession?.revision !== session.revision;
        if (changed) {
            root.conversionChoices = session.kind === "local-to-synced" ? session.choices || [] : [];
            root.conversionIndex = 0;
        }
        root.conversionSession = session;
        if (session.kind === "local-to-synced") {
            root.conversionIndex = Math.max(0, session.conflicts.findIndex(conflict => !root.conversionChoices.some(choice => choice.uid === conflict.uid)));
            if (session.phase !== "review" && !root.busy && root.conversionError.length === 0)
                root.conversionError = "Calendar attachment paused. Retry resumes activation or cleanup; if synchronization may have started, synced data and history stay intact.\nRecovery files: " + session.recoveryPaths.join(", ");
            return;
        }
        if (session.kind === "local-preserve") {
            if (session.phase !== "review" && !root.busy) {
                root.conversionError = "Local preservation paused. Retry rebuilds local review or finishes local activation/cleanup; no server changes are attempted.\nRecovery files: " + session.recoveryPaths.join(", ");
            }
            return;
        }
        if (session.kind === "remote-delete") {
            if (session.remoteAttempted && !root.busy && (changed || root.conversionError.length === 0)) {
                root.conversionError = session.phase === "uncertain" || session.phase === "deleting" ? "Remote deletion outcome uncertain; synchronization stays paused. Retry checks once without another DELETE." : "Remote calendar deleted; local activation or cleanup pending. Retry finishes locally without uploading.";
                root.conversionError += "\nRecovery files: " + session.recoveryPaths.join(", ");
            }
            return;
        }
        if (session.remoteAttempted && !root.busy && (changed || root.conversionError.length === 0)) {
            root.conversionError = session.disconnected ? "Sync disconnected; local calendar could not be loaded. Local data preserved: " + session.localPath : "Conversion incomplete; sync paused.";
            root.conversionError += "\nRecovery files: " + session.recoveryPaths.join(", ");
        }
    }

    onConversionsChanged: {
        const current = root.conversionSession ? root.conversions.find(session => session.session === root.conversionSession.session) : root.conversions[0];
        if (current)
            root.adoptConversion(current);
        else if (!root.busy && root.conversionSession) {
            root.conversionSession = null;
            root.conversionChoices = [];
        }
    }

    function conversionBlocked(id) {
        if (root.pending?.id === id && (root.pending.action.startsWith("convert-") || root.pending.action.startsWith("attach-") || root.pending.action.startsWith("remote-delete-") || root.pending.action === "local-preserve-begin"))
            return true;
        if ((root.conversionSession?.id === id && ["remote-delete", "local-preserve", "local-to-synced"].includes(root.conversionSession.kind)) || root.conversions.some(session => session.id === id && ["remote-delete", "local-preserve", "local-to-synced"].includes(session.kind)))
            return true;
        if (root.registry.profiles.find(profile => profile.id === id)?.type !== "synced")
            return false;
        return root.conversionSession?.id === id || root.conversions.some(session => session.id === id);
    }

    function beginConversion(id) {
        return root.beginLifecycle(id, "synced-to-local");
    }

    function beginAttachment(id, connection, intervalSeconds, expectedProfile, expectedRevision) {
        if (root.busy || root.conversionSession)
            return {
                ok: false,
                message: "Finish or cancel current calendar change first"
            };
        const profile = root.registry.profiles.find(candidate => candidate.id === id);
        if (!profile || profile.type !== "local" || JSON.stringify(profile) !== JSON.stringify(expectedProfile))
            return {
                ok: false,
                message: "Local calendar profile changed; reopen attachment"
            };
        root.conversionError = "";
        root.conversionResult = null;
        root.attachmentSubmission = "";
        return root.start("attach-begin", id, Object.assign({}, connection, {
            id,
            expectedProfile: profile,
            expectedRevision,
            intervalSeconds
        }));
    }

    function beginRemoteDeletion(id) {
        return root.beginLifecycle(id, "remote-delete");
    }

    function beginLocalPreservation(id) {
        return root.beginLifecycle(id, "local-preserve");
    }

    function recheckAvailability(id) {
        const profile = root.registry.profiles.find(candidate => candidate.id === id);
        if (!profile || profile.type !== "synced")
            return {
                ok: false,
                message: "Synced calendar not found"
            };
        return root.start("remote-recheck", id, {
            id,
            expectedProfile: profile,
            expectedRevision: root.revision
        });
    }

    function beginLifecycle(id, kind) {
        if (root.busy)
            return {
                ok: false,
                message: "Another calendar change is running"
            };
        const existing = root.conversions.find(session => session.id === id);
        if (root.conversionSession && root.conversionSession.id !== id && !root.conversionSession.remoteAttempted)
            return {
                ok: false,
                message: "Finish or cancel current conversion first"
            };
        if (existing) {
            root.adoptConversion(existing);
            return existing.remoteAttempted && !["remote-delete", "local-preserve"].includes(existing.kind) ? {
                ok: false,
                message: root.conversionError
            } : {
                ok: true
            };
        }
        const profile = root.registry.profiles.find(candidate => candidate.id === id);
        if (!profile || profile.type !== "synced" || !root.recordForId(id))
            return {
                ok: false,
                message: "Managed synced calendar not found"
            };
        root.conversionError = "";
        root.conversionResult = null;
        return root.start(kind === "remote-delete" ? "remote-delete-begin" : kind === "local-preserve" ? "local-preserve-begin" : "convert-begin", id, {
            id,
            expectedProfile: profile,
            expectedRevision: root.revision
        });
    }

    function stageConversionChoice(uid, revision, choice) {
        const conflict = root.conversionSession?.conflicts.find(candidate => candidate.uid === uid);
        if (root.busy || !conflict || root.conversionSession.remoteAttempted || conflict.revision !== revision || !(root.allowLocalOnly ? ["local", "remote", "local-only"] : ["local", "remote"]).includes(choice) || ((root.preservationLifecycle || root.attachmentLifecycle) && root.conversionSession.phase !== "review") || (conflict.kind === "group" && !conflict.ready))
            return {
                ok: false,
                message: "Conflict changed; reopen conversion review"
            };
        root.conversionChoices = root.conversionChoices.filter(candidate => candidate.uid !== uid).concat([
            {
                uid,
                revision,
                choice
            }
        ]);
        root.conversionError = "";
        if (!root.conversionReady)
            root.conversionIndex = Math.min(root.conversionIndex + 1, root.conversionSession.conflicts.length - 1);
        return {
            ok: true
        };
    }

    function finishConversion() {
        if (!root.conversionReady)
            return {
                ok: false,
                message: root.conversionError || "Choose a version for every conflict"
            };
        const session = root.conversionSession;
        return root.start(root.attachmentLifecycle ? "attach-finish" : root.preservationLifecycle ? "remote-delete-finish" : "convert-finish", session.id, {
            id: session.id,
            session: session.session,
            expectedRevision: session.revision,
            choices: root.conversionChoices
        });
    }

    function cancelConversion() {
        const session = root.conversionSession;
        if (!root.conversionCanCancel)
            return {
                ok: false,
                message: root.conversionError || "Remote work was attempted; inspect recovery files"
            };
        return root.start(root.attachmentLifecycle ? "attach-cancel" : root.preservationLifecycle ? "remote-delete-cancel" : "convert-cancel", session.id, {
            id: session.id,
            session: session.session,
            expectedRevision: session.revision
        });
    }

    function retryConversion() {
        const session = root.conversionSession;
        if (!session || !(root.preservationLifecycle || root.attachmentLifecycle))
            return {
                ok: false,
                message: "No calendar operation to retry"
            };
        if (root.attachmentLifecycle && session.phase === "review") {
            root.conversionError = "";
            root.attachmentSubmission = "";
            return root.finishConversion();
        }
        return root.start(root.attachmentLifecycle ? "attach-retry" : "remote-delete-retry", session.id, {
            id: session.id,
            session: session.session,
            expectedRevision: session.revision
        });
    }

    function finishReply(result) {
        if (result.action.startsWith("attach-")) {
            root.conversionResult = result;
            root.conversionError = result.ok ? "" : result.message;
            if (result.cancelled || result.completed) {
                root.conversionSession = null;
                root.conversionChoices = [];
                root.conversionIndex = 0;
            } else if (result.session && result.revision) {
                root.adoptConversion(result);
            }
            root.finished(result);
            return;
        }
        if (result.action.startsWith("remote-delete-") || result.action === "local-preserve-begin") {
            root.conversionResult = result;
            root.conversionError = !result.ok || result.cleanupWarning || result.activationWarning ? result.message : "";
            if (result.cancelled || result.rolledBack || result.completed) {
                root.conversionSession = null;
                root.conversionChoices = [];
                root.conversionIndex = 0;
            } else if (["remote-delete", "local-preserve"].includes(result.kind) && result.session && result.revision) {
                root.adoptConversion(result);
                if (result.reviewChanged) {
                    root.conversionChoices = [];
                    root.conversionIndex = 0;
                    root.conversionError = "";
                }
            }
            root.finished(result);
            return;
        }
        if (result.action.startsWith("convert-")) {
            root.conversionResult = result;
            root.conversionError = !result.ok || result.activationWarning || result.cleanupWarning ? result.message : "";
            if (result.action === "convert-begin" && result.ok)
                root.adoptConversion(result);
            else if (result.cancelled || (result.converted && result.localActive)) {
                root.conversionSession = null;
                root.conversionChoices = [];
                root.conversionIndex = 0;
            } else if (root.conversionSession && result.action === "convert-finish") {
                root.conversionSession = Object.assign({}, root.conversionSession, {
                    remoteAttempted: result.remoteAttempted !== false,
                    disconnected: result.disconnected === true,
                    localPath: result.localPath || root.conversionSession.localPath
                });
            }
            if (!result.ok && root.conversionSession) {
                const missing = root.conversionSession.recoveryPaths.filter(path => !root.conversionError.includes(path));
                if (missing.length)
                    root.conversionError += "\nRecovery files: " + missing.join(", ");
            }
        }
        root.finished(result);
    }

    function discover(url, username, passwordFile) {
        return root.start("discover", "", {
            url,
            username,
            passwordFile
        });
    }

    function removeSynced(id, expectedProfile, expectedRevision) {
        const current = root.registry.profiles.find(profile => profile.id === id);
        const baseline = ProfileMutation.validateProfile(expectedProfile === undefined ? current : expectedProfile);
        if (!current || current.type !== "synced" || !baseline.ok || JSON.stringify(baseline.profile) !== JSON.stringify(current))
            return {
                ok: false,
                field: "storage",
                message: "Calendar profile changed; confirm removal again"
            };
        return root.start("remove", id, {
            id,
            expectedProfile: baseline.profile,
            expectedRevision: expectedRevision === undefined ? root.revision : expectedRevision
        });
    }

    function saveSynced(draft, connection, intervalSeconds, replacingId, expectedRevision, expectedProfile) {
        const current = root.registry.profiles.find(profile => profile.id === draft.id) || null;
        if ((replacingId && replacingId !== draft.id) || (current && (replacingId !== draft.id || current.type !== "synced")) || (!current && replacingId))
            return {
                ok: false,
                field: "id",
                message: "Choose a unique ID; existing synced calendar IDs cannot change"
            };
        let previous = null;
        if (replacingId) {
            const baseline = ProfileMutation.validateProfile(expectedProfile);
            if (!baseline.ok || JSON.stringify(baseline.profile) !== JSON.stringify(current))
                return {
                    ok: false,
                    field: "storage",
                    message: "Calendar profile changed; reopen it before saving"
                };
            previous = baseline.profile;
        }
        const valid = ProfileMutation.validateProfile(Object.assign({}, previous || {
            visible: true
        }, draft));
        if (!valid.ok)
            return valid;
        if (valid.profile.type !== "synced")
            return {
                ok: false,
                field: "type",
                message: "Use synced calendar type"
            };
        return root.start("save", draft.id, Object.assign({}, connection, {
            profile: valid.profile,
            expectedProfile: previous,
            expectedRevision: expectedRevision === undefined ? root.revision : expectedRevision,
            intervalSeconds
        }), valid.profile);
    }

    function createSynced(draft, connection, remoteName, collectionId, homeHref, intervalSeconds) {
        if (root.registry.profiles.some(profile => profile.id === draft.id))
            return {
                ok: false,
                field: "id",
                message: "Choose a unique local ID; existing calendars cannot be attached here"
            };
        const valid = ProfileMutation.validateProfile(Object.assign({
            visible: true
        }, draft));
        if (!valid.ok)
            return valid;
        if (valid.profile.type !== "synced")
            return {
                ok: false,
                field: "type",
                message: "Use synced calendar type"
            };
        return root.start("create", draft.id, Object.assign({}, connection, {
            profile: valid.profile,
            expectedProfile: null,
            expectedRevision: root.revision,
            remoteName,
            collectionId,
            homeHref,
            intervalSeconds
        }), valid.profile);
    }
}
