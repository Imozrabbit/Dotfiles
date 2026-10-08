import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const source = await readFile(new URL("../widgets/SystemTrayItems.qml", import.meta.url), "utf8");
const workspaces = await readFile(new URL("../widgets/Workspaces.qml", import.meta.url), "utf8");
const trayVisible = workspaces.match(/readonly property bool trayVisible: ([^\n]+)/)?.[1];
assert.ok(trayVisible, "One actual tray-presence condition must drive icons and separators");
const separators = [...workspaces.matchAll(/visible: ([^\n]+)\n\s+Layout.preferredWidth: 1/g)].map(match => match[1]);
assert.equal(separators.length, 2);
for (const showTray of [false, true])
    for (const count of [0, 2])
        for (const showProtonManager of [false, true])
            for (const showWorkspaces of [false, true]) {
                const root = { showTray, showProtonManager, showWorkspaces, showLauncher: true, showUpdates: false };
                const context = { root, SystemTray: { items: { values: Array(count) } } };
                root.trayVisible = runInNewContext(trayVisible, context);
                assert.equal(root.trayVisible, showTray && count > 0);
                assert.equal(runInNewContext(separators[0], context), (root.trayVisible || showProtonManager) && showWorkspaces);
                assert.equal(runInNewContext(separators[1], context), root.trayVisible || showProtonManager || showWorkspaces);
            }
assert.match(source, /Repeater\s*\{[\s\S]*?model:\s*SystemTray\.items/,
    "Tray items render inline from SystemTray.items");
assert.match(source, /QsMenuOpener\s*\{[\s\S]*?menu:\s*trayIcon\.modelData\.menu/,
    "Each item exposes its actual menu entries");
assert.match(source, /children\.values\.length\s*>\s*0/,
    "Empty tray menus must not open");
assert.match(source, /trayIcon\.modelData\.activate\(\)/,
    "Left-click activation remains available");
const visibilityHandler = source.match(/onVisibleChanged: \{([\s\S]*?)\n    \}/)?.[1];
assert.ok(visibilityHandler, "Hide context menu when tray is disabled or bar hides");
const trayMenu = { visible: true };
runInNewContext(visibilityHandler, { root: { visible: false }, trayMenu });
assert.equal(trayMenu.visible, false);
const clickHandler = source.match(/onClicked: mouse => \{([\s\S]*?)\n                \}/)?.[1];
assert.ok(clickHandler);
for (const button of [1, 2])
    for (const onlyMenu of [false, true])
        for (const hasMenu of [false, true])
            for (const count of [0, 2]) {
                let activations = 0, openings = 0;
                const trayIcon = { modelData: { onlyMenu, hasMenu, activate: () => activations++ } };
                runInNewContext(clickHandler, {
                    mouse: { button }, Qt: { LeftButton: 1 }, trayIcon,
                    menuOpener: { children: { values: Array(count) } },
                    trayMenu: { openFor: () => openings++ }
                });
                const activates = button === 1 && !onlyMenu;
                assert.equal(activations, Number(activates));
                assert.equal(openings, Number(!activates && hasMenu && count > 0));
            }
assert.doesNotMatch(source, /toggleText|trayOpened|TrayBubble/,
    "No tray toggle or separate bubble remains");
assert.doesNotMatch(workspaces, /trayDrawer\.trayOpened/,
    "Workspaces no longer manage a tray drawer state");
await assert.rejects(access(new URL("../widgets/TrayBubble.qml", import.meta.url)),
    "Obsolete tray bubble should be removed");
console.log("Inline system tray checks passed");
