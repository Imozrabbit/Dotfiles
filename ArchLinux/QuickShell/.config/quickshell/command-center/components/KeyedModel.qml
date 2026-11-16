pragma ComponentBehavior: Bound
import QtQml
import QtQml.Models

ListModel {
    id: root
    dynamicRoles: true
    property var entries: []
    property string keyRole: "id"
    readonly property var byKey: new Map(root.entries.map(entry => [entry[root.keyRole], entry]))

    function synchronize(): void {
        const keys = root.entries.map(entry => entry[root.keyRole]);
        const wanted = new Set(keys);
        for (let index = root.count - 1; index >= 0; --index) {
            if (!wanted.has(root.get(index).key))
                root.remove(index);
        }
        keys.forEach((key, index) => {
            let from = index;
            while (from < root.count && root.get(from).key !== key)
                from++;
            if (from === root.count)
                root.insert(index, {
                    key
                });
            else if (from !== index)
                root.move(from, index, 1);
        });
    }

    onEntriesChanged: root.synchronize()
    Component.onCompleted: root.synchronize()
}
