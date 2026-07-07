#pragma once

// ---------- Device ----------
#define DEVICE_ID           "SWC_001"
#define FIRMWARE_VERSION    "1.0.0"

// ---------- BLE ----------
#define BLE_DEVICE_NAME     "SmartWaterCtrl"
#define BLE_SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define BLE_CHAR_RX_UUID        "12345678-1234-1234-1234-123456789abd"
#define BLE_CHAR_TX_UUID        "12345678-1234-1234-1234-123456789abe"

// ---------- MQTT ----------
#define MQTT_BROKER         "87.76.191.157"  //"mqtt.grty.co.in"
#define MQTT_PORT           1883
#define MQTT_USER           ""
#define MQTT_PASS           ""
#define MQTT_TOPIC_STATUS   "swc/" DEVICE_ID "/status"
#define MQTT_TOPIC_HISTORY  "swc/" DEVICE_ID "/history"
#define MQTT_TOPIC_ACTIVE   "swc/" DEVICE_ID "/active_cycle"
#define MQTT_TOPIC_CYCLES   "swc/" DEVICE_ID "/cycles"
#define MQTT_TOPIC_CMD      "swc/" DEVICE_ID "/command"

// ---------- GPIO ----------
#define RELAY_PIN           18
#define FLOW_SENSOR_PIN     4
#define FLOW_SENSOR_LED_PIN 14
#define WIFI_LED_PIN        26
#define I2C_SDA             21
#define I2C_SCL             22

// ---------- Flow Sensor ----------
#define DEFAULT_PULSES_PER_LITER  450

// ---------- Scheduler ----------
#define MAX_CYCLES          4
#define NVS_NAMESPACE       "swc"
#define HISTORY_MAX_ENTRIES 200  // ~1 month at moderate use (5 events/day)

// ---------- Timing ----------
#define STATUS_PUBLISH_INTERVAL_MS   5000
#define SCHEDULE_CHECK_INTERVAL_MS   30000
#define STATE_SAVE_INTERVAL_MS       10000

// ---------- LED Blink Patterns ----------
// WiFi LED
#define WIFI_LED_CONNECTING_ON_MS    200   // fast blink = connecting
#define WIFI_LED_CONNECTING_OFF_MS   200
#define WIFI_LED_CONNECTED_ON_MS     1000  // slow blink = connected, no MQTT
#define WIFI_LED_CONNECTED_OFF_MS    1000
#define WIFI_LED_MQTT_ON_MS          50    // double blink = WiFi + MQTT ok
#define WIFI_LED_MQTT_OFF_MS         50

// Flow LED
#define FLOW_LED_PULSE_MS            50    // brief flash per pulse burst
