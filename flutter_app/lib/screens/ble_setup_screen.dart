import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../providers/providers.dart';

class BleSetupScreen extends ConsumerStatefulWidget {
  const BleSetupScreen({super.key});
  @override
  ConsumerState<BleSetupScreen> createState() => _BleSetupScreenState();
}

class _BleSetupScreenState extends ConsumerState<BleSetupScreen> {
  List<ScanResult> _devices  = [];
  bool _scanning             = false;
  bool _connected            = false;
  String _connectedName      = '';
  String _log                = '';
  StreamSubscription? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void _addLog(String msg) {
    final time = DateTime.now().toString().substring(11, 19);
    setState(() => _log = '$time  $msg\n$_log');
  }

  // ── BLE Scan ───────────────────────────────────────────
  Future<void> _startScan() async {
    // Request BLE permission check
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      _addLog('❌ Bluetooth is OFF — please enable it');
      return;
    }

    setState(() { _devices = []; _scanning = true; });
    _addLog('🔍 Scanning for BLE devices...');

    await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true);

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _devices = results
            .where((r) => r.device.platformName.isNotEmpty)
            .toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    await Future.delayed(const Duration(seconds: 10));
    await FlutterBluePlus.stopScan();
    setState(() => _scanning = false);
    _addLog('✅ Scan complete — ${_devices.length} device(s) found');
  }

  // ── BLE Connect ────────────────────────────────────────
  Future<void> _connect(BluetoothDevice device) async {
    _addLog('🔗 Connecting to ${device.platformName}...');
    final ble = ref.read(bleServiceProvider);
    final ok  = await ble.connect(device);
    setState(() {
      _connected     = ok;
      _connectedName = device.platformName;
    });
    if (ok) {
      _addLog('✅ Connected to ${device.platformName}');
      await ble.syncRTC();
      _addLog('🕐 RTC synced with phone time');
      ble.responseStream.listen((resp) {
        final status = resp['ok'] == true ? '✅' : '❌';
        _addLog('$status Response: ${resp['cmd']}');
      });
    } else {
      _addLog('❌ Connection failed — try again');
    }
  }

  Future<void> _disconnect() async {
    final ble = ref.read(bleServiceProvider);
    await ble.disconnect();
    setState(() { _connected = false; _connectedName = ''; });
    _addLog('🔌 Disconnected');
  }

  // ── WiFi Dialog with scan list ─────────────────────────
  Future<void> _showWifiDialog() async {
    // Common networks list — user can also type manually
    // In future, ESP32 can send scan results via BLE
    String selectedSSID  = '';
    bool   obscure       = true;
    final  ssidCtrl      = TextEditingController();
    final  passCtrl      = TextEditingController();
    bool   showManual    = false;

    // Predefined + allow manual entry
    final commonNets = <String>[];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.wifi, color: Color(0xFF2196F3)),
            SizedBox(width: 8),
            Text('WiFi Configuration'),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // Manual SSID entry
              TextField(
                controller: ssidCtrl,
                onChanged: (v) => setSt(() => selectedSSID = v),
                decoration: InputDecoration(
                  labelText: 'WiFi Name (SSID)',
                  prefixIcon: const Icon(Icons.wifi),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  hintText: 'Enter WiFi name',
                ),
              ),
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setSt(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.info_outline,
                      color: Color(0xFFFF9800), size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Make sure ESP32 is powered and BLE is connected before sending.',
                    style: TextStyle(fontSize: 11,
                        color: Color(0xFFE65100)),
                  )),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final ssid = ssidCtrl.text.trim();
                final pass = passCtrl.text;
                if (ssid.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter WiFi name')));
                  return;
                }
                Navigator.pop(ctx);
                final ble = ref.read(bleServiceProvider);
                _addLog('📡 Sending WiFi config: $ssid');
                await ble.sendWifiConfig(ssid, pass);
                _addLog('⏳ Device connecting to $ssid...');
                _addLog('   Watch MQTT dashboard — device will appear when connected');
              },
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              label: const Text('Send to Device',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3)),
            ),
          ],
        ),
      ),
    );
  }

  // ── MQTT Config ────────────────────────────────────────
  Future<void> _showMqttDialog() async {
    final brokerCtrl = TextEditingController(text: 'mqtt.grty.co.in');
    final portCtrl   = TextEditingController(text: '1883');
    final userCtrl   = TextEditingController();
    final passCtrl   = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.cloud, color: Color(0xFF4CAF50)),
          SizedBox(width: 8),
          Text('MQTT Settings'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _dialogField(brokerCtrl, 'Broker Address', Icons.dns),
          const SizedBox(height: 10),
          _dialogField(portCtrl, 'Port', Icons.numbers,
              type: TextInputType.number),
          const SizedBox(height: 10),
          _dialogField(userCtrl, 'Username (optional)', Icons.person),
          const SizedBox(height: 10),
          _dialogField(passCtrl, 'Password (optional)', Icons.lock,
              obscure: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final ble = ref.read(bleServiceProvider);
              await ble.sendMqttConfig(
                brokerCtrl.text,
                int.tryParse(portCtrl.text) ?? 1883,
                userCtrl.text,
                passCtrl.text,
              );
              _addLog('✅ MQTT config sent: ${brokerCtrl.text}');
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50)),
            child: const Text('Send',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Calibration ────────────────────────────────────────
  Future<void> _showCalibrationDialog() async {
    final ctrl = TextEditingController(text: '450');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Flow Sensor Calibration'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter the number of pulses the sensor generates per 1 liter of water.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Pulses per Liter',
              suffixText: 'pulses/L',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8))),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final ble = ref.read(bleServiceProvider);
              await ble.sendCalibration(int.tryParse(ctrl.text) ?? 450);
              _addLog('✅ Calibration set: ${ctrl.text} pulses/L');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label,
      IconData icon, {TextInputType? type, bool obscure = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        title: const Text('BLE Device Setup',
            style: TextStyle(color: Colors.black87,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Column(children: [

        Expanded(child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // ── Status Banner ──────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _connected
                    ? const Color(0xFFE8F5E9) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _connected
                    ? const Color(0xFF4CAF50) : Colors.grey.shade200),
              ),
              child: Row(children: [
                Icon(Icons.bluetooth,
                    color: _connected
                        ? const Color(0xFF4CAF50) : Colors.grey,
                    size: 28),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_connected
                      ? '✅ Connected to $_connectedName'
                      : '⚪ Not connected',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _connected
                            ? const Color(0xFF4CAF50) : Colors.grey)),
                  Text(_connected
                      ? 'Tap options below to configure'
                      : 'Scan to find your Smart Water Controller',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
                ])),
                if (_connected)
                  TextButton(
                    onPressed: _disconnect,
                    child: const Text('Disconnect',
                        style: TextStyle(color: Colors.red)),
                  ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Scan / Device List ─────────────────────
            if (!_connected) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: _scanning
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.bluetooth_searching,
                          color: Colors.white),
                  label: Text(_scanning
                      ? 'Scanning...' : 'Scan for SmartWaterCtrl',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (_devices.isNotEmpty) ...[
                Text('Found ${_devices.length} device(s):',
                    style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                const SizedBox(height: 8),
                ..._devices.map((r) {
                  final isTarget = r.device.platformName
                      .contains('SmartWater');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isTarget
                          ? const Color(0xFFE3F2FD) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isTarget
                            ? const Color(0xFF2196F3)
                            : Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.bluetooth,
                          color: isTarget
                              ? const Color(0xFF2196F3) : Colors.grey),
                      title: Text(r.device.platformName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isTarget
                                ? const Color(0xFF2196F3)
                                : Colors.black87)),
                      subtitle: Text(
                          '${r.device.remoteId} • ${r.rssi} dBm',
                          style: const TextStyle(fontSize: 11)),
                      trailing: ElevatedButton(
                        onPressed: () => _connect(r.device),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isTarget
                              ? const Color(0xFF2196F3) : Colors.grey,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                        child: const Text('Connect',
                            style: TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  );
                }),
              ],
            ],

            // ── Config Options (when connected) ────────
            if (_connected) ...[
              const Text('CONFIGURE DEVICE',
                  style: TextStyle(color: Colors.grey,
                      fontSize: 11, fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),

              _ConfigTile(
                icon: Icons.wifi,
                color: const Color(0xFF2196F3),
                title: 'WiFi Settings',
                subtitle: 'Connect device to your WiFi network',
                onTap: _showWifiDialog,
              ),
              _ConfigTile(
                icon: Icons.cloud,
                color: const Color(0xFF4CAF50),
                title: 'MQTT Settings',
                subtitle: 'Configure broker: mqtt.grty.co.in:1883',
                onTap: _showMqttDialog,
              ),
              _ConfigTile(
                icon: Icons.access_time,
                color: const Color(0xFFFF9800),
                title: 'Sync Time & Date',
                subtitle: 'Sync RTC with phone time automatically',
                onTap: () async {
                  final ble = ref.read(bleServiceProvider);
                  await ble.syncRTC();
                  _addLog('✅ RTC synced: ${DateTime.now()}');
                },
              ),
              _ConfigTile(
                icon: Icons.water_drop_outlined,
                color: const Color(0xFF9C27B0),
                title: 'Flow Sensor Calibration',
                subtitle: 'Default: 450 pulses per liter',
                onTap: _showCalibrationDialog,
              ),
              _ConfigTile(
                icon: Icons.electrical_services,
                color: const Color(0xFFFF9800),
                title: 'Test Relay (5 sec)',
                subtitle: 'Verify pump connection',
                onTap: () async {
                  final ble = ref.read(bleServiceProvider);
                  await ble.testRelay();
                  _addLog('⚡ Relay test pulse sent — 5 seconds');
                },
              ),
              const SizedBox(height: 8),
              const Text('DANGER ZONE',
                  style: TextStyle(color: Colors.red,
                      fontSize: 11, fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              _ConfigTile(
                icon: Icons.warning_amber,
                color: Colors.red,
                title: 'Factory Reset',
                subtitle: 'Erase all settings from device',
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Factory Reset'),
                      content: const Text(
                          'This will erase WiFi, MQTT, cycles and all data from the device. This cannot be undone.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                          child: const Text('Factory Reset',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final ble = ref.read(bleServiceProvider);
                    await ble.factoryReset();
                    _addLog('🔄 Factory reset sent — device restarting');
                    await _disconnect();
                  }
                },
              ),
            ],
          ],
        )),

        // ── Log Panel ──────────────────────────────────
        Container(
          height: 160,
          color: const Color(0xFF1A1A2E),
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              const Text('DEVICE LOG',
                  style: TextStyle(color: Colors.grey,
                      fontSize: 10, fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _log = ''),
                child: const Text('CLEAR',
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
              ),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                reverse: false,
                child: Text(
                  _log.isEmpty
                      ? 'Tap "Scan for SmartWaterCtrl" to begin...'
                      : _log,
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 11,
                    height: 1.6,
                    fontFamily: 'monospace'),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ConfigTile({required this.icon, required this.color,
                     required this.title, required this.subtitle,
                     required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
          blurRadius: 6)],
    ),
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20)),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    ),
  );
}
