import QtQuick

QtObject {
    id: root

    property var screens: []
    property string focusedScreenName: ""
    property var screen: null
    property var entries: []
    property string feedback: ""
    readonly property bool visible: root.entries.length > 0 && root.screen !== null

    function selectScreen(): var {
        return root.screens.find(candidate => candidate.name === root.focusedScreenName) ?? root.screens[0] ?? null;
    }

    function toggle(): void {
        if (root.entries.length > 0) {
            root.entries = [];
            return;
        }
        const target = root.selectScreen();
        if (!target)
            return;
        root.screen = target;
        root.feedback = "";
        root.entries = [
            {
                id: 1,
                appName: "Toast preview",
                summary: "Sample notification",
                body: "A sample message for checking spacing, wrapping and controls. Nothing here is sent to an application or saved in history.",
                time: "now",
                image: Qt.resolvedUrl("../../media/preview-cover.png").toString(),
                imageExpected: true,
                actions: [
                    {
                        id: "open",
                        text: "Open"
                    },
                    {
                        id: "dismiss",
                        text: "Dismiss"
                    }
                ],
                hasInlineReply: true,
                inlineReplyPlaceholder: "Sample reply (not sent)",
                code: "123456",
                critical: false
            },
            {
                id: 2,
                appName: "Toast preview",
                summary: "Sample critical notification",
                body: "Critical toasts use a slow blinking red border. These samples stay until you close them or toggle the preview off.",
                time: "now",
                actions: [],
                critical: true
            }
        ];
    }

    function dismiss(id: var): void {
        root.entries = root.entries.filter(entry => entry.id !== id);
    }

    function acknowledge(text: string): void {
        root.feedback = text;
    }

    onEntriesChanged: {
        if (root.entries.length === 0) {
            root.screen = null;
            root.feedback = "";
        }
    }
    onScreensChanged: {
        if (root.screen && !root.screens.includes(root.screen)) {
            root.screen = root.selectScreen();
            if (!root.screen)
                root.entries = [];
        }
    }
}
