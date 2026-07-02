import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String _serviceUuid = '12345678-1234-1234-1234-123456789abc';
  static const String _rxUuid      = '12345678-1234-1234-1234-123456789abd';
  static const String _txUuid      = '12345678-1234-1234-1234-123456789abe';

  BluetoothDevice?        _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;

  final _responseController = StreamController<Map<String,dynamic>>.broadcast();
  final _connectedController = StreamController<bool>.broadcast();

  Stream<Map<String,dynamic>> get responseStream  => _responseController.stream;
  Stream<bool>                get connectedStream => _connectedController.stream;

  bool get isConnected => _device != null &&
      _device!.isConnected;

  // Scan and return found devices named SmartWaterCtrl
  Stream<List<ScanResult>> scan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    return FlutterBluePlus.scanResults.map((results) => results
        .where((r) => r.device.platformName.contains('SmartWater'))
        .toList());
  }

  void stopScan() => FlutterBluePlus.stopScan();

  Future<bool> connect(BluetoothDevice device) async {
    _device = device;
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _serviceUuid) {
          for (final char in svc.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            if (uuid == _txUuid) {
              _tx = char;
              await _tx!.setNotifyValue(true);
              _tx!.lastValueStream.listen((value) {
                if (value.isEmpty) return;
                try {
                  final json = jsonDecode(utf8.decode(value));
                  _responseController.add(json);
                } catch (_) {}
              });
            }
            if (uuid == _rxUuid) _rx = char;
          }
        }
      }
      _connectedController.add(true);
      return _rx != null && _tx != null;
    } catch (e) {
      _connectedController.add(false);
      return false;
    }
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    if (_rx == null) return;
    final bytes = utf8.encode(jsonEncode(payload));
    await _rx!.write(bytes, withoutResponse: false);
  }

  // BLE Commands
  Future<void> syncRTC() async {
    final unix = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await _send({'cmd': 'rtc_sync', 'unix': unix});
  }

  Future<void> sendWifiConfig(String ssid, String pass) async {
    await _send({'cmd': 'wifi_config', 'ssid': ssid, 'pass': pass});
  }

  Future<void> sendMqttConfig(String broker, int port,
      String user, String pass) async {
    await _send({
      'cmd': 'mqtt_config',
      'broker': broker,
      'port': port,
      'user': user,
      'pass': pass,
    });
  }

  Future<void> sendCalibration(int pulsesPerLiter) async {
    await _send({'cmd': 'calibrate', 'ppl': pulsesPerLiter});
  }

  Future<void> testRelay() async {
    await _send({'cmd': 'relay_test'});
  }

  Future<void> getDeviceInfo() async {
    await _send({'cmd': 'device_info'});
  }

  Future<void> factoryReset() async {
    await _send({'cmd': 'factory_reset'});
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _rx = null;
    _tx = null;
    _connectedController.add(false);
  }

  void dispose() {
    _responseController.close();
    _connectedController.close();
    _device?.disconnect();
  }
}
