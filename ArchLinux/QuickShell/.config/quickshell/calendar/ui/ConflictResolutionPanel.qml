pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common/Theme.js" as Theme

Item {
    id: root

    required property var conflictService
    property var conversionService: null
    signal closeRequested

    readonly property bool conversionMode: root.conversionService !== null
    readonly property bool allowLocalOnly: root.conversionMode && root.conversionService.allowLocalOnly !== false
    readonly property var conflict: root.conversionMode ? root.conversionService.conversionConflict : root.conflictService.currentConflict
    readonly property string stagedChoice: root.conversionService?.conversionChoices.find(choice => choice.uid === root.conflict?.uid)?.choice || ""
    readonly property var local: root.conflict ? root.conflict.local : null
    readonly property var remote: root.conflict ? root.conflict.remote : null
    readonly property bool groupProtected: root.conflict !== null && root.conflict.kind === "group" && root.conflict.ready !== true
    readonly property bool selectionEnabled: root.conflict !== null && !root.groupProtected && (root.conversionMode ? !root.conversionService.busy && !root.conversionService.conversionSession?.remoteAttempted && (!["remote-delete", "local-preserve", "local-to-synced"].includes(root.conversionService.conversionKind) || root.conversionService.conversionSession?.phase === "review") : !root.conflictService.busy && root.conflictService.stateValid)
    property string selectedSide: ""
    property string selectedUid: ""
    property string selectedCalendarId: ""
    property string selectedLocalIcs: ""
    property string selectedRemoteIcs: ""
    property string selectedRevision: ""
    property bool confirmPending: false

    readonly property var fields: [
        {
            label: "WHEN",
            key: "start"
        },
        {
            label: "UNTIL",
            key: "end"
        },
        {
            label: "REPEAT",
            key: "recurrence"
        },
        {
            label: "LOCATION",
            key: "location"
        },
        {
            label: "DESCRIPTION",
            key: "description"
        },
        {
            label: "REMINDERS",
            key: "reminders"
        }
    ]

    function value(data, key) {
        if (!data)
            return "Unavailable";
        if (key === "reminders")
            return data.reminders && data.reminders.length > 0 ? data.reminders.map(reminder => reminder.minutesBefore + " min before").join(", ") : "None";
        if (key === "allDay")
            return data.allDay ? "All day" : "Timed";
        if (key === "recurrence") {
            const rule = data.recurrence;
            if (!rule)
                return data.recurrenceSummary || "None";
            const pattern = rule.frequency === "yearly" ? rule.pattern.dates.map(date => String(date.month).padStart(2, "0") + "-" + String(date.day).padStart(2, "0")).join(", ") : JSON.stringify(rule.pattern);
            const ending = rule.ends.mode === "count" ? "after " + rule.ends.count + " occurrences" : rule.ends.mode === "date" ? "through " + rule.ends.date : "never ends";
            return rule.frequency + " / interval " + rule.interval + " · " + pattern + " · from " + rule.startsOn + " · " + ending + (data.timezone ? " · " + data.timezone : "");
        }
        return String(data[key] ?? "") || "None";
    }

    function differs(key) {
        return root.value(root.local, key) !== root.value(root.remote, key);
    }

    function selectSide(side) {
        if (!root.selectionEnabled || !(root.allowLocalOnly ? ["local", "remote", "local-only"] : ["local", "remote"]).includes(side))
            return;
        root.selectedUid = root.conflict.uid;
        root.selectedCalendarId = root.conflict.calendarId || "";
        root.selectedRevision = root.conflict.revision || "";
        root.selectedLocalIcs = root.conflict.localIcs || "";
        root.selectedRemoteIcs = root.conflict.remoteIcs || "";
        root.selectedSide = side;
    }

    function restoreConversionChoice() {
        if (!root.conversionMode)
            return;
        root.selectedSide = root.stagedChoice;
        root.selectedUid = root.conflict?.uid || "";
        root.selectedRevision = root.conflict?.revision || "";
    }

    function confirmChoice() {
        if (root.conversionMode) {
            if (root.selectionEnabled && root.selectedSide.length > 0)
                root.stageChoice(root.selectedSide);
            return;
        }
        if (root.groupProtected || root.selectedSide.length === 0 || root.conflictService.busy || !root.conflictService.stateValid)
            return;
        root.confirmPending = true;
        root.conflictService.choose(root.selectedSide, root.selectedUid, root.selectedRevision, root.selectedCalendarId);
    }

    function cancelChoice() {
        root.selectedSide = "";
        root.confirmPending = false;
        root.closeRequested();
    }

    function stageChoice(choice) {
        if (!root.conflict)
            return;
        const result = root.conversionService.stageConversionChoice(root.selectedUid, root.selectedRevision, choice);
        if (!result.ok)
            root.conversionService.conversionError = result.message;
        else if (root.conversionService.conversionReady)
            root.closeRequested();
    }

    function cancelConversion() {
        const result = root.conversionService.cancelConversion();
        if (!result.ok)
            root.conversionService.conversionError = result.message;
    }

    onConflictChanged: root.restoreConversionChoice()
    onStagedChoiceChanged: root.restoreConversionChoice()
    onConversionModeChanged: {
        root.selectedSide = "";
        root.confirmPending = false;
        root.restoreConversionChoice();
    }
    Component.onCompleted: root.restoreConversionChoice()

    Connections {
        target: root.conversionService
        function onConversionSessionChanged() {
            if (!root.conversionService.conversionSession)
                root.closeRequested();
        }
    }

    Connections {
        target: root.conflictService
        function onConflictsChanged() {
            if (root.conversionMode)
                return;
            if (root.confirmPending && !root.conflictService.hasConflict)
                root.closeRequested();
            const uid = root.conflict ? root.conflict.uid : "";
            const calendarId = root.conflict ? root.conflict.calendarId || "" : "";
            const localIcs = root.conflict ? root.conflict.localIcs : "";
            const remoteIcs = root.conflict ? root.conflict.remoteIcs : "";
            if (calendarId !== root.selectedCalendarId || uid !== root.selectedUid || localIcs !== root.selectedLocalIcs || remoteIcs !== root.selectedRemoteIcs) {
                root.selectedSide = "";
                root.confirmPending = false;
                root.selectedUid = uid;
                root.selectedCalendarId = calendarId;
                root.selectedLocalIcs = localIcs;
                root.selectedRemoteIcs = remoteIcs;
                root.selectedRevision = root.conflict ? root.conflict.revision || "" : "";
            }
        }
        function onErrorMessageChanged() {
            if (root.conflictService.errorMessage.length > 0)
                root.confirmPending = false;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.48)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.closeRequested()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(720, Math.max(0, parent.width - 48))
        height: Math.min(650, Math.max(0, parent.height - 48))
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
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 65
            color: Qt.rgba(Theme.currentTime.r, Theme.currentTime.g, Theme.currentTime.b, 0.18)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: root.conversionMode ? root.allowLocalOnly || root.conversionService.conversionKind === "local-to-synced" ? "Conversion conflict" : "Preservation review" : "Conflict"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 21
                font.weight: Font.DemiBold
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                text: root.conflict ? root.conversionMode ? (root.conversionService.conversionIndex + 1) + " of " + root.conversionService.conversionSession.conflicts.length : ((root.conflictService.conflicts.indexOf(root.conflict) + 1) + " of " + root.conflictService.conflicts.length) : "No conflicts"
                color: Theme.textMuted
                font.family: Theme.font
                font.pixelSize: 12
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                text: root.conflict ? (root.conflict.calendarId ? root.conflict.calendarId + " · " : "") + root.conflict.uid : ""
                textFormat: Text.PlainText
                color: Theme.textMuted
                font.pixelSize: 9
                elide: Text.ElideMiddle
                width: 150
                horizontalAlignment: Text.AlignRight
            }
        }

        Flickable {
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + 36
            clip: true
            flickableDirection: Flickable.VerticalFlick

            ColumnLayout {
                id: contentColumn
                x: 20
                y: 18
                width: Math.max(0, parent.width - 40)
                spacing: 15

                Text {
                    Layout.fillWidth: true
                    text: root.groupProtected ? "Group protected. " + (root.conflict.problem || "Whole-series conflict resolution required.") : root.conflict && root.conflict.kind === "group" ? "Choose complete series version. All member resources are resolved together; unknown ICS properties stay unchanged." : "Choose complete event version. Unknown ICS properties stay unchanged."
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                ColumnLayout {
                    visible: root.conversionMode
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: root.allowLocalOnly ? "Choices stay offline until final confirmation. Local choice updates server unless keep-local option is selected." : root.conversionService?.conversionKind === "local-to-synced" ? "Choices stay offline until every differing event or series has a version. After the last choice, refresh, attachment and synchronization run automatically; Local replaces the matching remote version. Unique events from both sides stay." : root.conversionService?.conversionKind === "local-preserve" ? "Server cards show previously captured versions, not live server data. Choose what to keep locally. No server requests, uploads or DELETE." : "Choose the version to keep locally. Confirm stays offline and never uploads. Only the separate final server-deletion confirmation sends DELETE."
                        wrapMode: Text.Wrap
                        color: Theme.textMuted
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                    ActionButton {
                        id: keepLocalChoice
                        objectName: "conversionKeepLocal"
                        visible: root.allowLocalOnly
                        Layout.fillWidth: true
                        enabled: visible && root.selectionEnabled
                        label: "Keep local, leave server unchanged"
                        primary: root.selectedSide === "local-only"
                        activeFocusOnTab: enabled
                        border.width: activeFocus ? 2 : primary ? 0 : 1
                        border.color: activeFocus ? Theme.text : Theme.border
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: keepLocalChoice.label
                        Accessible.checked: keepLocalChoice.primary
                        Accessible.onPressAction: keepLocalChoice.clicked()
                        Keys.onPressed: event => {
                            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                return;
                            keepLocalChoice.clicked();
                            event.accepted = true;
                        }
                        onClicked: if (root.conversionMode)
                            root.selectSide("local-only")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            {
                                label: "THIS DEVICE",
                                side: "local",
                                data: root.local
                            },
                            {
                                label: root.conversionMode && !root.allowLocalOnly ? "SERVER" : "OTHER DEVICE",
                                side: "remote",
                                data: root.remote
                            }
                        ]

                        delegate: Rectangle {
                            id: versionCard
                            objectName: "conflictVersion_" + versionCard.modelData.side
                            enabled: visible && root.selectionEnabled
                            required property var modelData
                            readonly property bool selected: (root.selectedSide === "local-only" ? "local" : root.selectedSide) === modelData.side
                            activeFocusOnTab: enabled
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: versionCard.modelData.label
                            Accessible.checked: versionCard.selected
                            Accessible.onPressAction: root.selectSide(versionCard.modelData.side)
                            Keys.onPressed: event => {
                                if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                    return;
                                root.selectSide(versionCard.modelData.side);
                                event.accepted = true;
                            }
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: cardContent.implicitHeight + 35
                            color: cardTap.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : selected ? Qt.alpha(Theme.accent, 0.14) : cardHover.hovered ? Theme.surfaceRaised : Theme.background
                            radius: Theme.radius
                            border.width: selected || activeFocus ? 2 : 1
                            border.color: selected ? Theme.accent : activeFocus ? Theme.text : cardHover.hovered ? Theme.textMuted : Theme.border

                            HoverHandler {
                                id: cardHover
                                enabled: versionCard.enabled
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                id: cardTap
                                enabled: versionCard.enabled
                                onTapped: root.selectSide(versionCard.modelData.side)
                            }

                            ColumnLayout {
                                id: cardContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                anchors.topMargin: 15
                                spacing: 11

                                Text {
                                    Layout.fillWidth: true
                                    text: versionCard.modelData.label
                                    color: versionCard.selected ? Theme.accent : Theme.textMuted
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.2
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.value(versionCard.modelData.data, "title")
                                    textFormat: Text.PlainText
                                    color: Theme.text
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Item {
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 0.5
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 20

                                    Repeater {
                                        model: root.fields
                                        delegate: ColumnLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.modelData.label
                                                color: Theme.textMuted
                                                font.pixelSize: 9
                                                font.letterSpacing: 1.2
                                                font.weight: Font.DemiBold
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 8
                                                text: root.value(versionCard.modelData.data, parent.modelData.key)
                                                textFormat: Text.PlainText
                                                color: root.differs(parent.modelData.key) ? Theme.currentTime : Theme.text
                                                font.pixelSize: 12
                                                wrapMode: Text.Wrap
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 1
                                                Layout.topMargin: 5
                                                color: Theme.border
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.conversionMode ? root.conversionService.conversionError : root.conflictService.errorMessage
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.currentTime
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }

        RowLayout {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 58
            anchors.leftMargin: 17
            anchors.rightMargin: 17
            anchors.bottomMargin: 5
            spacing: 8

            Rectangle {
                id: confirmButton
                objectName: "conflictConfirm"
                enabled: visible && root.selectionEnabled && root.selectedSide.length > 0
                activeFocusOnTab: enabled
                Accessible.role: Accessible.Button
                Accessible.name: "Confirm choice"
                Accessible.onPressAction: root.confirmChoice()
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                        return;
                    root.confirmChoice();
                    event.accepted = true;
                }
                Layout.preferredWidth: confirmText.implicitWidth + 28
                Layout.preferredHeight: 34
                radius: Theme.radius
                border.width: activeFocus ? 1 : 0
                border.color: Theme.text
                color: confirmMouse.pressed ? Qt.darker(Theme.accent, 1.2) : confirmHover.hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                opacity: enabled ? 1 : 0.5
                Text {
                    id: confirmText
                    anchors.centerIn: parent
                    text: "Confirm"
                    color: Theme.background
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                HoverHandler {
                    id: confirmHover
                    enabled: confirmButton.enabled
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    id: confirmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: confirmButton.enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.confirmChoice()
                }
            }

            ActionButton {
                visible: root.conversionMode
                enabled: !root.conversionService?.busy && root.conversionService?.conversionIndex > 0
                label: card.width < 500 ? "‹" : "Previous"
                minimumWidth: card.width < 500 ? 34 : 80
                Accessible.role: Accessible.Button
                Accessible.name: "Previous conflict"
                onClicked: root.conversionService.conversionIndex--
            }
            ActionButton {
                visible: root.conversionMode
                enabled: !root.conversionService?.busy && root.conversionService?.conversionIndex < (root.conversionService?.conversionSession?.conflicts.length || 0) - 1
                label: card.width < 500 ? "›" : "Next"
                minimumWidth: card.width < 500 ? 34 : 80
                Accessible.role: Accessible.Button
                Accessible.name: "Next conflict"
                onClicked: root.conversionService.conversionIndex++
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                visible: !root.conversionMode
                Layout.preferredWidth: cancelText.implicitWidth + 28
                Layout.preferredHeight: 34
                radius: Theme.radius
                color: cancelMouse.pressed ? Qt.darker(Theme.surfaceRaised, 1.2) : cancelHover.hovered ? Theme.surfaceRaised : Theme.background
                border.width: 1
                border.color: Theme.border
                opacity: root.conflictService.busy ? 0.5 : 1
                Text {
                    id: cancelText
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                HoverHandler {
                    id: cancelHover
                    enabled: !root.conflictService.busy
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !root.conflictService.busy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.cancelChoice()
                }
            }
            ActionButton {
                visible: root.conversionMode
                enabled: !root.conversionService?.busy && !root.conversionService?.conversionSession?.remoteAttempted && root.conversionService?.conversionCanCancel !== false
                label: root.allowLocalOnly || root.conversionService?.conversionKind === "local-to-synced" ? "Cancel conversion" : root.conversionService?.conversionKind === "local-preserve" ? "Cancel preservation" : "Cancel deletion"
                activeFocusOnTab: enabled
                border.color: activeFocus ? Theme.text : Theme.border
                Accessible.role: Accessible.Button
                Accessible.name: label
                Accessible.onPressAction: clicked()
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                        return;
                    clicked();
                    event.accepted = true;
                }
                onClicked: root.cancelConversion()
            }
        }
    }
}
