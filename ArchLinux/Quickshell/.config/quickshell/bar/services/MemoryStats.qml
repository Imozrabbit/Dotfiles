import QtQuick
import Quickshell
import Quickshell.Io

import "MemoryParser.js" as MemoryParser

Scope {
    id: root
    property int memUsage: 0
    property real memTotalKib: -1
    property real memUsedKib: -1
    property real memAvailableKib: -1
    property real swapTotalKib: -1
    property real swapUsedKib: -1

    function applyMeminfo(text) {
        const sample = MemoryParser.parseMeminfo(text);
        if (sample.memory) {
            root.memTotalKib = sample.memory.total;
            root.memUsedKib = sample.memory.used;
            root.memAvailableKib = sample.memory.available;
            root.memUsage = Math.round(100 * sample.memory.used / sample.memory.total);
        } else {
            root.memTotalKib = -1;
            root.memUsedKib = -1;
            root.memAvailableKib = -1;
            root.memUsage = -1;
        }

        if (sample.swap) {
            root.swapTotalKib = sample.swap.total;
            root.swapUsedKib = sample.swap.used;
        } else {
            root.swapTotalKib = -1;
            root.swapUsedKib = -1;
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: root.applyMeminfo(text())
        onLoadFailed: root.applyMeminfo("")
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: memFile.reload()
    }
}
