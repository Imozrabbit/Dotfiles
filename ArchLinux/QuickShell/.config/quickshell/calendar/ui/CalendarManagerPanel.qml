pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../common/Theme.js" as Theme

Item {
    id: root

    required property var calendarService
    signal closeRequested
    property bool formMode: false
    property string editingId: ""
    property string nameText: ""
    property string idText: ""
    property string colorText: "#7b9acc"
    property string typeText: "local"
    property string errorMessage: ""
    property string confirmingId: ""
    property string removalMessage: ""
    property string sourcePath: ""
    property bool importPending: false
    property bool pickerOpen: false
    property string pickerPath: Quickshell.env("HOME")

    function beginCreate() {
        root.formMode = true;
        root.editingId = "";
        root.nameText = "";
        root.idText = "";
        root.colorText = "#7b9acc";
        root.typeText = "local";
        root.errorMessage = "";
        root.sourcePath = "";
    }

    function beginEdit(profile) {
        root.formMode = true;
        root.editingId = profile.id;
        root.nameText = profile.name;
        root.idText = profile.id;
        root.colorText = profile.color;
        root.typeText = profile.type;
        root.errorMessage = "";
        root.sourcePath = "";
    }

    function showList() {
        root.formMode = false;
        root.editingId = "";
        root.errorMessage = "";
        root.confirmingId = "";
        root.removalMessage = "";
        root.sourcePath = "";
        root.importPending = false;
    }

    function saveProfile() {
        const draft = {
            id: root.idText,
            name: root.nameText,
            color: root.colorText,
            type: root.typeText
        };
        const importing = root.typeText === "imported" && (root.editingId.length === 0 || root.sourcePath.length > 0);
        const result = importing ? root.calendarService.importIcsProfile(draft, root.sourcePath, root.editingId) : root.editingId.length > 0 ? root.calendarService.updateProfile(root.editingId, {
            name: root.nameText,
            color: root.colorText
        }) : root.calendarService.createProfile(draft);
        if (!result.ok) {
            root.errorMessage = result.message;
            return;
        }
        if (result.pending) {
            root.importPending = true;
            root.errorMessage = "Importing ICS source...";
            return;
        }
        root.showList();
    }

    function requestRemove(profile) {
        if (root.confirmingId !== profile.id) {
            root.confirmingId = profile.id;
            root.errorMessage = "";
            root.removalMessage = "Detach profile? Calendar data will remain on disk.";
            return;
        }
        const result = root.calendarService.removeProfile(profile.id);
        if (!result.ok)
            root.errorMessage = result.message;
        else {
            root.confirmingId = "";
            root.removalMessage = "";
        }
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.48)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.closeRequested()
        }
    }

    function navigatePicker(path) {
        root.pickerPath = path;
    }

    function pickerParent() {
        return folderModel.parentFolder.toString().replace(/^file:\/\//, "") || "/";
    }

    function chooseFolder() {
        root.sourcePath = root.pickerPath;
        root.pickerOpen = false;
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + root.pickerPath
        showDirs: true
        showFiles: true
        showHidden: true
        showDirsFirst: true
        nameFilters: ["*.ics"]
        sortField: FolderListModel.Name
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(460, Math.max(0, parent.width - 48))
        height: Math.min(parent.height - 48, root.formMode ? 520 : 360)
        color: Theme.surface
        radius: 13
        border.width: 1
        border.color: Theme.border
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => mouse.accepted = true
        }

        Rectangle {
            id: panelHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 13
            height: 50
            radius: 13
            color: Theme.surfaceRaised

            Text {
                anchors.centerIn: parent
                text: root.formMode ? (root.editingId.length > 0 ? "Edit calendar" : "New calendar") : "Manage calendars"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 21
                font.weight: Font.DemiBold
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.top: panelHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.margins: 20
            spacing: 10

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.formMode ? formComponent : listComponent
            }

            Text {
                visible: root.errorMessage.length > 0 || root.removalMessage.length > 0
                Layout.fillWidth: true
                text: root.errorMessage.length > 0 ? root.errorMessage : root.removalMessage
                textFormat: Text.PlainText
                color: root.errorMessage.length > 0 ? Theme.currentTime : Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }

        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 58

            ActionButton {
                anchors.left: parent.left
                anchors.leftMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                minimumWidth: 86
                enabled: !root.importPending
                label: root.formMode ? (root.typeText === "imported" ? (root.editingId.length > 0 ? "Replace" : "Import") : "Save") : "New calendar"
                primary: root.formMode
                onClicked: root.formMode ? root.saveProfile() : root.beginCreate()
            }

            ActionButton {
                anchors.right: parent.right
                anchors.rightMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                minimumWidth: 86
                enabled: !root.importPending
                label: root.formMode ? "Cancel" : "Close"
                onClicked: root.formMode ? root.showList() : root.closeRequested()
            }
        }
    }

    Connections {
        target: root.calendarService
        function onImportResultChanged() {
            const result = root.calendarService.importResult;
            if (!result)
                return;
            root.importPending = false;
            if (!result.ok)
                root.errorMessage = result.message;
            else
                root.showList();
        }
    }

    Component {
        id: listComponent

        ListView {
            clip: true
            spacing: 7
            model: root.calendarService.calendars
            delegate: Rectangle {
                id: calendarEntry
                required property var modelData
                width: ListView.view.width
                height: 52
                color: Theme.background
                radius: Theme.radius
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 7
                    spacing: 3

                    Rectangle {
                        Layout.preferredWidth: 9
                        Layout.preferredHeight: 9
                        radius: 5
                        color: calendarEntry.modelData.color
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: calendarEntry.modelData.name
                            textFormat: Text.PlainText
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        Text {
                            text: calendarEntry.modelData.type + (calendarEntry.modelData.missing ? " · Missing" : calendarEntry.modelData.errorMessage ? " · Error" : "")
                            textFormat: Text.PlainText
                            color: Theme.textMuted
                            font.pixelSize: 10
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 4

                        GlyphButton {
                            label: calendarEntry.modelData.visible ? "󰈈" : "󰈉"
                            onClicked: root.calendarService.setCalendarVisible(calendarEntry.modelData.id, !calendarEntry.modelData.visible)
                        }
                        GlyphButton {
                            label: "󰏫"
                            onClicked: root.beginEdit(calendarEntry.modelData)
                        }
                        GlyphButton {
                            label: root.confirmingId === calendarEntry.modelData.id ? "" : "󰆴"
                            destructive: root.confirmingId === calendarEntry.modelData.id
                            onClicked: root.requestRemove(calendarEntry.modelData)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: formComponent

        ColumnLayout {
            spacing: 5

            FieldLabel {
                text: "NAME"
                Layout.leftMargin: 5
            }
            FormField {
                text: root.nameText
                placeholderText: "Calendar name"
                onTextEdited: root.nameText = text
            }
            FieldLabel {
                text: "ID"
                Layout.leftMargin: 5
                Layout.topMargin: 10
            }
            FormField {
                text: root.idText
                placeholderText: "lowercase-id"
                enabled: root.editingId.length === 0
                onTextEdited: root.idText = text
            }
            FieldLabel {
                text: "TYPE"
                Layout.leftMargin: 5
                Layout.topMargin: 10
            }
            InlineWheelField {
                id: typePicker
                label: ""
                model: ["local", "imported"]
                currentIndex: root.typeText === "imported" ? 1 : 0
                displayText: root.typeText
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                enabled: root.editingId.length === 0
                onExpansionRequested: expanded = !expanded
                onCollapseRequested: expanded = false
                onSelectionRequested: (index, value) => root.typeText = String(value)
            }
            FieldLabel {
                text: "COLOR"
                Layout.leftMargin: 5
                Layout.topMargin: 10
            }
            RowLayout {
                Layout.fillWidth: true
                FormField {
                    text: root.colorText
                    placeholderText: "#rrggbb"
                    onTextEdited: root.colorText = text
                }
                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: Theme.radius
                    color: root.colorText
                    border.width: 1
                    border.color: Theme.border
                }
            }
            FieldLabel {
                visible: root.typeText === "imported"
                text: root.editingId.length > 0 ? "REPLACE ICS SOURCE" : "ICS SOURCE"
                Layout.leftMargin: 5
                Layout.topMargin: 10
            }
            Rectangle {
                id: sourceSelector
                visible: root.typeText === "imported"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: Theme.background
                radius: Theme.radius
                border.width: 1
                border.color: Theme.border
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 30
                    text: root.sourcePath.length > 0 ? root.sourcePath : root.editingId.length > 0 ? "Leave empty to keep current source" : "Choose an .ics file or folder"
                    textFormat: Text.PlainText
                    color: root.sourcePath.length > 0 ? Theme.text : Theme.textMuted
                    font.family: Theme.font
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: Theme.textMuted
                    font.family: Theme.font
                    font.pixelSize: 17
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.importPending
                    onClicked: root.pickerOpen = !root.pickerOpen
                }
            }
            Controls.Popup {
                id: sourcePicker
                parent: Controls.Overlay.overlay
                z: 1000
                implicitWidth: sourceSelector.width
                implicitHeight: 280
                padding: 8
                modal: true
                dim: true
                closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
                Controls.Overlay.modal: Rectangle {
                    color: Qt.rgba(0, 0, 0, 0.4)
                }
                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
                function positionPicker() {
                    const position = sourceSelector.mapToItem(parent, 0, sourceSelector.height - height);
                    x = position.x;
                    y = position.y;
                }
                onOpened: positionPicker()
                onClosed: root.pickerOpen = false
                contentItem: ColumnLayout {
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 5
                            text: root.pickerPath
                            textFormat: Text.PlainText
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            elide: Text.ElideMiddle
                        }
                        GlyphButton {
                            label: ""
                            Layout.rightMargin: 5
                            onClicked: sourcePicker.close()
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        color: Theme.surfaceRaised
                        radius: Theme.radius
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            text: "  .."
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.navigatePicker(root.pickerParent())
                        }
                    }
                    ListView {
                        id: sourceEntries
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: folderModel
                        spacing: 2
                        delegate: Rectangle {
                            id: entry
                            required property string fileName
                            required property bool fileIsDir
                            required property string filePath
                            required property url fileUrl
                            width: sourceEntries.width
                            height: 28
                            radius: Theme.radius
                            color: entryHover.hovered ? Theme.surfaceRaised : "transparent"
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                text: (entry.fileIsDir ? "  " : "  ") + entry.fileName
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideMiddle
                            }
                            HoverHandler {
                                id: entryHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (entry.fileIsDir) {
                                        root.pickerPath = entry.filePath;
                                    } else {
                                        root.sourcePath = entry.filePath;
                                        sourcePicker.close();
                                    }
                                }
                            }
                        }
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        minimumWidth: 86
                        label: "Use this folder"
                        primary: true
                        onClicked: root.chooseFolder()
                    }
                }
            }
            Connections {
                target: root
                function onPickerOpenChanged() {
                    if (root.pickerOpen && root.formMode && root.typeText === "imported")
                        sourcePicker.open();
                    else
                        sourcePicker.close();
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 9
        font.letterSpacing: 1.2
        font.weight: Font.DemiBold
    }

    component FormField: Controls.TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        color: Theme.text
        placeholderTextColor: Theme.textMuted
        selectionColor: Theme.accent
        selectedTextColor: Theme.background
        font.pixelSize: 13
        font.family: Theme.font
        leftPadding: 10
        rightPadding: 10
        background: Rectangle {
            radius: Theme.radius
            color: Theme.background
            border.width: 1
            border.color: Theme.border
        }
    }

    component GlyphButton: Rectangle {
        id: glyphButton
        required property string label
        property bool destructive: false
        signal clicked
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        radius: Theme.radius
        color: glyphHover.hovered ? Theme.surfaceRaised : "transparent"

        Text {
            anchors.fill: parent
            text: glyphButton.label
            color: glyphButton.destructive ? Theme.currentTime : glyphHover.hovered ? Theme.text : Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        HoverHandler {
            id: glyphHover
            cursorShape: Qt.PointingHandCursor
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: glyphButton.clicked()
        }
    }
}
