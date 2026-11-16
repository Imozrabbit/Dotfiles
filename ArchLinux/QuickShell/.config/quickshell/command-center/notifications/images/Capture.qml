pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

Item {
    id: root
    property var job: null
    property string capturingPath: ""
    property bool rendered: false
    signal finished(string token, bool success)
    width: 300
    height: 150

    function capture(): void {
        if (!root.job || root.capturingPath === root.job.path)
            return;
        const token = root.job.token;
        const path = root.job.path;
        if (image.status === Image.Error) {
            root.capturingPath = path;
            root.finished(token, false);
            return;
        }
        if (!root.rendered || image.status !== Image.Ready || !root.Window.window?.visible)
            return;
        root.capturingPath = path;
        const accepted = image.grabToImage(result => {
            const current = root.job?.token === token && root.job?.path === path;
            root.finished(token, current && result.saveToFile(path));
        }, Qt.size(300, 150));
        if (!accepted)
            root.finished(token, false);
    }

    onJobChanged: {
        root.capturingPath = "";
        Qt.callLater(root.capture);
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.job?.source ?? ""
        sourceSize: Qt.size(300, 150)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        onStatusChanged: Qt.callLater(root.capture)
    }

    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            root.rendered = true;
            Qt.callLater(root.capture);
        }
        function onVisibleChanged() {
            if (!root.Window.window.visible)
                root.rendered = false;
        }
    }
}
