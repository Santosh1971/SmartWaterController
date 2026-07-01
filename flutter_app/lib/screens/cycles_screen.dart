import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/cycle.dart';
import '../services/mqtt_service.dart';
import 'add_cycle_screen.dart';

class CyclesScreen extends ConsumerWidget {
  const CyclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cyclesAsync = ref.watch(cyclesProvider);
    final mqtt = ref.read(mqttServiceProvider);

    // Request cycles on first load
    WidgetsBinding.instance.addPostFrameCallback((_) => mqtt.getCycles());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const Icon(Icons.menu, color: Colors.black87),
        title: const Text('Cycles',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              shape: const CircleBorder()),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddCycleScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: cyclesAsync.maybeWhen(
        data: (cycles) => cycles.isEmpty
            ? _buildEmpty(context)
            : _buildList(context, cycles, mqtt),
        orElse: () => _buildEmpty(context),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.loop, size: 64, color: Colors.grey),
      const SizedBox(height: 16),
      const Text('No cycles configured',
          style: TextStyle(color: Colors.grey, fontSize: 16)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AddCycleScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Add First Cycle'),
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3)),
      ),
    ]),
  );

  Widget _buildList(BuildContext context, List<Cycle> cycles,
      MqttService mqtt) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cycles.length,
      itemBuilder: (_, i) => _CycleTile(
        cycle: cycles[i],
        onTap: () => Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => AddCycleScreen(cycle: cycles[i]))),
        onToggle: (val) {
          final updated = cycles[i].copyWith(enabled: val);
          final allCycles = List<Cycle>.from(cycles);
          allCycles[i] = updated;
          mqtt.setCycles(allCycles);
        },
      ),
    );
  }
}

class _CycleTile extends StatelessWidget {
  final Cycle cycle;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  const _CycleTile({required this.cycle, required this.onTap,
                    required this.onToggle});

  Color get _modeColor => switch (cycle.mode) {
        OperationMode.literBased      => const Color(0xFF9C27B0),
        OperationMode.timeBased       => const Color(0xFF4CAF50),
        OperationMode.timeWindowLiter => const Color(0xFF2196F3),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        onTap: onTap,
        title: Row(children: [
          Text(cycle.name.isEmpty ? 'Cycle ${cycle.id}' : cycle.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _modeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
            child: Text(cycle.modeLabel,
                style: TextStyle(color: _modeColor, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.access_time, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(cycle.startTimeStr,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(width: 8),
            const Text('Everyday',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
          if (cycle.mode != OperationMode.timeBased) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.water_drop, size: 14, color: Color(0xFF2196F3)),
              const SizedBox(width: 4),
              Text('${cycle.targetLiters.toStringAsFixed(1)} L',
                  style: const TextStyle(
                      color: Color(0xFF2196F3), fontWeight: FontWeight.w600)),
            ]),
          ],
          if (cycle.mode != OperationMode.literBased) ...[
            const SizedBox(height: 2),
            Text('${cycle.startTimeStr} - ${cycle.endTimeStr}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(
            value: cycle.enabled,
            onChanged: onToggle,
            activeColor: const Color(0xFF4CAF50),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}
