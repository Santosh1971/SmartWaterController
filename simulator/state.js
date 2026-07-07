// state.js — mirrors the real field names in main.cpp's buildStatusJSON()
// and the SoftAPHandler command set, so the Flutter app's parsing code
// works unchanged against real hardware later.

const PULSES_PER_LITER = 450.0; // matches DEFAULT_PULSES_PER_LITER in Config.h

const state = {
  deviceId: 'SWC_001',
  firmware: '1.0.0',
  pumpOn: false,
  rtcSet: true,
  wifiConnected: false,   // false while in SoftAP-only provisioning state
  mqttConnected: false,
  cycle: { active: false, paused: false, cycleId: 255, litersDelivered: 0, startedBy: 'none' },
  literPerMin: 0,         // operator-set simulated flow rate (dashboard control only)
  savedWifi: null,        // {ssid, pass} — set via /wifi_config
  savedMqtt: null,        // {broker, port, user, pass} — set via /mqtt_config
  calibrationPPL: PULSES_PER_LITER,
  clock: new Date(),
};

function tick() {
  state.clock = new Date();
  if (state.pumpOn && state.literPerMin > 0) {
    state.cycle.active = true;
    state.cycle.litersDelivered += state.literPerMin / 60;
  }
}

function startFlowLoop(onTick) {
  setInterval(() => { tick(); onTick(); }, 1000);
}

function pad(n) { return n < 10 ? '0' + n : '' + n; }

function buildStatusJSON() {
  const c = state.clock;
  return {
    device_id: state.deviceId,
    firmware: state.firmware,
    pump_on: state.pumpOn,
    rtc_time: `${pad(c.getHours())}:${pad(c.getMinutes())}:${pad(c.getSeconds())}`,
    rtc_date: `${pad(c.getDate())}/${pad(c.getMonth() + 1)}/${c.getFullYear()}`,
    rtc_set: state.rtcSet,
    wifi_rssi: state.wifiConnected ? -55 : 0,
    wifi_connected: state.wifiConnected,
    mqtt_connected: state.mqttConnected,
    cycle_active: state.cycle.active,
    cycle_paused: state.cycle.paused,
    cycle_id: state.cycle.cycleId,
    liters_delivered: Number(state.cycle.litersDelivered.toFixed(3)),
    started_by: state.cycle.startedBy,
  };
}

function setWifiConfig(ssid, pass) {
  state.savedWifi = { ssid, pass };
  // simulate the real connect delay + outcome, same as firmware's onWiFiConfig
  setTimeout(() => { state.wifiConnected = true; }, 2000);
  return true;
}

function setMqttConfig(broker, port, user, pass) {
  state.savedMqtt = { broker, port, user, pass };
  setTimeout(() => { state.mqttConnected = true; }, 1000);
  return true;
}

function setRtcSync(unixSeconds) {
  state.clock = new Date(unixSeconds * 1000);
  state.rtcSet = true;
  return true;
}

function setCalibration(ppl) {
  state.calibrationPPL = ppl;
  return true;
}

function relayTest() {
  state.pumpOn = true;
  setTimeout(() => { state.pumpOn = false; }, 5000); // mirrors relay.testPulse(5000) in firmware
  return true;
}

function factoryReset() {
  state.savedWifi = null;
  state.savedMqtt = null;
  state.wifiConnected = false;
  state.mqttConnected = false;
  state.cycle = { active: false, paused: false, cycleId: 255, litersDelivered: 0, startedBy: 'none' };
  return true;
}

function wifiScan() {
  // fake nearby networks — matches WiFiScanner.cpp's o["ssid"]=WiFi.SSID(i) shape
  return [
    { ssid: 'HomeWiFi_5G', rssi: -42 },
    { ssid: 'HomeWiFi_2G', rssi: -48 },
    { ssid: 'Neighbour_Router', rssi: -71 },
  ];
}

// Dashboard-only manual controls (not part of the real device API)
function setRelay(on) { state.pumpOn = on; return buildStatusJSON(); }
function setFlowRate(literPerMin) { state.literPerMin = Math.max(0, Number(literPerMin) || 0); return buildStatusJSON(); }
function resetTotals() { state.cycle.litersDelivered = 0; return buildStatusJSON(); }

module.exports = {
  state, buildStatusJSON, startFlowLoop,
  setWifiConfig, setMqttConfig, setRtcSync, setCalibration, relayTest, factoryReset, wifiScan,
  setRelay, setFlowRate, resetTotals,
};
