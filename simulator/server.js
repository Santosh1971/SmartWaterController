// server.js — mock SoftAP HTTP server matching lib/SoftAPHandler exactly.
// Routes, methods, and the {ok, payload} response envelope mirror the real
// ESP32 firmware on the softap-provisioning branch. Point the Flutter app's
// SoftAP base URL here (http://localhost:4000) instead of the real device's
// http://192.168.4.1 to develop against it with zero hardware.

const express = require('express');
const http = require('http');
const path = require('path');
const WebSocket = require('ws');
const state = require('./state');

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'dashboard.html')));

const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws' }); // dashboard live-update only, not part of real device API

function broadcast() {
  const msg = JSON.stringify({ type: 'status', data: state.buildStatusJSON() });
  wss.clients.forEach((c) => { if (c.readyState === WebSocket.OPEN) c.send(msg); });
}

function reply(res, ok, payload = {}) {
  res.status(ok ? 200 : 400).json({ ok, payload });
}

// ---- Real SoftAPHandler routes (match lib/SoftAPHandler/SoftAPHandler.cpp) ----

app.post('/wifi_config', (req, res) => {
  const { ssid, pass } = req.body || {};
  if (!ssid) return reply(res, false, { msg: 'ssid required' });
  state.setWifiConfig(ssid, pass || '');
  reply(res, true);
});

app.post('/mqtt_config', (req, res) => {
  const { broker, port, user, pass } = req.body || {};
  if (!broker) return reply(res, false, { msg: 'broker required' });
  state.setMqttConfig(broker, port || 1883, user || '', pass || '');
  reply(res, true);
});

app.post('/rtc_sync', (req, res) => {
  const { unix } = req.body || {};
  if (!unix) return reply(res, false, { msg: 'unix required' });
  state.setRtcSync(unix);
  reply(res, true);
});

app.post('/calibrate', (req, res) => {
  const { ppl } = req.body || {};
  state.setCalibration(ppl);
  reply(res, true);
});

app.post('/relay_test', (req, res) => {
  state.relayTest();
  reply(res, true);
});

app.post('/factory_reset', (req, res) => {
  reply(res, true);
  setTimeout(() => state.factoryReset(), 300);
});

app.get('/wifi_scan', (req, res) => res.json(state.wifiScan()));

app.get('/device_info', (req, res) => res.json(state.buildStatusJSON()));

// ---- Dashboard-only manual controls (not part of the real device API) ----
app.post('/sim/relay', (req, res) => res.json(state.setRelay(!!req.body.on)));
app.post('/sim/flow-rate', (req, res) => res.json(state.setFlowRate(req.body.literPerMin)));
app.post('/sim/reset-totals', (req, res) => res.json(state.resetTotals()));

wss.on('connection', (ws) => ws.send(JSON.stringify({ type: 'status', data: state.buildStatusJSON() })));
state.startFlowLoop(broadcast);

const PORT = process.env.PORT || 4000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`SWC SoftAP simulator running:`);
  console.log(`  Dashboard:   http://localhost:${PORT}`);
  console.log(`  Device API:  http://localhost:${PORT}/device_info  (point Flutter SoftAP client here)`);
  console.log(`  LAN access:  http://<this-machine-LAN-IP>:${PORT}  (use from a phone)`);
});
