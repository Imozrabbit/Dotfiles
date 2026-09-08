import QtQuick
import "../common/CalendarMath.js" as CalendarMath
import "../common/EventMutation.js" as EventMutation

QtObject {
    id: root

    readonly property date mockFocusDate: new Date(2026, 8, 2)
    readonly property var sourceCalendars: [
        {
            id: "edt_unistra",
            name: "University",
            color: "#7b9acc",
            writable: false,
            visible: true
        },
        {
            id: "personal",
            name: "Personal",
            color: "#b58bc8",
            writable: true,
            visible: true
        }
    ]
    property var calendars: sourceCalendars

    property PersonalCalendarStore personalStore: PersonalCalendarStore {
        calendars: root.sourceCalendars
        reservedUids: root.sourceEvents.map(event => event.uid)
    }

    readonly property var sourceEvents: [
        {
            uid: "a4d13d18-567b-4689-ad2b-c461f0014032@a4d1.org",
            calendarId: "edt_unistra",
            title: "Réunion de rentrée",
            description: "Filières : M1 SemE, M1 CmI MnE\nIntervenants : Anstotz Freddy",
            location: "103 · Institut de Physique",
            start: "2026-09-01T12:00:00Z",
            end: "2026-09-01T14:00:00Z",
            allDay: false,
            reminders: []
        },
        {
            uid: "b6243fa0-ddec-47aa-a4fd-695a8f28825f@b624.org",
            calendarId: "edt_unistra",
            title: "CM: Architecture Micro CTL",
            description: "Filières : M1 SemE, M1 CmI MnE\nIntervenants : Anstotz Freddy",
            location: "163 · Institut de Physique",
            start: "2026-09-01T14:00:00Z",
            end: "2026-09-01T16:00:00Z",
            allDay: false,
            reminders: []
        },
        {
            uid: "deb5852d-4c99-4fef-9d96-1a3a0f1f15f9@deb5.org",
            calendarId: "edt_unistra",
            title: "Traitement Signal",
            description: "Filières : M1 SemE, M1 CmI MnE\nIntervenants : Salzenstein Fabien",
            location: "160 · Institut de Physique",
            start: "2026-09-02T06:00:00Z",
            end: "2026-09-02T08:00:00Z",
            allDay: false,
            reminders: []
        },
        {
            uid: "20ee6a01-01f0-4e1d-bae6-2cd3fb8eb45a@20ee.org",
            calendarId: "edt_unistra",
            title: "Électronique analogique",
            description: "Filières : M1 SemE, M1 CmI MnE\nIntervenants : Antoni Frederic",
            location: "160 · Institut de Physique",
            start: "2026-09-02T08:00:00Z",
            end: "2026-09-02T10:00:00Z",
            allDay: false,
            reminders: []
        },
        {
            uid: "d3d937c9-d37d-44d1-aa32-4e39be2afcbe@d3d9.org",
            calendarId: "edt_unistra",
            title: "Automatique",
            description: "Filières : M1 SemE, M1 CmI MnE\nIntervenants : Laroche Edouard",
            location: "160 · Institut de Physique",
            start: "2026-09-02T12:00:00Z",
            end: "2026-09-02T14:00:00Z",
            allDay: false,
            reminders: []
        },
        {
            uid: "b65443cf-2d73-4d05-a12e-8c9a5672a290@b654.org",
            calendarId: "edt_unistra",
            title: "Électronique analogique",
            description: "Filières : M1 SemE, M1 CmI MnE\nIntervenants : Antoni Frederic",
            location: "167 · Institut de Physique",
            start: "2026-09-02T14:00:00Z",
            end: "2026-09-02T16:00:00Z",
            allDay: false,
            reminders: []
        },
        {
            uid: "enterprise-day",
            calendarId: "edt_unistra",
            title: "Semaine en Entreprise",
            description: "Filières : Groupe TP1 : App",
            location: "",
            start: "2026-09-03T06:00:00Z",
            end: "2026-09-03T16:00:00Z",
            allDay: false,
            reminders: []
        },
        {
            uid: "crowded-1",
            calendarId: "edt_unistra",
            title: "Signal processing",
            start: "2026-09-15T06:00:00Z",
            end: "2026-09-15T08:00:00Z",
            allDay: false
        },
        {
            uid: "crowded-2",
            calendarId: "edt_unistra",
            title: "Microcontrollers",
            start: "2026-09-15T08:00:00Z",
            end: "2026-09-15T10:00:00Z",
            allDay: false
        },
        {
            uid: "crowded-4",
            calendarId: "edt_unistra",
            title: "Analog electronics",
            start: "2026-09-15T12:00:00Z",
            end: "2026-09-15T14:00:00Z",
            allDay: false
        }
    ]
    readonly property var rawEvents: root.sourceEvents.concat(personalStore.rawEvents)
    readonly property var normalizedSourceEvents: root.normalizeEvents(root.sourceEvents)
    readonly property var events: root.normalizedSourceEvents.concat(root.normalizeEvents(personalStore.rawEvents))

    function normalizeEvents(rawEvents) {
        const normalized = [];
        for (const event of rawEvents) {
            const result = EventMutation.normalizeEvent(event, root.sourceCalendars);
            if (result)
                normalized.push(result);
        }
        return normalized;
    }

    function calendarById(calendarId) {
        return root.calendars.find(calendar => calendar.id === calendarId) || null;
    }

    function setCalendarVisible(calendarId, visible) {
        const calendars = CalendarMath.withCalendarVisibility(root.calendars, calendarId, visible);
        if (calendars !== root.calendars)
            root.calendars = calendars;
    }

    function availableUid() {
        let uid;
        do {
            uid = Date.now().toString(36) + "-"
                + Math.random().toString(36).slice(2)
                + "@quickshell-calendar";
        } while (root.rawEvents.some(event => event.uid === uid));
        return uid;
    }

    function storageUnavailable() {
        return {
            ok: false,
            field: "storage",
            message: personalStore.errorMessage.length > 0
                ? personalStore.errorMessage : "Personal calendar is not ready"
        };
    }

    function createEvent(eventData) {
        if (!personalStore.ready)
            return root.storageUnavailable();
        const result = EventMutation.createEvent(root.rawEvents, root.sourceCalendars, eventData, root.availableUid());
        if (!result.ok)
            return result;
        const saved = personalStore.persist(result.rawEvents.filter(
            event => event.calendarId === "personal"));
        if (!saved.ok)
            return saved;
        return {
            ok: true,
            event: result.event
        };
    }

    function updateEvent(uid, eventData) {
        if (!personalStore.ready)
            return root.storageUnavailable();
        const result = EventMutation.updateEvent(root.rawEvents, root.sourceCalendars, uid, eventData);
        if (!result.ok)
            return result;
        const saved = personalStore.persist(result.rawEvents.filter(
            event => event.calendarId === "personal"));
        if (!saved.ok)
            return saved;
        return {
            ok: true,
            event: result.event
        };
    }

    function deleteEvent(uid) {
        if (!personalStore.ready)
            return root.storageUnavailable();
        const result = EventMutation.deleteEvent(root.rawEvents, root.sourceCalendars, uid);
        if (!result.ok)
            return result;
        const saved = personalStore.persist(result.rawEvents.filter(
            event => event.calendarId === "personal"));
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
}
