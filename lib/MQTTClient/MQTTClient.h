#pragma once
#include "Config.h"
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "Config.h"

class MQTTHandler {
public:
    // broker/user/pass are copied internally, so caller's buffers can go out of scope after this call
    void begin(const char* broker, uint16_t port, const char* user, const char* pass);
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

    char     _broker[128] = {0};
    uint16_t _port        = 1883;
    char     _user[64]    = {0};
    char     _pass[64]    = {0};
};
