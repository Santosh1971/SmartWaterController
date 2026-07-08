import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/device_service.dart';
import '../services/mqtt_service.dart';
import '../services/local_service.dart';
import '../models/device_status.dart';
import '../models/cycle.dart';
import '../models/history_entry.dart';

enum TransportMode { local, cloud }

const _transportPrefsKey = 'transport_mode';

// Individual transports -- both always exist; only one is "active" at a
// time per transportModeProvider, but keeping both alive means switching
// doesn't lose any in-flight connection state.
final mqttServiceProvider = Provider<MqttService>((ref) {
  final svc = MqttService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final localServiceProvider = Provider<LocalService>((ref) {
  final svc = LocalService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

// Manual transport switch -- SoftAP (local) is the default, per design
// decision: most setup/testing happens on the device's own network, and
// this avoids surprising a no-internet customer with a cloud attempt.
// Persisted so the choice survives app restarts.
class TransportModeNotifier extends StateNotifier<TransportMode> {
  TransportModeNotifier() : super(TransportMode.local) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_transportPrefsKey);
    if (saved == 'cloud') state = TransportMode.cloud;
  }

  Future<void> setMode(TransportMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _transportPrefsKey, mode == TransportMode.cloud ? 'cloud' : 'local');
  }
}

final transportModeProvider =
    StateNotifierProvider<TransportModeNotifier, TransportMode>(
        (ref) => TransportModeNotifier());

// The "active" transport -- this is what screens should actually use.
// Resolves to whichever concrete service matches the current mode.
final deviceServiceProvider = Provider<DeviceService>((ref) {
  final mode = ref.watch(transportModeProvider);
  return mode == TransportMode.local
      ? ref.watch(localServiceProvider)
      : ref.watch(mqttServiceProvider);
});

// Connection state, status, cycles, history -- all driven by whichever
// transport is currently active. Switching transportModeProvider
// automatically re-subscribes these to the new service.
final deviceConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(deviceServiceProvider).connectedStream;
});

final deviceStatusProvider = StreamProvider<DeviceStatus>((ref) {
  return ref.watch(deviceServiceProvider).statusStream;
});

final cyclesProvider = StreamProvider<List<Cycle>>((ref) {
  return ref.watch(deviceServiceProvider).cyclesStream;
});

final historyProvider = StreamProvider<List<HistoryEntry>>((ref) {
  return ref.watch(deviceServiceProvider).historyStream;
});
