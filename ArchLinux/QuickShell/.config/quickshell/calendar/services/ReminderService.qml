import QtQuick
import Quickshell.Io
import "../common/EventMutation.js" as EventMutation
import "../common/ReminderSchedule.js" as Schedule

QtObject {
    id: root

    required property var calendarService
    property var now: () => Date.now()
    property string notifySendPath: "notify-send"
    readonly property var masters: calendarService.rawEvents.filter(event => calendarService.calendars.some(calendar => calendar.id === event.calendarId && calendar.ready))
    readonly property var recurringMasters: masters.filter(event => event.recurrence || event.ical)
    readonly property string signature: JSON.stringify([masters, calendarService.systemTimezone])
    readonly property bool queryPending: activeId.length > 0
    readonly property string errorMessage: [queryError, notificationError].filter(text => text.length > 0).join("; ")
    property string queryError: ""
    property string notificationError: ""
    property var sourceSnapshots: new Map()
    property var scheduled: []
    property var queue: []
    property var sending: null
    property var clock: ({
            lastMs: 0,
            highWaterMs: 0
        })
    property bool initialized: false
    property double refreshAtMs: 0
    property bool queryWanted: false
    property int sequence: 0
    property string activeId: ""
    property string activeSignature: ""
    property var activeMasters: []
    property double activeStartMs: 0
    property double activeEndMs: 0
    property bool queryTimedOut: false
    property bool sendTimedOut: false

    function refresh() {
        const current = root.now();
        if (!Number.isSafeInteger(current))
            return;
        root.sourceSnapshots = Schedule.snapshots(root.masters);
        const retained = Schedule.retain(root.scheduled, root.sourceSnapshots, root.clock.highWaterMs);
        const ordinary = root.calendarService.normalizeEvents(root.masters.filter(event => !event.recurrence && !event.ical));
        root.scheduled = Schedule.merge(retained, Schedule.build(ordinary, root.sourceSnapshots, Math.max(current, root.clock.highWaterMs), current + 3600000));
        root.refreshAtMs = current + 1800000;
        root.queryWanted = true;
        Qt.callLater(root.startQuery);
    }

    function tick() {
        const current = root.now();
        const due = Schedule.takeDue(root.scheduled, root.clock, current);
        if (root.scheduled.length > 0 && root.scheduled[0].atMs <= root.clock.highWaterMs)
            root.scheduled = Schedule.retain(root.scheduled, root.sourceSnapshots, root.clock.highWaterMs);
        if (due.length > 0)
            root.queue = Schedule.merge(root.queue, due);
        root.sendNext();
        if (current >= root.refreshAtMs)
            root.refresh();
    }

    function startQuery() {
        if (!root.queryWanted || root.queryPending || root.queryProcess.running)
            return;
        root.queryWanted = false;
        if (root.recurringMasters.length === 0) {
            root.queryError = "";
            return;
        }
        root.activeId = String(++root.sequence);
        root.activeSignature = root.signature;
        root.activeMasters = root.recurringMasters;
        root.activeStartMs = Math.max(root.now(), root.clock.highWaterMs);
        root.activeEndMs = root.activeStartMs + 3600000;
        root.queryTimedOut = false;
        root.queryProcess.command = [root.calendarService.nativeHelperPath, "expand"];
        root.queryProcess.running = true;
        if (root.queryProcess.running)
            root.queryProcess.write(JSON.stringify({
                requestId: root.activeId,
                rangeStartMs: root.activeStartMs,
                rangeEndMs: root.activeEndMs,
                events: root.activeMasters,
                forReminders: true
            }) + "\n");
        const id = root.activeId;
        Qt.callLater(() => {
            if (root.activeId === id && !root.queryProcess.running)
                root.finishQuery(-1);
        });
    }

    function acceptOutput(text) {
        if (text.length > 32 * 1024 * 1024)
            return false;
        let response;
        try {
            response = JSON.parse(text);
        } catch (error) {
            return false;
        }
        if (!response || response.requestId !== root.activeId || !Array.isArray(response.occurrences) || response.occurrences.length > 100000 || !Array.isArray(response.warnings) || response.warnings.length > 100000 || response.warnings.some(warning => typeof warning !== "string"))
            return false;
        const masters = new Map(root.activeMasters.map(event => [Schedule.masterKey(event.calendarId, event.uid), event]));
        const seen = new Set();
        for (const event of response.occurrences) {
            if (!event || !masters.has(Schedule.masterKey(event.calendarId, event.masterUid)) || typeof event.uid !== "string" || event.uid.length === 0 || event.uid !== event.occurrenceId || !EventMutation.validateReminders(event.reminders).ok)
                return false;
            const key = Schedule.masterKey(event.calendarId, event.uid);
            if (seen.has(key))
                return false;
            seen.add(key);
        }
        const normalized = root.calendarService.normalizeEvents(response.occurrences);
        if (normalized.length !== response.occurrences.length || normalized.some((event, index) => event.startMs !== response.occurrences[index].startMs || event.endMs !== response.occurrences[index].endMs))
            return false;
        const rows = Schedule.build(normalized, root.sourceSnapshots, Math.max(root.now(), root.clock.highWaterMs), root.activeEndMs);
        root.scheduled = Schedule.merge(root.scheduled, rows);
        root.queryError = response.warnings.join("; ");
        return true;
    }

    function finishQuery(exitCode) {
        if (!root.queryPending)
            return;
        if (root.activeSignature === root.signature) {
            if (root.queryTimedOut || exitCode !== 0 || !root.acceptOutput(queryOutput.text))
                root.queryError = root.queryTimedOut ? "Reminder expansion timed out" : queryDiagnostics.text.trim().slice(0, 1024) || "Could not load reminder occurrences";
            if (root.queryError.length > 0)
                console.error(root.queryError);
        }
        root.activeId = "";
        root.activeMasters = [];
        Qt.callLater(root.startQuery);
    }

    function sendNext() {
        if (root.sending || root.sender.running)
            return;
        while (root.queue.length > 0) {
            const row = root.queue[0];
            root.queue = root.queue.slice(1);
            const current = root.now();
            if (row.atMs > current || current - row.atMs > 5000 || root.sourceSnapshots.get(Schedule.masterKey(row.calendarId, row.masterUid)) !== row.source)
                continue;
            const calendar = root.calendarService.calendars.find(item => item.id === row.calendarId && item.ready);
            if (!calendar)
                continue;
            const body = [calendar.name, Qt.formatDateTime(new Date(row.startMs), row.allDay ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"), row.location || ""].filter(text => String(text).trim().length > 0).map(text => Schedule.escapeMarkup(String(text).slice(0, 500))).join("\n");
            root.sending = row;
            root.sendTimedOut = false;
            root.sender.command = [root.notifySendPath, "--app-name=Calendar", "--icon=office-calendar", "--", String(row.title || "Untitled").slice(0, 200), body];
            root.sender.running = true;
            Qt.callLater(() => {
                if (root.sending === row && !root.sender.running)
                    root.finishSend(-1);
            });
            return;
        }
    }

    function finishSend(exitCode) {
        if (!root.sending)
            return;
        root.notificationError = root.sendTimedOut ? "Reminder notification timed out" : exitCode !== 0 ? "Could not send reminder notification" : "";
        if (root.notificationError.length > 0)
            console.error(root.notificationError);
        root.sending = null;
        Qt.callLater(root.sendNext);
    }

    onSignatureChanged: {
        if (root.initialized)
            root.refresh();
    }
    Component.onCompleted: {
        const current = root.now();
        root.clock = {
            lastMs: current,
            highWaterMs: current
        };
        root.initialized = true;
        root.refresh();
    }

    property Timer ticker: Timer {
        interval: 1000
        repeat: true
        running: root.initialized
        onTriggered: root.tick()
    }

    property Process queryProcess: Process {
        stdinEnabled: true
        stdout: StdioCollector {
            id: queryOutput
        }
        stderr: StdioCollector {
            id: queryDiagnostics
        }
        onExited: (exitCode, exitStatus) => root.finishQuery(exitCode)
        onRunningChanged: {
            if (!running && root.queryPending) {
                const id = root.activeId;
                Qt.callLater(() => {
                    if (root.activeId === id && !root.queryProcess.running)
                        root.finishQuery(-1);
                });
            }
        }
    }

    property Timer queryTimeout: Timer {
        interval: 10000
        running: root.queryProcess.running
        onTriggered: {
            root.queryTimedOut = true;
            root.queryProcess.signal(9);
        }
    }

    property Process sender: Process {
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => root.finishSend(exitCode)
        onRunningChanged: {
            if (!running && root.sending) {
                const row = root.sending;
                Qt.callLater(() => {
                    if (root.sending === row && !root.sender.running)
                        root.finishSend(-1);
                });
            }
        }
    }

    property Timer sendTimeout: Timer {
        interval: 10000
        running: root.sender.running
        onTriggered: {
            root.sendTimedOut = true;
            root.sender.signal(9);
        }
    }
}
