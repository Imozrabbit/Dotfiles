#include "calendar_json.h"
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <linux/fs.h>
#include <set>
#include <string>
#include <sys/syscall.h>
#include <system_error>
#include <thread>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

namespace {

struct FileStamp {
    fs::path path;
    fs::file_time_type modified;
    std::uintmax_t size = 0;

    bool operator==(const FileStamp &other) const {
        return path == other.path && modified == other.modified && size == other.size;
    }
};

std::string homePath(const char *suffix) {
    const char *home = std::getenv("HOME");
    return home ? std::string(home) + suffix : std::string();
}

fs::path defaultInputPath() {
    return homePath("/.local/share/calendars/edt_unistra");
}

fs::path defaultOutputPath() {
    const char *dataHome = std::getenv("XDG_DATA_HOME");
    if (dataHome && *dataHome != '\0')
        return fs::path(dataHome) / "calendars/edt_unistra.json";
    return fs::path(homePath("/.local/share/calendars/edt_unistra.json"));
}

bool collectFiles(const fs::path &inputPath, std::vector<FileStamp> &files,
                  std::string &error) {
    files.clear();
    std::error_code statusError;
    if (fs::is_regular_file(inputPath, statusError)) {
        if (inputPath.extension() != ".ics") {
            error = inputPath.string() + ": expected an .ics file";
            return false;
        }
        files.push_back({inputPath, fs::last_write_time(inputPath, statusError), fs::file_size(inputPath, statusError)});
        if (statusError)
            error = inputPath.string() + ": " + statusError.message();
        return error.empty();
    }
    fs::directory_iterator entries(inputPath, statusError);
    if (statusError) {
        error = statusError.message();
        return false;
    }

    const fs::directory_iterator end;
    while (entries != end) {
        const fs::directory_entry entry = *entries;
        statusError.clear();
        if (entry.is_regular_file(statusError) && entry.path().extension() == ".ics") {
            const std::uintmax_t size         = entry.file_size(statusError);
            const fs::file_time_type modified = entry.last_write_time(statusError);
            if (statusError) {
                error = entry.path().string() + ": " + statusError.message();
                return false;
            }
            files.push_back({entry.path(), modified, size});
        } else if (statusError) {
            error = entry.path().string() + ": " + statusError.message();
            return false;
        }

        entries.increment(statusError);
        if (statusError) {
            error = statusError.message();
            return false;
        }
    }

    std::sort(files.begin(), files.end(), [](const FileStamp &left, const FileStamp &right) {
        return left.path < right.path;
    });
    return true;
}

bool parseFiles(const std::vector<FileStamp> &files, std::vector<Event> &events,
                std::string &error) {
    events.clear();
    std::set<std::string> uids;
    for (const FileStamp &fileInfo : files) {
        std::ifstream file(fileInfo.path, std::ios::binary);
        if (!file) {
            error = fileInfo.path.string() + ": could not open file";
            return false;
        }

        const std::string source((std::istreambuf_iterator<char>(file)),
                                 std::istreambuf_iterator<char>());
        if (file.bad()) {
            error = fileInfo.path.string() + ": could not read file";
            return false;
        }

        const ParseResult parsed = parseCalendar(source);
        if (!parsed.error.empty()) {
            error = fileInfo.path.string() + ": " + parsed.error;
            return false;
        }
        for (Event event : parsed.events) {
            if (!uids.insert(event.uid).second) {
                error = "duplicate UID: " + event.uid;
                return false;
            }
            events.push_back(std::move(event));
        }
    }
    return true;
}

bool waitForStableFiles(const fs::path &directory, std::vector<FileStamp> &files,
                        std::string &error) {
    constexpr auto settleTime = std::chrono::seconds(2);
    constexpr auto timeout    = std::chrono::seconds(30);
    const auto deadline       = std::chrono::steady_clock::now() + timeout;

    while (std::chrono::steady_clock::now() < deadline) {
        std::vector<FileStamp> before;
        if (!collectFiles(directory, before, error)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        std::this_thread::sleep_for(settleTime);

        std::vector<FileStamp> after;
        if (collectFiles(directory, after, error)) {
            if (before == after) {
                files = std::move(after);
                return true;
            }
        }
    }

    error = "calendar directory did not stabilize during conversion";
    return false;
}

bool generate(const fs::path &inputPath, const fs::path &outputPath,
              const std::string &sourceId) {
    std::string error;
    for (int attempt = 0; attempt < 2; ++attempt) {
        std::vector<FileStamp> before;
        if (!waitForStableFiles(inputPath, before, error))
            break;

        std::vector<Event> events;
        if (!parseFiles(before, events, error))
            break;

        std::vector<FileStamp> after;
        if (!collectFiles(inputPath, after, error))
            break;
        if (before == after) {
            const std::string contents = serializeCalendar(std::move(events), sourceId);
            std::ifstream existing(outputPath, std::ios::binary);
            if (existing) {
                const std::string previous((std::istreambuf_iterator<char>(existing)), std::istreambuf_iterator<char>());
                if (!existing.bad() && previous == contents) {
                    std::cout << "Unchanged " << outputPath << "\n";
                    return true;
                }
            }
            if (!writeAtomicallyFile(outputPath.string(), contents, error))
                break;
            std::cout << "Generated " << outputPath << "\n";
            return true;
        }
        error = "calendar directory changed during conversion";
    }

    std::cerr << error << '\n';
    return false;
}

bool commitStagedOutput(const fs::path &staged, const fs::path &target,
                        const std::string &policy, std::string &error) {
    if (policy == "replace") {
        std::error_code filesystemError;
        fs::rename(staged, target, filesystemError);
        if (!filesystemError)
            return true;
        error = "could not replace output file: " + filesystemError.message();
        return false;
    }
    if (policy == "create") {
        const long status = syscall(SYS_renameat2, AT_FDCWD, staged.c_str(),
                                    AT_FDCWD, target.c_str(), RENAME_NOREPLACE);
        if (status == 0)
            return true;
        error = "could not create output file: " + std::string(std::strerror(errno));
        return false;
    }
    error = "output commit policy must be create or replace";
    return false;
}

} // namespace

int main(int argc, char **argv) {
    if (argc >= 2 && std::string(argv[1]) == "commit") {
        if (argc != 5) {
            std::cerr << "Usage: convert commit staged-json output-json [create|replace]\n";
            return 2;
        }
        std::string error;
        if (!commitStagedOutput(argv[2], argv[3], argv[4], error)) {
            std::cerr << error << '\n';
            return 1;
        }
        return 0;
    }
    if (argc > 4) {
        std::cerr << "Usage: convert [input-directory] [output-json] [source-id]\n";
        return 2;
    }

    const fs::path inputPath   = argc >= 2 ? fs::path(argv[1]) : defaultInputPath();
    const fs::path outputPath  = argc >= 3 ? fs::path(argv[2]) : defaultOutputPath();
    const std::string sourceId = argc >= 4 ? argv[3] : "edt_unistra";
    if (inputPath.empty() || outputPath.empty()) {
        std::cerr << "HOME is required for default calendar paths\n";
        return 2;
    }
    if (sourceId.empty()) {
        std::cerr << "source-id is required\n";
        return 2;
    }
    return generate(inputPath, outputPath, sourceId) ? 0 : 1;
}
