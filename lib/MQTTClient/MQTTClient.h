#pragma once
#include "Config.h"
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "Config.h"

class MQTTHandler {
public:
    void begin();
    void loop();
    bool isConnected();

    void publishStatus(const String& json);
    void publishActiveCycle(const String& json);
    void publishCycles(const String& json);
    bool publishHistory(const String& json);

    // Command callbacks — wired from main.cpp
    std::function<void(const String& cmd, const JsonObject& payload)> onCommand;

private:
    void _reconnect();
    void _callback(char* topic, byte* payload, unsigned int length);

    WiFiClient   _wifiClient;
    PubSubClient _mqtt;
    uint32_t     _lastReconnectAttempt = 0;
};
