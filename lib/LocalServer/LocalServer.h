#pragma once
#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include "Config.h"

// Always-on local server — reachable over whichever interface is currently
// up (SoftAP, STA/home-WiFi, or both concurrently). Two jobs, both replacing
// what used to be two separate transports:
//
//   1. Provisioning (formerly BLE): wifi_config, mqtt_config, rtc_sync,
//      calibrate, relay_test, factory_reset, wifi_scan, device_info.
//      Same command names/fields BLE used, now sent as HTTP/WS JSON.
//
//   2. Operational control (formerly MQTT-only): stop_cycle, manual_on,
//      set_cycles, get_history_range, etc. — reaches the device locally
//      whether or not the cloud/MQTT path is currently up.
//
// onCommand returns a JSON String response (unlike the old MQTT-only
// handler, which was fire-and-forget) so provisioning commands like
// device_info/wifi_scan can reply synchronously over HTTP or WS.
class LocalServer {
public:
    void begin();
    void loop();

    bool isConnected();      // true if >=1 WS client attached
    int  stationCount();     // phones associated to our SoftAP, if it's up

    void publishStatus(const String& json);
    void publishActiveCycle(const String& json);
    void publishCycles(const String& json);
    bool publishHistory(const String& json);

    std::function<String(const String& cmd, const JsonObject& payload)> onCommand;

private:
    String _dispatch(const String& msg);   // shared by WS + HTTP POST paths
    void   _broadcast(const char* type, const String& json);

    AsyncWebServer _server{80};
    AsyncWebSocket _ws{"/ws"};

    String _lastStatus  = "{}";
    String _lastActive  = "{}";
    String _lastCycles  = "[]";
    String _lastHistory = "[]";
};
