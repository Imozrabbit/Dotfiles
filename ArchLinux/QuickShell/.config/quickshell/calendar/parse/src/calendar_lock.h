#pragma once
#include <fcntl.h>
#include <filesystem>
#include <string>
#include <sys/file.h>
#include <unistd.h>

class CalendarLock {
  public:
    explicit CalendarLock(const std::filesystem::path &directory, std::string &error) {
        descriptor = open((directory / ".calendar-sync.lock").c_str(), O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (descriptor < 0 || flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
            if (descriptor >= 0)
                close(descriptor);
            descriptor = -1;
            error      = "calendar is busy";
        }
    }
    ~CalendarLock() {
        if (descriptor >= 0)
            close(descriptor);
    }
    CalendarLock(const CalendarLock &)            = delete;
    CalendarLock &operator=(const CalendarLock &) = delete;
    bool acquired() const { return descriptor >= 0; }

  private:
    int descriptor = -1;
};
