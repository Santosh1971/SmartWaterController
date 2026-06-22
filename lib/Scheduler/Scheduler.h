#pragma once
#include "Config.h"
#include <Arduino.h>
#include "NVSManager.h"
#include "RTCManager.h"
#include "FlowSensor.h"
#include "RelayControl.h"

enum CycleStopReason { STOP_COMPLETED, STOP_USER, STOP_PAUSED, STOP_POWER_RECOVERY };

class Scheduler {
public:
    void begin(NVSManager* nvs, RTCManager* rtc, FlowSensor* flow, RelayControl* relay);
    void loop();   // call every loop() iteration

    // Called from MQTT/BLE command handlers
    void startManual(float liters = 0);
    void stopCycle(CycleStopReason reason = STOP_USER);
    void pauseCycle();
    void resumeCycle();

    bool isRunning();
    bool isPaused();
    RunningState getCurrentState();

    // Called on boot for power recovery
    void checkPowerRecovery();

private:
    void _startCycle(Cycle& c, bool isRecovery = false);
    void _checkSchedule();
    void _checkCycleCompletion();
    void _saveProgress();

    NVSManager*   _nvs;
    RTCManager*   _rtc;
    FlowSensor*   _flow;
    RelayControl* _relay;

    Cycle        _cycles[MAX_CYCLES];
    uint8_t      _cycleCount = 0;
    RunningState _state;

    uint32_t _lastScheduleCheck = 0;
    uint32_t _lastStateSave     = 0;
    uint32_t _lastMinuteTick    = 0;
};
