#include <Arduino.h>
#include <ArduinoJson.h>
#include <nvs_flash.h>
#include "Config.h"
#include "RTCManager.h"
#include "FlowSensor.h"
#include "RelayControl.h"
#include "NVSManager.h"
#include "Scheduler.h"
#include "BLEHandler.h"
#include "MQTTClient.h"
#include "LEDManager.h"

// ---------- Global instances ----------
RTCManager   rtc;
FlowSensor   flowSensor;
RelayControl relay;
NVSManager   nvs;
Scheduler    scheduler;
BLEHandler   ble;
MQTTHandler  mqtt;
LEDManager   leds;

uint32_t lastStatusPublish = 0;
uint32_t lastWiFiCheck     = 0;

// ---------- ISR ----------
void IRAM_ATTR flowISR() {
    flowSensor.pulseISR();
    leds.flowPulse();        // LED flashes on every pulse burst
}

// ---------- Status JSON ----------
String buildStatusJSON() {
    JsonDocument doc;
    doc["device_id"]        = DEVICE_ID;
    doc["firmware"]         = FIRMWARE_VERSION;
    doc["pump_on"]          = relay.isOn();
    doc["rtc_time"]         = rtc.getTimeString();
    doc["rtc_date"]         = rtc.getDateString();
    doc["rtc_set"]          = rtc.isTimeSet();
    doc["wifi_rssi"]        = WiFi.RSSI();
    doc["wifi_connected"]   = (WiFi.status() == WL_CONNECTED);
    doc["mqtt_connected"]   = mqtt.isConnected();
    RunningState s          = scheduler.getCurrentState();
    doc["cycle_active"]     = s.active;
    doc["cycle_paused"]     = s.paused;
    doc["cycle_id"]         = s.cycleId;
    doc["liters_delivered"] = s.litersDelivered;
    doc["started_by"]       = s.startedBy;
    String out; serializeJson(doc, out);
    return out;
}

// ---------- WiFi LED updater ----------
void updateWiFiLED() {
    if (WiFi.status() != WL_CONNECTED) {
        leds.setWiFiState(WIFI_LED_SEARCHING);
    } else if (!mqtt.isConnected()) {
        leds.setWiFiState(WIFI_LED_WIFI_ONLY);
    } else {
        leds.setWiFiState(WIFI_LED_FULL_OK);
    }
}

// ---------- Setup ----------
void setup() {
    Serial.begin(115200);
    Serial.println("[BOOT] SmartWaterController starting...");

    // Fix NVS if partition was never initialized
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        Serial.println("[NVS] Erasing and reinitializing...");
        nvs_flash_erase();
        nvs_flash_init();
    }

    leds.begin();
    leds.setWiFiState(WIFI_LED_SEARCHING);

    nvs.begin();
    rtc.begin();
    relay.begin(RELAY_PIN);
    flowSensor.begin(FLOW_SENSOR_PIN);
    flowSensor.setCalibration(nvs.loadCalibration());
    attachInterrupt(digitalPinToInterrupt(FLOW_SENSOR_PIN), flowISR, RISING);

    scheduler.begin(&nvs, &rtc, &flowSensor, &relay);
    scheduler.checkPowerRecovery();

    // ---------- BLE callbacks ----------
    ble.onWiFiConfig = [](const char* ssid, const char* pass) {
        nvs.saveWiFi(ssid, pass);
        WiFi.begin(ssid, pass);
        Serial.printf("[WiFi] Connecting to %s\n", ssid);
    };
    ble.onMQTTConfig = [](const char* broker, uint16_t port,
                          const char* user, const char* pass) {
        nvs.saveMQTT(broker, port, user, pass);
    };
    ble.onRTCSync = [](uint32_t unixTime) {
        rtc.syncFromUnix(unixTime);
    };
    ble.onCalibration = [](uint32_t ppl) {
        flowSensor.setCalibration(ppl);
        nvs.saveCalibration(ppl);
    };
    ble.onRelayTest = []() {
        relay.testPulse(5000);
    };
    ble.onFactoryReset = []() {
        nvs.factoryReset();
        ESP.restart();
    };
    ble.onGetDeviceInfo = []() -> String {
        return buildStatusJSON();
    };
    ble.begin();

    // ---------- WiFi ----------
    char ssid[64], pass[64];
    if (nvs.loadWiFi(ssid, pass)) {
        Serial.printf("[WiFi] Connecting to %s\n", ssid);
        WiFi.begin(ssid, pass);
    } else {
        Serial.println("[WiFi] No credentials — configure via BLE");
    }

    // ---------- MQTT callbacks ----------
    mqtt.onCommand = [](const String& cmd, const JsonObject& payload) {
        if      (cmd == "stop_cycle")    scheduler.stopCycle();
        else if (cmd == "pause_cycle")   scheduler.pauseCycle();
        else if (cmd == "resume_cycle")  scheduler.resumeCycle();
        else if (cmd == "manual_on")     scheduler.startManual();
        else if (cmd == "manual_off")    scheduler.stopCycle(STOP_USER);
        else if (cmd == "manual_liters") scheduler.startManual(payload["liters"]);
        else if (cmd == "set_cycles") {
            // Parse and save cycles from payload
            JsonArray arr = payload["cycles"].as<JsonArray>();
            Cycle cycles[MAX_CYCLES];
            uint8_t count = 0;
            for (JsonObject o : arr) {
                if (count >= MAX_CYCLES) break;
                cycles[count].id           = o["id"];
                strlcpy(cycles[count].name, o["name"] | "", 32);
                cycles[count].startHour    = o["sh"];
                cycles[count].startMinute  = o["sm"];
                cycles[count].endHour      = o["eh"];
                cycles[count].endMinute    = o["em"];
                cycles[count].mode         = (OperationMode)(int)o["mode"];
                cycles[count].targetLiters = o["liters"];
                cycles[count].enabled      = o["enabled"];
                count++;
            }
            nvs.saveCycles(cycles, count);
        }
        else if (cmd == "get_history") {
            HistoryEntry entries[20];
            uint8_t count = nvs.getHistory(entries, 20);
            JsonDocument doc;
            JsonArray arr = doc.to<JsonArray>();
            for (uint8_t i = 0; i < count; i++) {
                JsonObject o = arr.add<JsonObject>();
                o["ts"]     = entries[i].timestamp;
                o["cid"]    = entries[i].cycleId;
                o["name"]   = entries[i].cycleName;
                o["mode"]   = (int)entries[i].mode;
                o["liters"] = entries[i].litersDelivered;
                o["dur"]    = entries[i].durationSeconds;
                o["status"] = entries[i].status;
            }
            String out; serializeJson(doc, out);
            mqtt.publishHistory(out);
        }
    };
    mqtt.begin();

    Serial.println("[BOOT] Setup complete");
}

// ---------- Loop ----------
void loop() {
    leds.loop();
    ble.loop();
    mqtt.loop();
    scheduler.loop();

    // Update WiFi LED state every 2 seconds
    if (millis() - lastWiFiCheck >= 2000) {
        lastWiFiCheck = millis();
        updateWiFiLED();
    }

    // Publish status every 5 seconds
    if (millis() - lastStatusPublish >= STATUS_PUBLISH_INTERVAL_MS) {
        lastStatusPublish = millis();
        if (mqtt.isConnected()) {
            mqtt.publishStatus(buildStatusJSON());
            if (scheduler.getCurrentState().active) {
                mqtt.publishActiveCycle(buildStatusJSON());
            }
        }
    }
}
