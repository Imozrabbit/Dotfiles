pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQml.Models
import "../components"
import "../quickactions"
import "../power"
import "../sliders"
import "../media"
import "../notifications"
import "../common/Theme.js" as Theme
import "../common/Config.js" as ConfigParser

Item {
    id: root

    property color backgroundColor: Theme.panel
    property real backgroundOpacity: 0.4
    property var colors: ({})
    readonly property var themeColors: Theme.resolveColors(root.colors)
    property real leftPadding: 16
    property real rightPadding: 16
    property var quickActions: []
    property var network: null
    property var bluetooth: null
    property var vpn: null
    property var idleInhibit: null
    property var localsend: null
    property var hyprsunset: null
    property var dnd: null
    property var powerActions: ConfigParser.resolveConfig("{}").powerActions
    property bool powerActionsBusy: false
    property var sliders: ConfigParser.resolveConfig("{}").sliders
    property var volumeControl: null
    property var microphoneControl: null
    property var brightnessControl: null
    property var sections: ConfigParser.resolveConfig("{}").sections
    property var entries: []
    property bool historyBusy: false
    property string historyError: ""
    property bool toastPreviewAvailable: false
    property bool toastPreviewVisible: false
    property var mediaPlayer: undefined
    property var mediaPlayers: []
    property bool mediaActive: true
    property bool desktopCopyActive: false
    property var mediaSourceNames: ({})
    property var spectrumLevels: []
    readonly property bool mediaVisible: mediaSection.visible
    readonly property var currentMediaPlayer: media.currentPlayer
    readonly property real mediaCardWidth: media.width
    property alias volume: sliderGrid.volume
    signal actionRequested(string action)
    signal dismissRequested(var entryId, var revision)
    signal dismissGroupRequested(string appName)
    signal clearAllRequested
    signal toastPreviewRequested
    signal openRequested(var entryId)
    signal copyCodeRequested(string code)
    signal mediaRequested(var player, string action)
    signal mediaSeekRequested(var player, var trackKey, real ratio)
    signal notificationActionRequested(var entryId, string action, var revision)
    signal notificationReplyRequested(var entryId, string text, var revision)

    readonly property real historyHeaderHeight: historyHeading.height + 8 + (historyErrorLabel.visible ? historyErrorLabel.implicitHeight + 8 : 0)
    readonly property real availableScrollHeight: Math.max(0, scroll.height - (notificationsSection.visible ? notificationsSection.options.spacingBefore + root.historyHeaderHeight : 0))
    readonly property real controlsHeight: powerHeader.height + (quickSection.visible ? quickSection.height : 0) + (mediaSection.visible ? mediaSection.height : 0) + (slidersSection.visible ? slidersSection.height : 0)

    implicitWidth: 300
    implicitHeight: 900
    clip: true

    function sectionOptions(id: string): var {
        return root.sections.find(section => section.id === id) || {
            enabled: false,
            spacingBefore: 0
        };
    }

    function arrangeSections(): void {
        const items = {
            quickActions: quickSection,
            media: mediaSection,
            sliders: slidersSection,
            notifications: notificationsSection
        };
        root.sections.forEach((section, index) => {
            const from = items[section.id].ObjectModel.index;
            if (from !== index + 1)
                sectionModel.move(from, index + 1, 1);
        });
        Qt.callLater(root.revealActiveFocus);
    }

    onSectionsChanged: Qt.callLater(root.arrangeSections)
    Component.onCompleted: root.arrangeSections()

    function revealFocusedControl(item: Item): void {
        if (!item)
            return;
        let ancestor = item.parent;
        while (ancestor && ancestor !== root) {
            const viewport = ancestor as Flickable;
            if (viewport && viewport.flickableDirection !== Flickable.HorizontalFlick) {
                const position = item.mapToItem(viewport.contentItem, 0, 0);
                const maximum = Math.max(0, viewport.contentHeight - viewport.height);
                if (position.y < viewport.contentY)
                    viewport.contentY = Math.max(0, Math.min(maximum, position.y));
                else if (position.y + item.height > viewport.contentY + viewport.height)
                    viewport.contentY = Math.max(0, Math.min(maximum, position.y + item.height - viewport.height));
            }
            ancestor = ancestor.parent;
        }
    }

    function revealActiveFocus(): void {
        root.revealFocusedControl(root.Window.window ? root.Window.window.activeFocusItem : null);
    }

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            root.revealActiveFocus();
        }
    }

    Rectangle {
        objectName: "panelBackground"
        anchors.fill: parent
        anchors.rightMargin: -1
        topLeftRadius: Theme.radius
        bottomLeftRadius: Theme.radius
        color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, root.backgroundOpacity)
        border.width: border.color.a > 0 ? 1 : 0
        border.color: root.themeColors.panelBorder
    }

    Flickable {
        id: scroll
        objectName: "panelScroll"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.leftPadding
        anchors.rightMargin: root.rightPadding
        anchors.topMargin: 16
        height: Math.max(0, root.height - 28)
        contentWidth: width
        contentHeight: body.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onHeightChanged: Qt.callLater(root.revealActiveFocus)

        Column {
            id: body
            width: scroll.width
            spacing: 0
            onPositioningComplete: root.revealActiveFocus()

            Repeater {
                model: sectionModel
            }
        }

        ObjectModel {
            id: sectionModel

            PowerButtons {
                id: powerHeader
                objectName: "powerActions"
                width: body.width
                actions: root.powerActions
                enabled: !root.powerActionsBusy
                themeColors: root.themeColors
                onActionRequested: action => root.actionRequested(action)
            }

            Item {
                id: quickSection
                objectName: "quickActionsSection"
                readonly property var options: root.sectionOptions("quickActions")
                width: body.width
                height: visible ? options.spacingBefore + quickGrid.implicitHeight : 0
                visible: options.enabled && quickGrid.cells.length > 0
                enabled: visible

                QuickActionGrid {
                    id: quickGrid
                    objectName: "quickGrid"
                    y: quickSection.options.spacingBefore
                    width: parent.width
                    actions: root.quickActions
                    network: root.network
                    bluetooth: root.bluetooth
                    vpn: root.vpn
                    idleInhibit: root.idleInhibit
                    localsend: root.localsend
                    hyprsunset: root.hyprsunset
                    dnd: root.dnd
                    themeColors: root.themeColors
                    onActionRequested: index => root.actionRequested("quick:" + index)
                }
            }

            Item {
                id: mediaSection
                objectName: "mediaSection"
                readonly property var options: root.sectionOptions("media")
                width: body.width
                height: visible ? options.spacingBefore + media.height : 0
                visible: options.enabled
                enabled: visible

                MediaDeck {
                    id: media
                    objectName: "mediaDeck"
                    y: mediaSection.options.spacingBefore
                    width: parent.width
                    players: root.mediaPlayer === undefined ? root.mediaPlayers : root.mediaPlayer ? [root.mediaPlayer] : []
                    active: root.mediaActive
                    desktopCopyActive: root.desktopCopyActive
                    sourceNames: root.mediaSourceNames
                    spectrumLevels: root.spectrumLevels
                    themeColors: root.themeColors
                    onActionRequested: (player, action) => root.mediaRequested(player, action)
                    onSeekRequested: (player, trackKey, ratio) => root.mediaSeekRequested(player, trackKey, ratio)
                }
            }

            Item {
                id: slidersSection
                objectName: "slidersSection"
                readonly property var options: root.sectionOptions("sliders")
                width: body.width
                height: visible ? options.spacingBefore + sliderGrid.implicitHeight : 0
                visible: options.enabled && sliderGrid.cells.length > 0
                enabled: visible

                SliderGrid {
                    id: sliderGrid
                    objectName: "sliderGrid"
                    x: 6
                    y: slidersSection.options.spacingBefore
                    width: Math.max(0, parent.width - 12)
                    sliders: root.sliders
                    volumeControl: root.volumeControl
                    microphoneControl: root.microphoneControl
                    brightnessControl: root.brightnessControl
                    themeColors: root.themeColors
                }
            }

            Item {
                id: notificationsSection
                objectName: "notificationsSection"
                readonly property var options: root.sectionOptions("notifications")
                width: body.width
                height: visible ? options.spacingBefore + root.historyHeaderHeight + history.height : 0
                visible: options.enabled && (root.entries.length > 0 || root.historyError !== "" || root.toastPreviewAvailable)
                enabled: visible

                Column {
                    y: notificationsSection.options.spacingBefore
                    width: parent.width
                    spacing: 8

                    RowLayout {
                        id: historyHeading
                        width: parent.width
                        height: 32
                        spacing: 6
                        visible: history.visible || root.historyError !== "" || root.toastPreviewAvailable

                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumWidth: 0
                            text: "Notifications"
                            color: root.themeColors.text
                            font.family: Theme.textFont
                            font.pixelSize: 18
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        ActionTile {
                            objectName: "toastPreviewToggle"
                            visible: root.toastPreviewAvailable
                            themeColors: root.themeColors
                            implicitWidth: 28
                            implicitHeight: 28
                            glyph: "󰂚"
                            tooltip: "Toggle sample toasts"
                            checked: root.toastPreviewVisible
                            Accessible.checkable: true
                            Accessible.checked: root.toastPreviewVisible
                            onClicked: root.toastPreviewRequested()
                        }
                        ActionTile {
                            id: clearNotifications
                            themeColors: root.themeColors
                            Layout.alignment: Qt.AlignVCenter
                            glyph: "󰃢"
                            tooltip: "Clear all notifications"
                            enabled: !root.historyBusy && root.entries.length > 0
                            onClicked: root.clearAllRequested()
                            implicitWidth: 36
                            implicitHeight: 28

                            contentItem: Text {
                                id: clearGlyph
                                FontMetrics {
                                    id: clearMetrics
                                    font: clearGlyph.font
                                    readonly property rect ink: tightBoundingRect(clearNotifications.glyph)
                                }
                                // Center painted glyph, not its monospaced font advance.
                                leftPadding: Math.max(0, (width - clearMetrics.ink.width) / 2 - clearMetrics.ink.x)
                                text: clearNotifications.glyph
                                color: clearNotifications.enabled ? clearNotifications.iconColor : Qt.darker(clearNotifications.iconColor, 1.5)
                                font.family: Theme.iconFont
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                                textFormat: Text.PlainText
                                maximumLineCount: 1
                                clip: true
                            }
                        }
                    }

                    Text {
                        id: historyErrorLabel
                        objectName: "notificationHistoryError"
                        width: parent.width
                        visible: text !== ""
                        text: root.historyError
                        color: root.themeColors.warning
                        font.family: Theme.textFont
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }

                    HistoryView {
                        id: history
                        objectName: "notificationHistory"
                        width: parent.width
                        height: visible ? Math.min(implicitHeight, Math.max(0, root.availableScrollHeight - Math.min(root.controlsHeight, root.availableScrollHeight / 2))) : 0
                        entries: root.entries
                        clearEnabled: !root.historyBusy
                        themeColors: root.themeColors
                        onOpenRequested: entryId => root.openRequested(entryId)
                        onDismissRequested: (entryId, revision) => root.dismissRequested(entryId, revision)
                        onDismissGroupRequested: appName => root.dismissGroupRequested(appName)
                        onCopyCodeRequested: code => root.copyCodeRequested(code)
                        onActionRequested: (entryId, action, revision) => root.notificationActionRequested(entryId, action, revision)
                        onReplyRequested: (entryId, text, revision) => root.notificationReplyRequested(entryId, text, revision)
                        onHeightChanged: Qt.callLater(root.revealActiveFocus)
                        onImplicitHeightChanged: Qt.callLater(root.revealActiveFocus)
                    }
                }
            }
        }
    }
}
