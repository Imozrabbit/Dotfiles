pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

import "./controls"

/* Composes summary, feedback, and pages into complete WiFi card. Overlay owner
   remains responsible for bottom-right anchoring and outside-click handling. */
Item {
    id: root

    required property var controller
    required property var style
    property var homeSsids: []
    required property real availableWidth
    required property real availableHeight
    property string expandedDnsKey: ""

    function toggleDns(key) {
        if (root.controller.isBusy)
            return;
        root.expandedDnsKey = root.expandedDnsKey === key ? "" : key;
        root.controller.dnsPromptUuid = "";
    }

    onVisibleChanged: {
        if (!visible)
            root.expandedDnsKey = "";
    }

    function scrollToTop() {
        contentScroll.contentY = 0;
    }

    implicitWidth: 390
    implicitHeight: Math.ceil(mainLayout.implicitHeight + 24)
    width: Math.min(implicitWidth, Math.max(0, root.availableWidth))
    height: Math.min(implicitHeight, Math.max(0, root.availableHeight))

    Behavior on height {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: root.controller
        function onDnsChoiceRequested(uuid) {
            root.expandedDnsKey = "connected:" + uuid;
            root.scrollToTop();
        }
        function onCurrentPageChanged() {
            root.scrollToTop();
        }
    }

    Rectangle {
        anchors.fill: menuCard
        color: root.style.card
        radius: root.style.radius
        layer.enabled: true
        layer.effect: DropShadow {
            radius: 44
            samples: 64
            verticalOffset: 18
            color: Qt.rgba(0, 0, 0, 0.55)
        }
    }

    Rectangle {
        id: menuCard

        anchors.fill: parent
        color: root.style.card
        radius: root.style.radius
        border.width: 1
        border.color: root.style.border
        clip: true

        Flickable {
            id: contentScroll

            anchors.fill: parent
            contentWidth: width
            contentHeight: root.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: mainLayout

                x: 12
                y: 12
                width: Math.max(0, contentScroll.width - 24)
                spacing: 8

                MenuButton {
                    style: root.style
                    Layout.alignment: Qt.AlignCenter
                    Layout.preferredWidth: 93
                    Layout.preferredHeight: 26
                    text: root.controller.isExpanded ? " Collapse" : "Networks"
                    icon: root.controller.isExpanded ? "" : ""
                    kind: "ghost"
                    disabled: root.controller.isBusy
                    onClicked: root.controller.startScanToggle()
                }

                ConnectionSummary {
                    controller: root.controller
                    style: root.style
                    isHome: root.homeSsids.includes(root.controller.currentSsid)
                    expanded: root.expandedDnsKey === "connected:" + root.controller.activeConnectionUuid
                    onToggleRequested: root.toggleDns("connected:" + root.controller.activeConnectionUuid)
                }

                Label {
                    visible: root.controller.dnsPromptUuid !== ""
                    Layout.fillWidth: true
                    text: root.homeSsids.includes(root.controller.currentSsid) ? "Home network uses router DNS." : "Choose DNS for this new network. Suggested: " + (root.controller.dns.providers.find(provider => provider.id === root.controller.dns.preferredProvider)?.label || "Default") + "."
                    color: root.style.foreground
                    font.family: root.style.textFont
                    wrapMode: Text.Wrap
                }
                MenuButton {
                    visible: root.controller.dnsPromptUuid !== ""
                    Layout.fillWidth: true
                    implicitHeight: 26
                    text: "Later — keep current DNS"
                    style: root.style
                    onClicked: {
                        root.controller.dnsPromptUuid = "";
                        root.expandedDnsKey = "";
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 5
                    Layout.topMargin: 3
                    Layout.bottomMargin: -5
                    visible: root.controller.savedModel.count > 0

                    Label {
                        text: "Saved"
                        font.family: root.style.textFont
                        font.pixelSize: 12
                        font.weight: 600
                        color: root.style.muted
                        Layout.fillWidth: true
                    }

                    BusyIndicator {
                        running: root.controller.scanRunning
                        visible: root.controller.scanRunning
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: root.style.success
                        }
                    }
                }

                ListView {
                    id: savedList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(300, savedList.contentHeight || root.controller.savedModel.count * 41)
                    visible: root.controller.savedModel.count > 0
                    clip: true
                    model: root.controller.savedModel
                    spacing: 6
                    ScrollBar.vertical: ScrollBar {
                        active: true
                        width: 4
                    }
                    delegate: SavedNetworkRow {
                        id: savedRow
                        style: root.style
                        isBusy: root.controller.isBusy
                        expanded: root.expandedDnsKey === "saved:" + savedRow.uuid
                        isConnected: savedRow.uuid === root.controller.activeConnectionUuid
                        isHome: root.homeSsids.includes(savedRow.ssid)
                        dnsBackend: root.controller.dns
                        onClicked: (uuid, ssid, isEnterprise) => root.controller.connectSaved(uuid, ssid, isEnterprise)
                        onToggleRequested: root.toggleDns("saved:" + savedRow.uuid)
                    }
                }

                Label {
                    visible: root.controller.statusLine.length > 0
                    text: root.controller.statusLine
                    font.family: root.style.textFont
                    font.pixelSize: 11
                    color: root.controller.statusIsError ? root.style.error : root.style.muted
                }

                TextArea {
                    visible: root.controller.errorVisible
                    text: root.controller.errorText
                    readOnly: true
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight + 20, 120)
                    font.family: root.style.textFont
                    font.pixelSize: 11
                    color: root.style.error
                    background: Rectangle {
                        radius: 12
                        color: Qt.rgba(root.style.error.r, root.style.error.g, root.style.error.b, 0.08)
                        border.width: 1
                        border.color: Qt.rgba(root.style.error.r, root.style.error.g, root.style.error.b, 0.25)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: root.style.border
                    visible: root.controller.isExpanded
                    opacity: 0.7
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: root.controller.isExpanded ? viewStack.children[viewStack.currentIndex].implicitHeight : 0
                    visible: root.controller.isExpanded
                    opacity: root.controller.isExpanded ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                        }
                    }

                    /* Controller owns page state; StackLayout only composes list and
                       credential pages while expanded height follows selected page. */
                    StackLayout {
                        id: viewStack

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        currentIndex: root.controller.currentPage

                        NetworkListPage {
                            controller: root.controller
                            style: root.style
                        }

                        CredentialsPage {
                            controller: root.controller
                            style: root.style
                        }
                    }
                }

                MenuButton {
                    style: root.style
                    Layout.fillWidth: true
                    implicitHeight: 38
                    text: "Open Advanced Settings"
                    icon: "󰒓"
                    kind: "ghost"
                    disabled: root.controller.isBusy
                    onClicked: root.controller.openAdvancedEditor()
                }
            }
        }
    }
}
