import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/device_status.dart';
import '../models/history_entry.dart';
import '../models/cycle.dart';

class MqttService {
  static const String _broker   = 'mqtt.grty.co.in';
  static const int    _port     = 1883;
  static const String _deviceId = 'SWC_001';

  static const String _topicStatus  = 'swc/$_deviceId/status';
  static const String _topicCmd     = 'swc/$_deviceId/command';
  static const String _topicHistory = 'swc/$_deviceId/history';
  static const String _topicCycles  = 'swc/$_deviceId/cycles';

  MqttServerClient? _client;
  Timer? _reconnectTimer;

  // Use late StreamControllers so they're always ready
  final _statusController   = StreamController<DeviceStatus>.broadcast();
  final _historyController  = StreamController<List<HistoryEntry>>.broadcast();
  final _cyclesController   = StreamController<List<Cycle>>.broadcast();
  final _connectedController= StreamController<bool>.broadcast();

  Stream<DeviceStatus>       get statusStream    => _statusController.stream;
  Stream<List<HistoryEntry>> get historyStream   => _historyController.stream;
  Stream<List<Cycle>>        get cyclesStream    => _cyclesController.stream;
  Stream<bool>               get connectedStream => _connectedController.stream;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<bool> connect() async {
    // Disconnect existing connection cleanly
    try { _client?.disconnect(); } catch (_) {}
    _client = null;

    final clientId = 'swc_app_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(_broker, clientId, _port);
    _client!.logging(on: true);  // enable for debug
    _client!.keepAlivePeriod = 20;
    _client!.connectTimeoutPeriod = 10000;
    _client!.autoReconnect = true;
    _client!.onDisconnected   = _onDisconnected;
    _client!.onConnected      = _onConnected;
    _client!.onAutoReconnect  = () => print('[MQTT] Auto reconnecting...');

    final connMsg = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();
    _client!.connectionMessage = connMsg;

    try {
      print('[MQTT] Connecting to $_broker:$_port as $clientId');
      await _client!.connect();
    } catch (e) {
      print('[MQTT] Connect error: $e');
      _connectedController.add(false);
      return false;
    }

    if (_client!.connectionStatus!.state != MqttConnectionState.connected) {
      print('[MQTT] Failed: ${_client!.connectionStatus!.returnCode}');
      _connectedController.add(false);
      return false;
    }

    print('[MQTT] Connected — subscribing to topics');

    // Subscribe with QoS 0 for status (high frequency)
    _client!.subscribe(_topicStatus,  MqttQos.atMostOnce);
    _client!.subscribe(_topicHistory, MqttQos.atLeastOnce);
    _client!.subscribe(_topicCycles,  MqttQos.atLeastOnce);

    // Listen to incoming messages
    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> msgs) {
      for (final msg in msgs) {
        final pub     = msg.payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
                            pub.payload.message);
        print('[MQTT] Received on ${msg.topic}: $payload');
        _handleMessage(msg.topic, payload);
      }
    });

    _connectedController.add(true);
    return true;
  }

  void _handleMessage(String topic, String payload) {
    try {
      if (topic == _topicStatus) {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        _statusController.add(DeviceStatus.fromJson(json));
      } else if (topic == _topicHistory) {
        final list = (jsonDecode(payload) as List)
            .map((e) => HistoryEntry.fromJson(e))
            .toList();
        _historyController.add(list);
      } else if (topic == _topicCycles) {
        final list = (jsonDecode(payload) as List)
            .map((e) => Cycle.fromJson(e))
            .toList();
        _cyclesController.add(list);
      }
    } catch (e) {
      print('[MQTT] Parse error on $topic: $e');
    }
  }

  void _publish(Map<String, dynamic> payload) {
    if (!isConnected) {
      print('[MQTT] Not connected — cannot publish');
      return;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));
    _client!.publishMessage(_topicCmd, MqttQos.atLeastOnce, builder.payload!);
    print('[MQTT] Published: ${jsonEncode(payload)}');
  }

  void manualOn()                  => _publish({'cmd': 'manual_on'});
  void manualOff()                 => _publish({'cmd': 'manual_off'});
  void manualLiters(double liters) => _publish({'cmd': 'manual_liters', 'liters': liters});
  void stopCycle()                 => _publish({'cmd': 'stop_cycle'});
  void pauseCycle()                => _publish({'cmd': 'pause_cycle'});
  void resumeCycle()               => _publish({'cmd': 'resume_cycle'});
  void getHistory()                => _publish({'cmd': 'get_history'});
  void getCycles()                 => _publish({'cmd': 'get_cycles'});
  void setCycles(List<Cycle> cycles) => _publish({
        'cmd': 'set_cycles',
        'cycles': cycles.map((c) => c.toJson()).toList(),
      });

  void _onConnected()    { print('[MQTT] onConnected'); _connectedController.add(true);  }
  void _onDisconnected() { print('[MQTT] onDisconnected'); _connectedController.add(false); }

  void dispose() {
    _reconnectTimer?.cancel();
    _statusController.close();
    _historyController.close();
    _cyclesController.close();
    _connectedController.close();
    try { _client?.disconnect(); } catch (_) {}
  }
}
