pragma ComponentBehavior: Bound
import QtQml

QtObject {
    id: root
    required property var profiles
    required property var caldav
    property bool mutationBlocked: false
    property var stores: []
    property string routingError: ""
    readonly property var conflicts: {
        const result = [];
        for (const store of root.stores)
            for (const conflict of store.conflicts)
                result.push(Object.assign({}, conflict, {
                    calendarId: store.calendarId
                }));
        return result;
    }
    readonly property var activeStore: root.stores.find(store => store.hasConflict) || null
    readonly property var currentConflict: root.conflicts.length ? root.conflicts[0] : null
    readonly property bool hasConflict: root.conflicts.length > 0
    readonly property bool busy: root.stores.some(store => store.busy)
    readonly property bool stateValid: root.activeStore ? root.activeStore.stateValid : root.stores.every(store => store.stateValid)
    readonly property string errorMessage: root.routingError || root.activeStore?.errorMessage || root.stores.find(store => !store.stateValid)?.errorMessage || ""

    function stateValidForId(id) {
        return root.stores.find(store => store.calendarId === id)?.stateValid === true;
    }

    function isConflicted(value, calendarId) {
        const id = value && typeof value === "object" ? value.calendarId : calendarId;
        const store = root.stores.find(candidate => candidate.calendarId === id);
        return store ? store.isConflicted(value) : false;
    }

    function choose(side, uid, revision, calendarId) {
        if (root.caldav.conversionBlocked && root.caldav.conversionBlocked(calendarId)) {
            root.routingError = "Calendar conversion is running";
            return;
        }
        if (root.mutationBlocked) {
            root.routingError = "Calendar removal is running";
            return;
        }
        if (!root.activeStore || root.activeStore.calendarId !== calendarId) {
            root.routingError = "Calendar conflict changed; reopen it";
            return;
        }
        root.routingError = "";
        root.activeStore.choose(side, uid, revision);
    }

    property Instantiator instances: Instantiator {
        model: root.profiles.filter(profile => profile.type === "synced")
        delegate: CalendarConflictService {
            required property var modelData
            calendarId: modelData.id
            readonly property var record: root.caldav.recordForId(calendarId)
            pair: record ? record.pair : calendarId
            scoped: record !== null || calendarId !== "personal"
        }
        onObjectAdded: (index, object) => {
            const stores = root.stores.slice();
            stores.splice(index, 0, object);
            root.stores = stores;
        }
        onObjectRemoved: (index, object) => root.stores = root.stores.filter(store => store !== object)
    }
}
