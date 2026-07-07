#pragma once
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include "Config.h"

// Drop-in replacement for BLEHandler on the softap-provisioning branch.
// Same public callback interface as BLEHandler, so main.cpp barely changes —
// only the class name of the instantiated object differs.
//
// Provisioning flow:
//   1. On boot, if no WiFi creds saved yet, starts a SoftAP (device's own
//      hotspot) at SOFTAP_SSID / SOFTAP_PASSWORD (see Config.h additions below)
//   2. Phone joins that hotspot, browses to http://192.168.4.1/
//   3. App POSTs the same commands BLE used to accept, now as HTTP JSON
//   4. Once wifi_config succeeds and the device joins real WiFi, call
//      stopAdvertising() to tear down the AP (mirrors BLE's same-named call)

class SoftAPHandler {
public:
    void begin();
    void loop();
    bool isConnected();          // true if any HTTP client has hit us recently
    void sendResponse(const char* cmd, bool ok, const char* payload = "{}"); // unused for HTTP, kept for interface parity
    void stopAdvertising();      // tears down the SoftAP once real WiFi is up

    // Same callbacks as BLEHandler — wired identically from main.cpp
    std::function<void(const char* ssid, const char* pass)>    onWiFiConfig;
    std::function<void(const char* broker, uint16_t port,
                       const char* user, const char* pass)>    onMQTTConfig;
    std::function<void(uint32_t unixTime)>                     onRTCSync;
    std::function<void(uint32_t pulsesPerLiter)>               onCalibration;
    std::function<void()>                                       onRelayTest;
    std::function<void()>                                       onFactoryReset;
    std::function<String()>                                     onGetDeviceInfo;
    std::function<String()>                                     onWiFiScan;

private:
    void _handleWifiConfig();
    void _handleMqttConfig();
    void _handleRtcSync();
    void _handleCalibrate();
    void _handleRelayTest();
    void _handleFactoryReset();
    void _handleWifiScan();
    void _handleDeviceInfo();
    void _sendJson(bool ok, const String& payload = "{}");
    String _readBody();

    WebServer _server{80};
    bool      _apActive       = false;
    uint32_t  _lastClientSeen = 0;
};
