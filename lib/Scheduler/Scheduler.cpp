#include "Scheduler.h"

void Scheduler::begin(NVSManager* nvs, RTCManager* rtc,
                      FlowSensor* flow, RelayControl* relay) {
    _nvs   = nvs;
    _rtc   = rtc;
    _flow  = flow;
    _relay = relay;
    _cycleCount = _nvs->loadCycles(_cycles);
    memset(&_state, 0, sizeof(_state));
    Serial.printf("[SCHED] Ready — %d cycles loaded\n", _cycleCount);
}

void Scheduler::checkPowerRecovery() {
    RunningState saved;
    if (!_nvs->loadRunningState(saved)) return;
    Serial.println("[SCHED] Power recovery — checking interrupted cycle...");

    if (!_rtc->isTimeSet()) {
        Serial.println("[SCHED] RTC not set — skipping recovery");
        _nvs->clearRunningState();
        return;
    }

    // Find the cycle
    Cycle* c = nullptr;
    for (uint8_t i = 0; i < _cycleCount; i++) {
        if (_cycles[i].id == saved.cycleId) { c = &_cycles[i]; break; }
    }
    if (!c) { _nvs->clearRunningState(); return; }

    DateTime now   = _rtc->now();
    uint8_t  nowH  = now.hour();
    uint8_t  nowM  = now.minute();
    uint16_t nowMins   = nowH * 60 + nowM;
    uint16_t startMins = c->startHour * 60 + c->startMinute;
    uint16_t endMins   = c->endHour   * 60 + c->endMinute;

    float remaining = 0;
    if (c->mode == LITER_BASED || c->mode == TIME_WINDOW_LITER)
        remaining = c->targetLiters - saved.litersDelivered;

    bool withinWindow = (c->mode == TIME_BASED || c->mode == TIME_WINDOW_LITER)
                        ? (nowMins >= startMins && nowMins < endMins)
                        : true;

    if (withinWindow && remaining > 0) {
        Serial.printf("[SCHED] Resuming cycle %d — %.1fL remaining\n",
                      c->id, remaining);
        _state = saved;
        _state.active = true;
        _state.paused = false;
        _flow->resetCount();  // count fresh from resume point
        _relay->on();
    } else if (!withinWindow && remaining > 0) {
        // Daily quota not met — run immediately
        Serial.printf("[SCHED] Window passed but %.1fL undelivered — running now\n",
                      remaining);
        _state = saved;
        _state.active = true;
        _state.paused = false;
        _flow->resetCount();
        _relay->on();
    } else {
        Serial.println("[SCHED] Recovery: quota already met");
        _nvs->clearRunningState();
    }
}

void Scheduler::loop() {
    uint32_t now = millis();

    // Schedule check
    if (!_state.active && now - _lastScheduleCheck >= SCHEDULE_CHECK_INTERVAL_MS) {
        _lastScheduleCheck = now;
        _checkSchedule();
    }

    // Cycle completion check
    if (_state.active && !_state.paused) {
        _checkCycleCompletion();
    }

    // Periodic state save while running
    if (_state.active && now - _lastStateSave >= STATE_SAVE_INTERVAL_MS) {
        _lastStateSave = now;
        _state.litersDelivered = _flow->getLitersDelivered();
        _nvs->saveRunningState(_state);
    }
}

void Scheduler::_checkSchedule() {
    if (!_rtc->isTimeSet()) return;
    DateTime now  = _rtc->now();
    uint8_t  nowH = now.hour();
    uint8_t  nowM = now.minute();

    for (uint8_t i = 0; i < _cycleCount; i++) {
        Cycle& c = _cycles[i];
        if (!c.enabled) continue;
        if (c.startHour == nowH && c.startMinute == nowM) {
            Serial.printf("[SCHED] Triggering cycle %d at %02d:%02d\n",
                          c.id, nowH, nowM);
            _startCycle(c);
            return;
        }
    }
}

void Scheduler::_startCycle(Cycle& c, bool isRecovery) {
    _flow->resetCount();
    _state.active          = true;
    _state.paused          = false;
    _state.cycleId         = c.id;
    _state.litersDelivered = 0;
    _state.startUnix       = _rtc->getUnixTime();
    strlcpy(_state.startedBy, "auto", sizeof(_state.startedBy));
    _relay->on();
    _nvs->saveRunningState(_state);
    Serial.printf("[SCHED] Cycle %d started (mode=%d, target=%.1fL)\n",
                  c.id, c.mode, c.targetLiters);
}

void Scheduler::_checkCycleCompletion() {
    // Find active cycle config
    Cycle* c = nullptr;
    for (uint8_t i = 0; i < _cycleCount; i++) {
        if (_cycles[i].id == _state.cycleId) { c = &_cycles[i]; break; }
    }

    float delivered = _flow->getLitersDelivered() + _state.litersDelivered;
    bool done = false;

    if (c) {
        DateTime now   = _rtc->now();
        uint16_t nowM  = now.hour() * 60 + now.minute();
        uint16_t endM  = c->endHour * 60 + c->endMinute;

        if (c->mode == LITER_BASED && delivered >= c->targetLiters)      done = true;
        if (c->mode == TIME_BASED  && nowM >= endM)                       done = true;
        if (c->mode == TIME_WINDOW_LITER &&
            (delivered >= c->targetLiters || nowM >= endM))               done = true;

        // Manual liter mode (cycleId==255)
        if (_state.cycleId == 255 && delivered >= c->targetLiters)       done = true;
    }

    if (done) stopCycle(STOP_COMPLETED);
}

void Scheduler::stopCycle(CycleStopReason reason) {
    if (!_state.active) return;
    _relay->off();
    float delivered = _flow->getLitersDelivered() + _state.litersDelivered;

    HistoryEntry h;
    h.timestamp       = _rtc->getUnixTime();
    h.cycleId         = _state.cycleId;
    h.litersDelivered = delivered;
    h.durationSeconds = (uint16_t)(h.timestamp - _state.startUnix);

    // Find cycle name
    for (uint8_t i = 0; i < _cycleCount; i++) {
        if (_cycles[i].id == _state.cycleId) {
            strlcpy(h.cycleName, _cycles[i].name, 32);
            h.mode = _cycles[i].mode;
            break;
        }
    }

    const char* statusStr[] = {"completed","stopped","paused","recovered"};
    strlcpy(h.status, statusStr[(int)reason], 16);

    _nvs->addHistoryEntry(h);
    _nvs->clearRunningState();

    memset(&_state, 0, sizeof(_state));
    _flow->resetCount();

    Serial.printf("[SCHED] Cycle stopped — reason=%d, delivered=%.1fL\n",
                  (int)reason, delivered);
}

void Scheduler::pauseCycle() {
    if (!_state.active || _state.paused) return;
    _relay->off();
    _state.paused          = true;
    _state.litersDelivered += _flow->getLitersDelivered();
    _flow->resetCount();
    _nvs->saveRunningState(_state);
    Serial.println("[SCHED] Cycle paused");
}

void Scheduler::resumeCycle() {
    if (!_state.active || !_state.paused) return;
    _state.paused = false;
    _flow->resetCount();
    _relay->on();
    _nvs->saveRunningState(_state);
    Serial.println("[SCHED] Cycle resumed");
}

void Scheduler::startManual(float liters) {
    if (_state.active) stopCycle(STOP_USER);
    _flow->resetCount();
    _state.active          = true;
    _state.paused          = false;
    _state.cycleId         = 255;  // manual sentinel
    _state.litersDelivered = 0;
    _state.startUnix       = _rtc->getUnixTime();
    strlcpy(_state.startedBy, "manual", sizeof(_state.startedBy));

    // Store target in a temporary cycle slot for completion check
    static Cycle manualCycle;
    manualCycle.id           = 255;
    manualCycle.targetLiters = liters;
    manualCycle.mode         = (liters > 0) ? LITER_BASED : TIME_BASED;
    manualCycle.enabled      = true;

    _relay->on();
    _nvs->saveRunningState(_state);
    Serial.printf("[SCHED] Manual start — %.1fL target\n", liters);
}

bool Scheduler::isRunning() { return _state.active && !_state.paused; }
bool Scheduler::isPaused()  { return _state.active && _state.paused; }
RunningState Scheduler::getCurrentState() { return _state; }
