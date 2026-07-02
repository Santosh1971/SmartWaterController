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
#include "WiFiScanner.h"

RTCManager   rtc;
FlowSensor   flowSensor;
RelayControl relay;
NVSManager   nvs;
Scheduler    scheduler;
BLEHandler   ble;
MQTTHandler  mqtt;
LEDManager   leds;
WiFiScanner  wifiScanner;

uint32_t lastStatusPublish = 0;
uint32_t lastWiFiCheck     = 0;

void IRAM_ATTR flowISR() {
    flowSensor.pulseISR();
    leds.flowPulse();
}

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

// Build cycles JSON from NVS
String buildCyclesJSON() {
    Cycle cycles[MAX_CYCLES];
    uint8_t count = nvs.loadCycles(cycles);
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    for (uint8_t i = 0; i < count; i++) {
        JsonObject o = arr.add<JsonObject>();
        o["id"]      = cycles[i].id;
        o["name"]    = cycles[i].name;
        o["sh"]      = cycles[i].startHour;
        o["sm"]      = cycles[i].startMinute;
        o["eh"]      = cycles[i].endHour;
        o["em"]      = cycles[i].endMinute;
        o["mode"]    = (int)cycles[i].mode;
        o["liters"]  = cycles[i].targetLiters;
        o["enabled"] = cycles[i].enabled;
    }
    String out; serializeJson(doc, out);
    return out;
}

void updateWiFiLED() {
    if (WiFi.status() != WL_CONNECTED)    leds.setWiFiState(WIFI_LED_SEARCHING);
    else if (!mqtt.isConnected())          leds.setWiFiState(WIFI_LED_WIFI_ONLY);
    else                                   leds.setWiFiState(WIFI_LED_FULL_OK);
}

// Sync RTC from NTP (IST = UTC+5:30 = 19800 seconds)
void syncNTP() {
    configTime(19800, 0, "in.pool.ntp.org", "asia.pool.ntp.org", "pool.ntp.org");
    Serial.println("[NTP] Syncing time...");
    struct tm timeinfo;
    bool ntpOk = false;
    for (int attempt = 0; attempt < 3 && !ntpOk; attempt++) {
        if (attempt > 0) { delay(2000); Serial.println("[NTP] Retrying..."); }
        ntpOk = getLocalTime(&timeinfo, 8000);
    }
    if (ntpOk) {
        // Write IST fields directly to DS3231 — avoids unix/UTC conversion issue
        rtc.syncFromTm(timeinfo);
        Serial.printf("[NTP] IST: %02d/%02d/%04d %02d:%02d:%02d\n",
            timeinfo.tm_mday, timeinfo.tm_mon+1, timeinfo.tm_year+1900,
            timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
    } else {
        Serial.println("[NTP] Sync failed — using existing RTC time");
    }
}

void setup() {
    Serial.begin(115200);
    Serial.println("[BOOT] SmartWaterController starting...");

    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
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

    // BLE Callbacks
    ble.onWiFiConfig = [](const char* ssid, const char* pass) {
        Serial.printf("[WiFi] Connecting to: %s\n", ssid);
        nvs.saveWiFi(ssid, pass);
        WiFi.disconnect();
        delay(100);
        WiFi.mode(WIFI_STA);
        WiFi.begin(ssid, pass);
        int attempts = 0;
        while (WiFi.status() != WL_CONNECTED && attempts < 30) {
            delay(500);
            Serial.print(".");
            attempts++;
        }
        if (WiFi.status() == WL_CONNECTED) {
            Serial.printf("\n[WiFi] Connected! IP: %s\n",
                WiFi.localIP().toString().c_str());
            syncNTP();
        } else {
            Serial.println("\n[WiFi] Connection failed!");
        }
    };

    ble.onMQTTConfig = [](const char* broker, uint16_t port,
                          const char* user, const char* pass) {
        nvs.saveMQTT(broker, port, user, pass);
        Serial.printf("[MQTT] Config saved: %s:%d\n", broker, port);
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

    ble.onWiFiScan = []() -> String {
        return wifiScanner.scanAsJson();
    };

    ble.begin();

    // WiFi
    char ssid[64], pass[64];
    if (nvs.loadWiFi(ssid, pass)) {
        Serial.printf("[WiFi] Connecting to saved: %s\n", ssid);
        WiFi.mode(WIFI_STA);
        WiFi.begin(ssid, pass);
    } else {
        Serial.println("[WiFi] No credentials — configure via BLE");
    }

    // Wait for WiFi and sync NTP
    int wifiWait = 0;
    while (WiFi.status() != WL_CONNECTED && wifiWait < 20) {
        delay(500);
        wifiWait++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("[WiFi] Connected — IP: %s\n",
            WiFi.localIP().toString().c_str());
        syncNTP();
        ble.stopAdvertising();
    }

    // MQTT callbacks
    mqtt.onCommand = [](const String& cmd, const JsonObject& payload) {
        Serial.printf("[MQTT] Command: %s\n", cmd.c_str());

        if (cmd == "stop_cycle")    scheduler.stopCycle();
        else if (cmd == "pause_cycle")   scheduler.pauseCycle();
        else if (cmd == "resume_cycle")  scheduler.resumeCycle();
        else if (cmd == "manual_on")     scheduler.startManual();
        else if (cmd == "manual_off")    scheduler.stopCycle(STOP_USER);
        else if (cmd == "manual_liters") scheduler.startManual(payload["liters"]);

        else if (cmd == "set_cycles") {
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
                cycles[count].targetLiters = (float)o["liters"];
                cycles[count].enabled      = o["enabled"];
                count++;
            }
            nvs.saveCycles(cycles, count);
            Serial.printf("[MQTT] Saved %d cycles\n", count);
            // Reload scheduler with new cycles
            scheduler.begin(&nvs, &rtc, &flowSensor, &relay);
            // Publish updated cycles back so app refreshes
            delay(100);
            mqtt.publishCycles(buildCyclesJSON());
        }

        else if (cmd == "get_cycles") {
            Serial.println("[MQTT] Sending cycles...");
            mqtt.publishCycles(buildCyclesJSON());
        }

        else if (cmd == "clear_history") {
            nvs.clearHistory();
        }

        else if (cmd == "get_history") {
            HistoryEntry entries[20];
            uint8_t count = nvs.getHistory(entries, 20);
            Serial.printf("[HISTORY] Fetched %d entries from NVS\n", count);
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
            Serial.printf("[HISTORY] Publishing %d bytes: %s\n", out.length(), out.c_str());
            bool ok = mqtt.publishHistory(out);
            Serial.printf("[HISTORY] Publish result: %s\n", ok ? "OK" : "FAILED");
        }
    };

    mqtt.begin();
    Serial.println("[BOOT] Setup complete");
}

void loop() {
    leds.loop();
    ble.loop();
    mqtt.loop();
    scheduler.loop();

    if (millis() - lastWiFiCheck >= 2000) {
        lastWiFiCheck = millis();
        updateWiFiLED();
    }

    if (millis() - lastStatusPublish >= STATUS_PUBLISH_INTERVAL_MS) {
        lastStatusPublish = millis();
        if (mqtt.isConnected()) {
            mqtt.publishStatus(buildStatusJSON());
            if (scheduler.getCurrentState().active)
                mqtt.publishActiveCycle(buildStatusJSON());
        }
    }
}
