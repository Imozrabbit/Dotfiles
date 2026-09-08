#include "helper.h"
#include <cstdio>

string get_oneLine(FILE *file) {
    string buffer;
    int ch;
    while ((ch = fgetc(file)) != EOF) {
        if (ch == '\n') {
            break;
        }
        buffer += (char)ch;
    }
    return buffer;
}

string extractKey(string s) {
    int separatorPos = s.find_first_of(':', 0);
    return s.substr(0, separatorPos);
}

string extractValue(string s, int separatorPos) {
    return s.substr(separatorPos + 1);
}
