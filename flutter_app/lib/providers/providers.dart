import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mqtt_service.dart';
import '../services/ble_service.dart';
import '../models/device_status.dart';
import '../models/cycle.dart';
import '../models/history_entry.dart';

// Services
final mqttServiceProvider = Provider<MqttService>((ref) {
  final svc = MqttService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

// MQTT connection state
final mqttConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(mqttServiceProvider).connectedStream;
});

// Device status
final deviceStatusProvider = StreamProvider<DeviceStatus>((ref) {
  return ref.watch(mqttServiceProvider).statusStream;
});

// Cycles
final cyclesProvider = StreamProvider<List<Cycle>>((ref) {
  return ref.watch(mqttServiceProvider).cyclesStream;
});

// History
final historyProvider = StreamProvider<List<HistoryEntry>>((ref) {
  return ref.watch(mqttServiceProvider).historyStream;
});

// BLE connection state
final bleConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(bleServiceProvider).connectedStream;
});
