#include "MQTTClient.h"

static MQTTHandler* _instance = nullptr;

static void mqttCallback(char* topic, byte* payload, unsigned int length) {
    if (_instance) {
        String msg;
        for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
        Serial.printf("[MQTT] Received on %s: %s\n", topic, msg.c_str());
        JsonDocument doc;
        if (deserializeJson(doc, msg) != DeserializationError::Ok) return;
        const char* cmd = doc["cmd"];
        if (cmd && _instance->onCommand)
            _instance->onCommand(String(cmd), doc.as<JsonObject>());
    }
}

void MQTTHandler::begin(const char* broker, uint16_t port, const char* user, const char* pass,
                         const String& deviceId) {
    _instance = this;
    strlcpy(_broker, broker, sizeof(_broker));
    _port = port;
    strlcpy(_user, user, sizeof(_user));
    strlcpy(_pass, pass, sizeof(_pass));

    // Topics built at runtime from the actual per-device ID now, instead
    // of a fixed compile-time "swc/SWC_001/..." every unit shared.
    _deviceId     = deviceId;
    _topicStatus  = "swc/" + _deviceId + "/status";
    _topicHistory = "swc/" + _deviceId + "/history";
    _topicActive  = "swc/" + _deviceId + "/active_cycle";
    _topicCycles  = "swc/" + _deviceId + "/cycles";
    _topicCmd     = "swc/" + _deviceId + "/command";

    _mqtt.setClient(_wifiClient);
    _mqtt.setServer(_broker, _port);
    _mqtt.setCallback(mqttCallback);
    _mqtt.setKeepAlive(30);
    _mqtt.setBufferSize(24576);  // room for a full month's history range payload (~150-200 entries)
    Serial.printf("[MQTT] Configured — %s:%d (device %s)\n", _broker, _port, _deviceId.c_str());
}

void MQTTHandler::loop() {
    if (WiFi.status() != WL_CONNECTED) return;
    if (!_mqtt.connected()) {
        uint32_t now = millis();
        if (now - _lastReconnectAttempt > 5000) {
            _lastReconnectAttempt = now;
            _reconnect();
        }
    } else {
        _mqtt.loop();
    }
}

void MQTTHandler::_reconnect() {
    String clientId = _deviceId + "_" + String(random(0xffff), HEX);
    Serial.printf("[MQTT] Connecting as %s...\n", clientId.c_str());
    bool ok = (strlen(_user) > 0)
              ? _mqtt.connect(clientId.c_str(), _user, _pass)
              : _mqtt.connect(clientId.c_str());
    if (ok) {
        Serial.println("[MQTT] Connected");
        _mqtt.subscribe(_topicCmd.c_str());
        Serial.printf("[MQTT] Subscribed to %s\n", _topicCmd.c_str());
    } else {
        Serial.printf("[MQTT] Failed rc=%d — retry in 5s\n", _mqtt.state());
    }
}

bool MQTTHandler::isConnected() { return _mqtt.connected(); }

void MQTTHandler::publishStatus(const String& json) {
    _mqtt.publish(_topicStatus.c_str(), json.c_str(), true);
}
void MQTTHandler::publishActiveCycle(const String& json) {
    _mqtt.publish(_topicActive.c_str(), json.c_str(), true);
}
void MQTTHandler::publishCycles(const String& json) {
    _mqtt.publish(_topicCycles.c_str(), json.c_str(), true);
}
bool MQTTHandler::publishHistory(const String& json) {
    return _mqtt.publish(_topicHistory.c_str(), json.c_str(), false);
}
