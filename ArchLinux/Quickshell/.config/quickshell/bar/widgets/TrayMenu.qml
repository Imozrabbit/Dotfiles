pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.core as Core

PopupWindow {
    id: root

    required property Core.Theme theme
    property Item anchorItem: null
    property QsMenuHandle menuHandle: null

    function openFor(item, handle) {
        if (!item || !handle)
            return;
        root.visible = false;
        root.anchorItem = item;
        root.menuHandle = handle;
        root.visible = true;
    }

    visible: false
    grabFocus: true
    color: "transparent"
    implicitWidth: Math.max(80, Math.min(root.screen ? root.screen.width - 24 : 600, menuStack.currentItem ? menuStack.currentItem.implicitWidth + 15 : 80))
    implicitHeight: Math.min(root.screen ? root.screen.height - 24 : 400, Math.max(40, menuStack.currentItem ? menuStack.currentItem.implicitHeight + 12 : 40))

    anchor.item: root.anchorItem
    anchor.rect.x: root.anchorItem ? root.anchorItem.width / 2 : 0
    anchor.rect.y: root.anchorItem ? root.anchorItem.height / 2 : 0
    // qmllint disable missing-type
    anchor.adjustment: PopupAdjustment.All
    // qmllint enable missing-type

    onVisibleChanged: {
        if (visible) {
            menuStack.clear();
            menuStack.push(menuPage, {
                menuHandle: root.menuHandle,
                subpage: false
            }, StackView.Immediate);
            menuCard.forceActiveFocus();
        } else {
            menuStack.clear();
        }
    }

    Rectangle {
        id: menuCard

        anchors.fill: parent
        focus: true
        color: root.theme.sysTrayBg
        border.color: root.theme.sysTrayBorderColor
        border.width: 1
        radius: root.theme.radiusMedium

        Keys.onPressed: event => {
            const page = menuStack.currentItem;
            // qmllint disable missing-property
            if (event.key === Qt.Key_Escape) {
                root.visible = false;
            } else if (event.key === Qt.Key_Left && menuStack.depth > 1) {
                menuStack.pop(StackView.Immediate);
            } else if (page && event.key === Qt.Key_Down) {
                page.moveSelection(1);
            } else if (page && event.key === Qt.Key_Up) {
                page.moveSelection(-1);
            } else if (page && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                page.activateSelected();
            } else {
                return;
            }
            // qmllint enable missing-property
            event.accepted = true;
        }

        StackView {
            id: menuStack

            anchors.fill: parent
            anchors.margins: 4
        }
    }

    Component {
        id: menuPage

        Item {
            id: page

            required property QsMenuHandle menuHandle
            required property bool subpage
            property int selectedIndex: -1

            implicitWidth: menuColumn.implicitWidth
            implicitHeight: menuColumn.implicitHeight

            function selectEntry(entry) {
                if (!entry || entry.isSeparator || !entry.enabled)
                    return;
                if (entry.hasChildren) {
                    menuStack.push(menuPage, {
                        menuHandle: entry,
                        subpage: true
                    }, StackView.Immediate);
                } else {
                    entry.triggered();
                    root.visible = false;
                }
            }

            function activateSelected() {
                const entries = opener.children.values;
                if (page.selectedIndex >= 0 && page.selectedIndex < entries.length)
                    page.selectEntry(entries[page.selectedIndex]);
            }

            function moveSelection(step) {
                const entries = opener.children.values;
                for (let n = 0; n < entries.length; n++) {
                    const index = (page.selectedIndex + step * (n + 1) + entries.length * (n + 1)) % entries.length;
                    if (entries[index].enabled && !entries[index].isSeparator) {
                        page.selectedIndex = index;
                        return;
                    }
                }
            }

            QsMenuOpener {
                id: opener
                menu: page.menuHandle
            }

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: menuColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: menuColumn

                    width: page.width
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        implicitWidth: backLabel.implicitWidth + 24
                        implicitHeight: page.subpage ? 32 : 0
                        visible: page.subpage
                        color: backHover.containsMouse ? Qt.lighter(root.theme.sysTrayBg, 1.4) : "transparent"

                        Text {
                            id: backLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            text: "‹ Back"
                            color: root.theme.tooltipColor
                            font.family: root.theme.tooltipFontFamily
                            font.pixelSize: root.theme.tooltipFontSize
                        }

                        MouseArea {
                            id: backHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: menuStack.pop(StackView.Immediate)
                        }
                    }

                    Repeater {
                        model: opener.children

                        delegate: Rectangle {
                            id: row

                            required property QsMenuEntry modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitWidth: row.modelData.isSeparator ? 0 : rowContents.implicitWidth + 8
                            implicitHeight: modelData.isSeparator ? 9 : 32
                            color: row.index === page.selectedIndex && row.modelData.enabled && !row.modelData.isSeparator ? Qt.lighter(root.theme.sysTrayBg, 1.4) : "transparent"

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                height: 1
                                visible: row.modelData.isSeparator
                                color: root.theme.sysTrayBorderColor
                            }

                            RowLayout {
                                id: rowContents

                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 4
                                spacing: 6
                                visible: !row.modelData.isSeparator

                                Text {
                                    visible: row.modelData.buttonType !== QsMenuButtonType.None
                                    Layout.preferredWidth: visible ? 20 : 0
                                    text: row.modelData.buttonType === QsMenuButtonType.None ? "" : row.modelData.buttonType === QsMenuButtonType.RadioButton ? (row.modelData.checkState === Qt.Checked ? "◉" : "○") : (row.modelData.checkState === Qt.Checked ? "☑" : "□")
                                    color: root.theme.tooltipColor
                                    font.pixelSize: root.theme.tooltipFontSize
                                }

                                IconImage {
                                    implicitSize: 16
                                    source: row.modelData.icon
                                    visible: row.modelData.icon !== ""
                                    Layout.preferredWidth: visible ? 16 : 0
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.text
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: row.modelData.enabled ? root.theme.tooltipColor : root.theme.whiteMutedColor
                                    font.family: root.theme.tooltipFontFamily
                                    font.pixelSize: root.theme.tooltipFontSize
                                }

                                Text {
                                    visible: row.modelData.hasChildren
                                    text: row.modelData.hasChildren ? "›" : ""
                                    color: root.theme.tooltipColor
                                    font.pixelSize: root.theme.tooltipFontSize
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: row.modelData.enabled && !row.modelData.isSeparator
                                hoverEnabled: true
                                onEntered: page.selectedIndex = row.index
                                onClicked: page.selectEntry(row.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
