import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/device_status.dart';
import '../services/mqtt_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _connectionStatus = 'Connecting...';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _connectionStatus = 'Connecting to broker...');
    final mqtt = ref.read(mqttServiceProvider);
    final ok   = await mqtt.connect();
    setState(() => _connectionStatus = ok ? 'Waiting for device...' : 'Broker unreachable');
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(deviceStatusProvider);
    final mqtt        = ref.read(mqttServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Water Controller'),
        actions: [
          statusAsync.maybeWhen(
            data: (s) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                s.mqttConnected ? Icons.cloud_done : Icons.cloud_off,
                color: s.mqttConnected ? Colors.green : Colors.red,
              ),
            ),
            orElse: () => const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.cloud_off, color: Colors.grey),
            ),
          ),
        ],
      ),
      body: statusAsync.maybeWhen(
        data: (s) => _buildDashboard(context, s, mqtt),
        orElse: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.water_drop, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              Text(_connectionStatus,
                   style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, DeviceStatus s, MqttService mqtt) {
    return RefreshIndicator(
      onRefresh: () async => _connect(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DeviceBanner(status: s),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _PumpCard(status: s)),
            const SizedBox(width: 12),
            Expanded(child: _ProgressCard(status: s)),
          ]),
          const SizedBox(height: 12),
          if (s.cycleActive) ...[
            _ActiveCycleCard(status: s, mqtt: mqtt),
            const SizedBox(height: 12),
          ],
          _SummaryCard(status: s),
          const SizedBox(height: 12),
          _DeviceInfoCard(status: s),
        ],
      ),
    );
  }
}

class _DeviceBanner extends StatelessWidget {
  final DeviceStatus status;
  const _DeviceBanner({required this.status});
  @override
  Widget build(BuildContext context) {
    final online = status.mqttConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: online ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: online ? Colors.green : Colors.red),
      ),
      child: Row(children: [
        Icon(online ? Icons.wifi : Icons.wifi_off,
             color: online ? Colors.green : Colors.red),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(online ? 'Device Connected' : 'Device Offline',
               style: TextStyle(
                 fontWeight: FontWeight.bold,
                 color: online ? Colors.green.shade800 : Colors.red.shade800)),
          Text(status.deviceId.isEmpty ? '—' : status.deviceId,
               style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        const Spacer(),
        if (online) Text('${status.wifiRssi} dBm',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}

class _PumpCard extends StatelessWidget {
  final DeviceStatus status;
  const _PumpCard({required this.status});
  @override
  Widget build(BuildContext context) {
    final on = status.pumpOn;
    return Card(
      color: on ? Colors.green.shade50 : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Icon(Icons.water_drop, size: 40, color: on ? Colors.green : Colors.grey),
          const SizedBox(height: 8),
          Text('Pump', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          Text(on ? 'ON' : 'OFF',
               style: TextStyle(
                 fontSize: 22, fontWeight: FontWeight.bold,
                 color: on ? Colors.green : Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(status.rtcTime, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final DeviceStatus status;
  const _ProgressCard({required this.status});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Icon(Icons.show_chart, size: 40, color: Colors.blue),
          const SizedBox(height: 8),
          Text('Delivered', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          Text('${status.litersDelivered.toStringAsFixed(1)} L',
               style: const TextStyle(
                 fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 4),
          Text(status.rtcDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _ActiveCycleCard extends StatelessWidget {
  final DeviceStatus status;
  final MqttService  mqtt;
  const _ActiveCycleCard({required this.status, required this.mqtt});
  @override
  Widget build(BuildContext context) {
    final paused = status.cyclePaused;
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.loop, color: Colors.blue),
            const SizedBox(width: 8),
            Text('Cycle ${status.cycleId} Running',
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: paused ? Colors.orange : Colors.blue,
                borderRadius: BorderRadius.circular(12)),
              child: Text(paused ? 'PAUSED' : 'RUNNING',
                   style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 12),
          Text('${status.litersDelivered.toStringAsFixed(1)} L delivered',
               style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: paused
                    ? () => mqtt.resumeCycle()
                    : () => mqtt.pauseCycle(),
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(paused ? 'Resume' : 'Pause'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => mqtt.stopCycle(),
                icon: const Icon(Icons.stop, color: Colors.white),
                label: const Text('Stop', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final DeviceStatus status;
  const _SummaryCard({required this.status});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Today's Summary",
               style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(children: [
            _SummaryItem(icon: Icons.water,
              label: 'Total Water',
              value: '${status.litersDelivered.toStringAsFixed(1)} L',
              color: Colors.blue),
            _SummaryItem(icon: Icons.person,
              label: 'Started By',
              value: status.startedBy.isEmpty ? '—' : status.startedBy,
              color: Colors.green),
            _SummaryItem(icon: Icons.network_wifi,
              label: 'Signal',
              value: '${status.wifiRssi} dBm',
              color: Colors.orange),
          ]),
        ]),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _SummaryItem({required this.icon, required this.label,
                      required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(value,
             style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final DeviceStatus status;
  const _DeviceInfoCard({required this.status});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Device Info',
               style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _InfoRow('Firmware', status.firmware.isEmpty ? '—' : status.firmware),
          _InfoRow('RTC', '${status.rtcDate} ${status.rtcTime}'),
          _InfoRow('RTC Set', status.rtcSet ? 'Yes' : 'No — sync via BLE'),
          _InfoRow('WiFi', status.wifiConnected ? 'Connected' : 'Disconnected'),
          _InfoRow('MQTT', status.mqttConnected ? 'Connected' : 'Disconnected'),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 80,
          child: Text(label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
        Expanded(
          child: Text(value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
      ]),
    );
  }
}
