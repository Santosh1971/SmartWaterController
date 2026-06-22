#pragma once
#include "Config.h"
#include <Arduino.h>
#include <RTClib.h>

class RTCManager {
public:
    bool begin();
    DateTime now();
    void syncFromUnix(uint32_t unixTime);
    bool isTimeSet();
    String getTimeString();   // "HH:MM"
    String getDateString();   // "DD/MM/YYYY"
    uint32_t getUnixTime();
private:
    RTC_DS3231 _rtc;
    bool _initialized = false;
};
