pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "toasts" as Toasts
import "images" as Images
import "../common/Theme.js" as Theme

Scope {
    id: root
    required property var service
    required property var settings
    readonly property var windows: Array.from(surfaces.instances)
    readonly property var themeColors: Theme.resolveColors(root.settings.colors)
    signal interactionRequested(var surface)

    Variants {
        id: surfaces
        model: root.service.screens
        Toasts.Surface {
            id: surface
            required property ShellScreen modelData
            targetScreen: modelData
            active: true
            entries: root.service.toasts.filter(entry => entry.screenName === surface.modelData.name)
            requestedWidth: root.settings.toast.width
            requestedHeight: root.settings.toast.height
            themeColors: root.themeColors
            captureActive: capture.job !== null
            onDismissRequested: (entryId, revision) => root.service.dismiss(entryId, revision)
            onActionRequested: (entryId, action, revision) => root.service.invoke(entryId, revision, action)
            onReplyRequested: (entryId, text, revision) => root.service.reply(entryId, revision, text)
            onCopyRequested: (entryId, revision) => root.service.copy(entryId, revision)
            onInteractionChanged: (entryId, hovered, focused) => root.service.interact(entryId, hovered, focused)
            onInteractionRequested: root.interactionRequested(surface)

            Images.Capture {
                id: capture
                x: -width
                job: root.service.captureJob?.screenName === surface.modelData.name ? root.service.captureJob : null
                onFinished: (token, success) => root.service.captureFinished(token, success)
            }
        }
    }
}
