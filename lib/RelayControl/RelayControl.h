#pragma once
#include "Config.h"
#include <Arduino.h>

class RelayControl {
public:
    void begin(uint8_t pin);
    void on();
    void off();
    bool isOn();
    void testPulse(uint16_t durationMs = 5000);  // BLE relay test

private:
    uint8_t _pin;
    bool _state = false;
};
