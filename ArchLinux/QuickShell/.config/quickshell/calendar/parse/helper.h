#ifndef HELPER_h
#define HELPER_h
#pragma once

#include <cstdio>
#include <string>
using namespace std;

struct Event {
    string descrption;
    string summary;
    // Start
    int startYear;
    int startMonth;
    int startDay;
    int startHour;
    int startMinute;
    // End
    int endYear;
    int endMonth;
    int endDay;
    int endHour;
    int endMinute;
};

string get_oneLine(FILE *file);

string extractKey(string s);
string extractValue(string s, int separatorPos);

#endif
