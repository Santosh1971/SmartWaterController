#include "SoftAPHandler.h"

void SoftAPHandler::begin() {
    WiFi.mode(WIFI_AP_STA);  // AP for provisioning + STA ready for real WiFi once configured
    WiFi.softAP(SOFTAP_SSID, SOFTAP_PASSWORD);
    _apActive = true;
    Serial.printf("[SoftAP] Started '%s' — IP: %s\n",
        SOFTAP_SSID, WiFi.softAPIP().toString().c_str());

    _server.on("/wifi_config",   HTTP_POST, [this]() { _handleWifiConfig(); });
    _server.on("/mqtt_config",   HTTP_POST, [this]() { _handleMqttConfig(); });
    _server.on("/rtc_sync",      HTTP_POST, [this]() { _handleRtcSync(); });
    _server.on("/calibrate",     HTTP_POST, [this]() { _handleCalibrate(); });
    _server.on("/relay_test",    HTTP_POST, [this]() { _handleRelayTest(); });
    _server.on("/factory_reset", HTTP_POST, [this]() { _handleFactoryReset(); });
    _server.on("/wifi_scan",     HTTP_GET,  [this]() { _handleWifiScan(); });
    _server.on("/device_info",   HTTP_GET,  [this]() { _handleDeviceInfo(); });

    _server.begin();
    Serial.println("[SoftAP] HTTP server started on port 80");
}

void SoftAPHandler::loop() {
    _server.handleClient();
}

bool SoftAPHandler::isConnected() {
    // No persistent connection concept in HTTP like BLE's — treat "connected"
    // as "a client hit us in the last 10s", useful for UI purposes only.
    return (millis() - _lastClientSeen) < 10000;
}

void SoftAPHandler::stopAdvertising() {
    if (_apActive) {
        WiFi.softAPdisconnect(true);
        _apActive = false;
        Serial.println("[SoftAP] AP stopped — WiFi/MQTT priority mode");
    }
}

void SoftAPHandler::sendResponse(const char*, bool, const char*) {
    // Not used over HTTP — each handler replies directly via _sendJson().
    // Kept only so main.cpp code that might call this doesn't need branching.
}

String SoftAPHandler::_readBody() {
    _lastClientSeen = millis();
    return _server.hasArg("plain") ? _server.arg("plain") : "";
}

void SoftAPHandler::_sendJson(bool ok, const String& payload) {
    JsonDocument doc;
    doc["ok"] = ok;
    doc["payload"] = serialized(payload);
    String out; serializeJson(doc, out);
    _server.send(ok ? 200 : 400, "application/json", out);
}

void SoftAPHandler::_handleWifiConfig() {
    JsonDocument doc;
    if (deserializeJson(doc, _readBody()) != DeserializationError::Ok) {
        _sendJson(false, "{\"msg\":\"invalid JSON\"}"); return;
    }
    const char* ssid = doc["ssid"] | "";
    const char* pass = doc["pass"] | "";
    if (onWiFiConfig) onWiFiConfig(ssid, pass);
    _sendJson(true);
}

void SoftAPHandler::_handleMqttConfig() {
    JsonDocument doc;
    if (deserializeJson(doc, _readBody()) != DeserializationError::Ok) {
        _sendJson(false, "{\"msg\":\"invalid JSON\"}"); return;
    }
    const char* broker = doc["broker"] | "";
    uint16_t port       = doc["port"] | 1883;
    const char* user    = doc["user"] | "";
    const char* pass    = doc["pass"] | "";
    if (onMQTTConfig) onMQTTConfig(broker, port, user, pass);
    _sendJson(true);
}

void SoftAPHandler::_handleRtcSync() {
    JsonDocument doc;
    if (deserializeJson(doc, _readBody()) != DeserializationError::Ok) {
        _sendJson(false, "{\"msg\":\"invalid JSON\"}"); return;
    }
    if (onRTCSync) onRTCSync((uint32_t)doc["unix"]);
    _sendJson(true);
}

void SoftAPHandler::_handleCalibrate() {
    JsonDocument doc;
    if (deserializeJson(doc, _readBody()) != DeserializationError::Ok) {
        _sendJson(false, "{\"msg\":\"invalid JSON\"}"); return;
    }
    if (onCalibration) onCalibration((uint32_t)doc["ppl"]);
    _sendJson(true);
}

void SoftAPHandler::_handleRelayTest() {
    _readBody();
    if (onRelayTest) onRelayTest();
    _sendJson(true);
}

void SoftAPHandler::_handleFactoryReset() {
    _readBody();
    _sendJson(true);
    delay(300);
    if (onFactoryReset) onFactoryReset();
}

void SoftAPHandler::_handleWifiScan() {
    _lastClientSeen = millis();
    String result = onWiFiScan ? onWiFiScan() : "[]";
    _server.send(200, "application/json", result);
}

void SoftAPHandler::_handleDeviceInfo() {
    _lastClientSeen = millis();
    String info = onGetDeviceInfo ? onGetDeviceInfo() : "{}";
    _server.send(200, "application/json", info);
}
