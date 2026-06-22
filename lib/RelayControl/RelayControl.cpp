#include "RelayControl.h"

void RelayControl::begin(uint8_t pin) {
    _pin = pin;
    pinMode(_pin, OUTPUT);
    digitalWrite(_pin, LOW);
    _state = false;
    Serial.printf("[RELAY] Initialized on pin %d\n", _pin);
}

void RelayControl::on() {
    if (!_state) {
        digitalWrite(_pin, HIGH);
        _state = true;
        Serial.println("[RELAY] ON");
    }
}

void RelayControl::off() {
    if (_state) {
        digitalWrite(_pin, LOW);
        _state = false;
        Serial.println("[RELAY] OFF");
    }
}

bool RelayControl::isOn() {
    return _state;
}

void RelayControl::testPulse(uint16_t durationMs) {
    Serial.printf("[RELAY] Test pulse %dms\n", durationMs);
    on();
    delay(durationMs);
    off();
}
