#include "helper.h"
#include <cstdio>

int main(void) {
    Event event;
    FILE *calendarFile = fopen("/home/Zrabbit/.local/share/calendars/edt_unistra/00d08a14-063d-43cc-b8b1-25513be88a32@00d0.org.ics", "r");

    string buffer;

    if (!calendarFile) {
        perror("File opening failed");
        return 1;
    };

    buffer = get_oneLine(calendarFile);
    printf("%s\nKey: %s\nValue: %s\n", buffer.c_str(), extractKey(buffer).c_str(), extractValue(buffer, 5).c_str());
    fclose(calendarFile);
    return 0;

    if (ferror(calendarFile))
        puts("I/O error when reading");
    else if (feof(calendarFile)) {
        puts("End of file reached successfully");
    }
    fclose(calendarFile);
    return 0;
}
