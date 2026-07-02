#include "WiFiScanner.h"
#include <ArduinoJson.h>

String WiFiScanner::scanAsJson() {
    Serial.println("[WiFi] Scanning networks...");
    int found = WiFi.scanNetworks();
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    if (found > 0) {
        for (int i = 0; i < min(found, 15); i++) {
            JsonObject o = arr.add<JsonObject>();
            o["ssid"] = WiFi.SSID(i);
            o["rssi"] = WiFi.RSSI(i);
            o["open"] = (WiFi.encryptionType(i) == WIFI_AUTH_OPEN);
        }
    }
    WiFi.scanDelete();
    Serial.printf("[WiFi] Scan found %d networks\n", found);
    String out; serializeJson(doc, out);
    return out;
}
