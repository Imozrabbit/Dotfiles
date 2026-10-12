import QtQml
import Quickshell.Io
import "../common/CalendarMath.js" as CalendarMath

QtObject {
    id: root

    required property var calendarService
    required property double rangeStartMs
    required property double rangeEndMs
    readonly property var recurringMasters: calendarService.rawEvents.concat(calendarService.holidayStore ? calendarService.holidayStore.rawEvents : [])
        .filter(event => event.recurrence || event.ical)
    readonly property string signature: JSON.stringify([rangeStartMs, rangeEndMs, recurringMasters])
    property string activeSignature: ""
    property string attemptedSignature: ""
    property string resultSignature: ""
    property string activeId: ""
    property int sequence: 0
    property var occurrences: []
    property bool pending: false
    property string errorMessage: ""
    readonly property var events: {
        const ordinary = calendarService.events.filter(event => !event.recurrence && !event.ical);
        const expanded = resultSignature === signature ? occurrences.filter(event => event.calendarId !== "holidays_fr") : [];
        return CalendarMath.filterEventsInRange(ordinary.concat(expanded), calendarService.calendars, rangeStartMs, rangeEndMs);
    }
    readonly property var holidays: {
        const ordinary = calendarService.holidaysInRange(rangeStartMs, rangeEndMs).filter(event => !event.recurrence && !event.ical);
        const expanded = resultSignature === signature ? occurrences.filter(event => event.calendarId === "holidays_fr") : [];
        return ordinary.concat(expanded).sort((left, right) => left.startMs - right.startMs || String(left.uid).localeCompare(String(right.uid)));
    }

    function acceptOutput(text) {
        if (root.activeSignature !== root.signature || text.length > 32 * 1024 * 1024)
            return false;
        let response;
        try {
            response = JSON.parse(text);
        } catch (error) {
            return false;
        }
        if (!response || response.requestId !== root.activeId || !Array.isArray(response.occurrences)
                || response.occurrences.length > 100000 || !Array.isArray(response.warnings)
                || response.warnings.some(warning => typeof warning !== "string"))
            return false;
        const seen = new Set();
        const masters = new Map(root.recurringMasters.map(master => [master.uid, master]));
        for (const event of response.occurrences) {
            const master = event && masters.get(event.masterUid);
            if (!master || event.calendarId !== master.calendarId || event.uid !== event.occurrenceId
                    || typeof event.uid !== "string" || seen.has(event.uid))
                return false;
            seen.add(event.uid);
        }
        const normalized = root.calendarService.normalizeEvents(response.occurrences.filter(event => event.calendarId !== "holidays_fr"))
            .concat(root.calendarService.normalizeHolidays(response.occurrences.filter(event => event.calendarId === "holidays_fr")));
        if (normalized.length !== response.occurrences.length
                || normalized.some(event => event.startMs >= root.rangeEndMs || event.endMs <= root.rangeStartMs))
            return false;
        root.occurrences = normalized;
        root.resultSignature = root.activeSignature;
        root.errorMessage = response.warnings.join("; ");
        return true;
    }

    function startLatest() {
        if (queryProcess.running || root.attemptedSignature === root.signature)
            return;
        root.errorMessage = "";
        root.attemptedSignature = root.signature;
        if (!Number.isFinite(root.rangeStartMs) || !Number.isFinite(root.rangeEndMs) || root.rangeEndMs <= root.rangeStartMs)
            return;
        if (root.recurringMasters.length === 0) {
            root.occurrences = [];
            root.resultSignature = root.signature;
            root.pending = false;
            return;
        }
        root.activeSignature = root.signature;
        root.activeId = String(++root.sequence);
        root.pending = true;
        queryProcess.command = [root.calendarService.nativeHelperPath, "expand"];
        queryProcess.running = true;
        queryProcess.write(JSON.stringify({ requestId: root.activeId, rangeStartMs: root.rangeStartMs,
            rangeEndMs: root.rangeEndMs, events: root.recurringMasters }) + "\n");
    }

    onSignatureChanged: Qt.callLater(root.startLatest)
    Component.onCompleted: Qt.callLater(root.startLatest)

    property Process queryProcess: Process {
        stdinEnabled: true
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: diagnostics }
        onExited: (exitCode, exitStatus) => {
            root.pending = false;
            if (root.activeSignature === root.signature) {
                if (exitCode !== 0 || !root.acceptOutput(output.text))
                    root.errorMessage = diagnostics.text.trim() || "Could not load repeating events";
            }
            Qt.callLater(root.startLatest);
        }
    }
}
