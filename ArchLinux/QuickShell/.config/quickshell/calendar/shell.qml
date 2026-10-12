import Quickshell
import Quickshell.Io
import "services"
import "ui"

ShellRoot {
    CalendarService {
        id: calendarBackend
    }

    CalendarWindow {
        id: calendarWindow
        calendarService: calendarBackend
    }

    IpcHandler {
        target: "calendar"

        function toggle(): bool {
            return calendarWindow.toggleWindow();
        }
    }
}
