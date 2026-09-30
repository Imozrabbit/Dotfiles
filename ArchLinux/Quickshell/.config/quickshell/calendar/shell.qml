import Quickshell
import Quickshell.Io
import "services"
import "ui"

ShellRoot {
    CalendarService {
        id: calendarService
    }

    CalendarWindow {
        id: calendarWindow
        calendarService: calendarService
    }

    IpcHandler {
        target: "calendar"

        function toggle(): bool {
            return calendarWindow.toggleWindow();
        }
    }
}
