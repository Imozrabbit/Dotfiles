import Quickshell
import Quickshell.Io
import "ui"
import "notifications" as Notifications
import "notifications/native" as NativeService

ShellRoot {
    Config {
        id: configuration
    }

    NativeService.Service {
        id: notifications
        screens: Quickshell.screens
        focusedScreenName: controlCenter.focusedScreenName()
    }

    NativeService.Controls {
        service: notifications
    }

    Notifications.Host {
        id: toastHost
        service: notifications
        settings: configuration.settings
        onInteractionRequested: surface => controlCenter.focusNotificationSurface(surface)
    }

    ControlCenterWindow {
        id: controlCenter
        settings: configuration.settings
        notificationController: notifications
        notificationWindows: toastHost.windows
    }

    IpcHandler {
        target: "command-center"

        function toggle(): bool {
            return controlCenter.toggleWindow();
        }

        function close(): bool {
            return controlCenter.closeWindow();
        }
    }
}
