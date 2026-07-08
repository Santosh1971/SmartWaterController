import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/device_status.dart';
import '../services/device_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // No initState()-driven connect() here anymore — main.dart's MainShell
  // already connects once at app startup, and IndexedStack keeps this
  // screen's State alive across tab switches now, so there's no need to
  // (and no good moment to safely) reconnect every time this becomes
  // visible again. _connect() is still available as a manual retry.
  bool _retrying = false;

  Future<void> _connect() async {
    setState(() => _retrying = true);
    await ref.read(deviceServiceProvider).connect();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(deviceStatusProvider);
    final connectedAsync = ref.watch(deviceConnectedProvider);
    final mqtt = ref.read(deviceServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const Icon(Icons.menu, color: Colors.black87),
        title: const Text('Dashboard',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
            onPressed: () {},
          ),
        ],
      ),
      body: statusAsync.maybeWhen(
        data: (s) => _buildDashboard(s, mqtt),
        orElse: () => _buildLoading(connectedAsync),
      ),
    );
  }

  Widget _buildLoading(AsyncValue<bool> connectedAsync) {
    final connected = connectedAsync.maybeWhen(data: (c) => c, orElse: () => false);
    final label = _retrying
        ? 'Connecting...'
        : connected
            ? 'Waiting for device...'
            : 'Not connected — retry?';
    return Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.water_drop_outlined, size: 64, color: Color(0xFF2196F3)),
      const SizedBox(height: 24),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
      const SizedBox(height: 16),
      const CircularProgressIndicator(color: Color(0xFF2196F3)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: _connect,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
      ),
    ]));
  }

  Widget _buildDashboard(DeviceStatus s, DeviceService mqtt) {
    return RefreshIndicator(
      onRefresh: () async => _connect(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Device Connected Banner
          _DeviceBanner(status: s),
          const SizedBox(height: 16),

          // Pump Status + Today's Progress
          Row(children: [
            Expanded(child: _PumpStatusCard(status: s)),
            const SizedBox(width: 12),
            Expanded(child: _ProgressCard(status: s)),
          ]),
          const SizedBox(height: 12),

          // Next Cycle Row
          Row(children: [
            Expanded(child: _InfoCard(
              icon: Icons.access_time,
              iconColor: const Color(0xFF2196F3),
              label: 'Next Cycle',
              value: s.cycleActive ? 'Running' : '--:--',
              sub: '',
            )),
            const SizedBox(width: 12),
            Expanded(child: _InfoCard(
              icon: Icons.water_drop,
              iconColor: const Color(0xFF2196F3),
              label: 'Next Cycle Detail',
              value: '${s.litersDelivered.toStringAsFixed(1)} L',
              sub: '',
            )),
          ]),
          const SizedBox(height: 12),

          // Active Cycle Card
          if (s.cycleActive) ...[
            _ActiveCycleCard(status: s, mqtt: mqtt),
            const SizedBox(height: 12),
          ],

          // Today's Summary
          _SummaryCard(status: s),
          const SizedBox(height: 12),

          // Last Cycle
          _LastCycleCard(status: s),
        ],
      ),
    );
  }
}

// ── Device Banner ──────────────────────────────────────────
class _DeviceBanner extends StatelessWidget {
  final DeviceStatus status;
  const _DeviceBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final online = status.mqttConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Icon(online ? Icons.wifi : Icons.wifi_off,
             color: online ? const Color(0xFF4CAF50) : Colors.red, size: 28),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(online ? 'Device Connected' : 'Device Offline',
               style: TextStyle(
                 fontWeight: FontWeight.w600, fontSize: 15,
                 color: online ? const Color(0xFF4CAF50) : Colors.red)),
          Text(status.deviceId.isEmpty ? 'Searching...' : status.deviceId,
               style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.router, color: Colors.grey, size: 28)),
      ]),
    );
  }
}

// ── Pump Status Card ──────────────────────────────────────
class _PumpStatusCard extends StatelessWidget {
  final DeviceStatus status;
  const _PumpStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final on = status.pumpOn;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pump Status',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        Center(
          child: Icon(Icons.settings_input_component,
              size: 56,
              color: on ? const Color(0xFFFF9800) : Colors.grey.shade400),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(on ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold,
                color: on ? const Color(0xFF4CAF50) : Colors.grey)),
        ),
        if (on) ...[
          const SizedBox(height: 4),
          Center(
            child: Text('Since ${status.rtcTime}',
                style: const TextStyle(color: Colors.grey, fontSize: 11))),
        ],
      ]),
    );
  }
}

// ── Progress Ring Card ────────────────────────────────────
class _ProgressCard extends StatelessWidget {
  final DeviceStatus status;
  const _ProgressCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        const Text('Today\'s Progress',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        SizedBox(
          width: 90, height: 90,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: status.litersDelivered / 200,
              strokeWidth: 8,
              backgroundColor: Colors.grey.shade200,
              color: const Color(0xFF2196F3),
            ),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${status.litersDelivered.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold,
                    color: Colors.black87)),
              const Text('Liters',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        Text('${((status.litersDelivered / 200) * 100).toStringAsFixed(0)}% of Daily Usage',
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ]),
    );
  }
}

// ── Info Card ─────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, value, sub;
  const _InfoCard({required this.icon, required this.iconColor,
                   required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          Text(value, style: const TextStyle(
              fontWeight: FontWeight.bold, color: Color(0xFF2196F3), fontSize: 14)),
          if (sub.isNotEmpty)
            Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ])),
      ]),
    );
  }
}

// ── Active Cycle Card ─────────────────────────────────────
class _ActiveCycleCard extends StatelessWidget {
  final DeviceStatus status;
  final DeviceService mqtt;
  const _ActiveCycleCard({required this.status, required this.mqtt});

  @override
  Widget build(BuildContext context) {
    final paused = status.cyclePaused;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.loop, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Active Cycle — ${paused ? "Paused" : "Running"}',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        // Body
        Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Row(children: [
              _CycleDetailItem(label: 'Start Time', value: status.rtcTime),
              _CycleDetailItem(label: 'End Time', value: '--:--'),
              _CycleDetailItem(label: 'Target', value: '--'),
            ]),
            const Divider(height: 16),
            Row(children: [
              _CycleDetailItem(
                  label: 'Delivered',
                  value: '${status.litersDelivered.toStringAsFixed(1)} L',
                  valueColor: const Color(0xFF2196F3)),
              _CycleDetailItem(label: 'Remaining', value: '-- L',
                  valueColor: const Color(0xFFFF9800)),
              _CycleDetailItem(label: 'Progress', value: '--%',
                  valueColor: const Color(0xFF4CAF50)),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 0.42,
              backgroundColor: Colors.grey.shade200,
              color: const Color(0xFF4CAF50),
              minHeight: 6,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: paused ? () => mqtt.resumeCycle()
                                    : () => mqtt.pauseCycle(),
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
                  label: Text(paused ? 'Resume' : 'Pause'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4CAF50),
                    side: const BorderSide(color: Color(0xFF4CAF50))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => mqtt.stopCycle(),
                  icon: const Icon(Icons.stop, size: 18, color: Colors.white),
                  label: const Text('STOP CYCLE',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _CycleDetailItem extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _CycleDetailItem({required this.label, required this.value,
                           this.valueColor});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(
          fontWeight: FontWeight.bold, fontSize: 13,
          color: valueColor ?? Colors.black87)),
    ]),
  );
}

// ── Summary Card ──────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final DeviceStatus status;
  const _SummaryCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Today's Summary",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 12),
        Row(children: [
          _SummaryItem(label: 'Total Water',
              value: '${status.litersDelivered.toStringAsFixed(1)} L',
              color: const Color(0xFF2196F3)),
          _SummaryItem(label: 'Total Cycles',
              value: status.cycleActive ? '1' : '0',
              color: const Color(0xFF4CAF50)),
          _SummaryItem(label: 'Manual Use',
              value: status.startedBy == 'manual'
                  ? '${status.litersDelivered.toStringAsFixed(1)} L' : '0.0 L',
              color: const Color(0xFFFF9800)),
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
            const SizedBox(width: 6),
            Text('Last Cycle (${status.rtcDate})',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Spacer(),
            const Text('Completed',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ]),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryItem({required this.label, required this.value,
                      required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(
          fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
    ]),
  );
}

// ── Last Cycle Card ───────────────────────────────────────
class _LastCycleCard extends StatelessWidget {
  final DeviceStatus status;
  const _LastCycleCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Device Info',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          Text('RTC: ${status.rtcDate} ${status.rtcTime}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text('WiFi: ${status.wifiRssi} dBm',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text('Firmware: ${status.firmware}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ]),
    );
  }
}
