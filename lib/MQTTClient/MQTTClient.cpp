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

void MQTTHandler::begin() {
    _instance = this;
    _mqtt.setClient(_wifiClient);
    _mqtt.setServer(MQTT_BROKER, MQTT_PORT);
    _mqtt.setCallback(mqttCallback);
    _mqtt.setKeepAlive(30);
    _mqtt.setBufferSize(24576);  // room for a full month's history range payload (~150-200 entries)
    Serial.printf("[MQTT] Configured — %s:%d\n", MQTT_BROKER, MQTT_PORT);
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
    String clientId = String(DEVICE_ID) + "_" + String(random(0xffff), HEX);
    Serial.printf("[MQTT] Connecting as %s...\n", clientId.c_str());

    bool ok = (strlen(MQTT_USER) > 0)
              ? _mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)
              : _mqtt.connect(clientId.c_str());

    if (ok) {
        Serial.println("[MQTT] Connected");
        _mqtt.subscribe(MQTT_TOPIC_CMD);
        Serial.printf("[MQTT] Subscribed to %s\n", MQTT_TOPIC_CMD);
    } else {
        Serial.printf("[MQTT] Failed rc=%d — retry in 5s\n", _mqtt.state());
    }
}

bool MQTTHandler::isConnected() { return _mqtt.connected(); }

void MQTTHandler::publishStatus(const String& json) {
    _mqtt.publish(MQTT_TOPIC_STATUS, json.c_str(), true);
}

void MQTTHandler::publishActiveCycle(const String& json) {
    _mqtt.publish(MQTT_TOPIC_ACTIVE, json.c_str(), true);
}

void MQTTHandler::publishCycles(const String& json) {
    _mqtt.publish(MQTT_TOPIC_CYCLES, json.c_str(), true);
}

bool MQTTHandler::publishHistory(const String& json) {
    return _mqtt.publish(MQTT_TOPIC_HISTORY, json.c_str(), false);
}
