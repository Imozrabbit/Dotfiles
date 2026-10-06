pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var colors
    required property var service
    readonly property bool menuOpen: geSelector.menuOpen
    readonly property var packageState: service.snapshot?.package ?? {state:"unavailable",installedVersion:null,availableVersion:null,messages:[]}
    readonly property var versions: service.snapshot?.geVersions ?? []
    readonly property bool canSelect: !service.busy && versions.length > 0 && (service.snapshot?.blockers.length ?? 1) === 0
    spacing: 12
    function closeMenu() { geSelector.closeMenu(); }
    Section {
        id: launcherPackageCard
        colors: root.colors
        implicitHeight: packageContent.implicitHeight + 24
        ColumnLayout {
            id: packageContent
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Label { theme: root.theme; colors: root.colors; text: "umu-launcher"; font.bold: true }
                Label {
                    theme: root.theme; colors: root.colors
                    Layout.fillWidth: false
                    text: root.packageState.state === "unavailable" ? "Unavailable" : root.packageState.state === "updateAvailable" ? "Update available" : root.packageState.state === "notInstalled" ? "Not installed" : "Up to date"
                    horizontalAlignment: Text.AlignRight
                    color: root.packageState.state === "unavailable" ? root.colors.error : root.packageState.state === "updateAvailable" ? root.colors.warning : root.packageState.state === "notInstalled" ? root.colors.secondary : root.colors.success
                    font.pixelSize: 12
                }
            }
            RowLayout {
                Label { theme: root.theme; colors: root.colors; Layout.fillWidth: false; text: "Installed"; color: root.colors.dimText }
                Label { theme: root.theme; colors: root.colors; text: root.packageState.installedVersion ?? "—"; horizontalAlignment: Text.AlignRight; color: root.colors.dimText }
            }
            RowLayout {
                Label { theme: root.theme; colors: root.colors; Layout.fillWidth: false; text: "Available"; color: root.colors.dimText }
                Label { theme: root.theme; colors: root.colors; text: root.packageState.availableVersion ?? "—"; horizontalAlignment: Text.AlignRight; color: root.colors.dimText }
            }
            Label { theme: root.theme; colors: root.colors; text: "Official Arch repository"; color: root.colors.secondary; font.pixelSize: 12 }
            Messages { theme: root.theme; colors: root.colors; Layout.topMargin: 4; entries: root.packageState.messages.concat(root.service.messages.package) }
        }
    }
    Section {
        id: launcherProtonCard
        colors: root.colors
        implicitHeight: selectionContent.implicitHeight + 24
        ColumnLayout {
            id: selectionContent
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Label { theme: root.theme; colors: root.colors; text: "Proton selection"; font.bold: true }
                Action { theme: root.theme; colors: root.colors; text: "Sync latest GE"; enabled: root.canSelect; onClicked: root.service.syncGe() }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: -3
                Layout.rightMargin: -1
                Layout.topMargin: 6
                GeSelector {
                    id: geSelector
                    theme: root.theme; colors: root.colors
                    versions: root.versions
                    currentVersion: root.service.snapshot?.currentGeVersion ?? ""
                    enabled: root.canSelect
                    onSelectRequested: name => root.service.selectGe(name)
                }
            }
            Messages {
                theme: root.theme; colors: root.colors
                Layout.topMargin: 3
                entries: (root.service.snapshot?.messages.selection ?? []).concat(root.service.messages.selection)
            }
        }
    }
    Action {
        id: locationsToggle
        theme: root.theme; colors: root.colors
        Layout.alignment: Qt.AlignLeft
        text: (checked ? "▾ " : "▸ ") + "Locations"
        flat: true
        checkable: true
        leftPadding: 4
        rightPadding: 12
    }
    Item {
        visible: locationsToggle.checked
        Layout.fillWidth: true
        implicitHeight: locationsContent.implicitHeight
        Rectangle { x: 12; width: 1; height: parent.height; color: root.colors.guide }
        ColumnLayout {
            id: locationsContent
            x: 25
            width: parent.width - 37
            spacing: 12
            Repeater {
                model: [
                    {label:"Install directory",path:root.service.config.compatibilityToolsDir},
                    {label:"Sandbox directory",path:root.service.config.sandboxCompatibilityToolsDir},
                    {label:"umu config",path:root.service.config.umuConfigPath}
                ]
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4
                    Label { theme: root.theme; colors: root.colors; text: parent.modelData.label; font.pixelSize: 13 }
                    Label { theme: root.theme; colors: root.colors; text: parent.modelData.path; font.pixelSize: 12; color: root.colors.dimText; wrapMode: Text.WrapAnywhere }
                }
            }
        }
    }
}
