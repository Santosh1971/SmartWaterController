import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/cycle.dart';
import '../services/mqtt_service.dart';
import 'add_cycle_screen.dart';

class CyclesScreen extends ConsumerStatefulWidget {
  const CyclesScreen({super.key});
  @override
  ConsumerState<CyclesScreen> createState() => _CyclesScreenState();
}

class _CyclesScreenState extends ConsumerState<CyclesScreen> {
  // Local cycles list — updated from MQTT + local edits
  List<Cycle> _cycles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _requestCycles();
    // Listen to cycles stream
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mqttServiceProvider).cyclesStream.listen((cycles) {
        if (mounted) setState(() { _cycles = cycles; _loading = false; });
      });
    });
  }

  void _requestCycles() {
    setState(() => _loading = true);
    ref.read(mqttServiceProvider).getCycles();
    // Timeout loading after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _loading) setState(() => _loading = false);
    });
  }

  Future<void> _openAddCycle({Cycle? cycle}) async {
    await Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => AddCycleScreen(
                  cycle: cycle,
                  existingCycles: _cycles,
                  onSaved: (updatedCycles) {
                    setState(() => _cycles = updatedCycles);
                    // Send to device
                    ref.read(mqttServiceProvider).setCycles(updatedCycles);
                  },
                )));
    // Refresh after returning
    _requestCycles();
  }

  void _toggleCycle(int index, bool val) {
    final updated = List<Cycle>.from(_cycles);
    updated[index] = _cycles[index].copyWith(enabled: val);
    setState(() => _cycles = updated);
    ref.read(mqttServiceProvider).setCycles(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const Icon(Icons.menu, color: Colors.black87),
        title: const Text('Cycles',
            style: TextStyle(color: Colors.black87,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (_cycles.length < 4)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  shape: const CircleBorder()),
              onPressed: () => _openAddCycle(),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF2196F3)),
                SizedBox(height: 16),
                Text('Loading cycles...', style: TextStyle(color: Colors.grey)),
              ]))
          : _cycles.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.loop, size: 64, color: Colors.grey),
      const SizedBox(height: 16),
      const Text('No cycles configured',
          style: TextStyle(color: Colors.grey, fontSize: 16)),
      const SizedBox(height: 8),
      const Text('Tap + to add your first watering cycle',
          style: TextStyle(color: Colors.grey, fontSize: 13)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => _openAddCycle(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Cycle',
            style: TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12)),
      ),
    ]),
  );

  Widget _buildList() => RefreshIndicator(
    onRefresh: () async => _requestCycles(),
    child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _cycles.length,
      itemBuilder: (_, i) => _CycleTile(
        cycle: _cycles[i],
        index: i + 1,
        onTap: () => _openAddCycle(cycle: _cycles[i]),
        onToggle: (val) => _toggleCycle(i, val),
      ),
    ),
  );
}

class _CycleTile extends StatelessWidget {
  final Cycle cycle;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  const _CycleTile({required this.cycle, required this.index,
                    required this.onTap, required this.onToggle});

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
          Text('Cycle $index',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15)),
          if (cycle.name.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('· ${cycle.name}',
                style: TextStyle(color: Colors.grey.shade500,
                    fontSize: 13)),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _modeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
            child: Text(cycle.modeLabel,
                style: TextStyle(color: _modeColor,
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
          const SizedBox(height: 4),
          Row(children: [
            if (cycle.mode != OperationMode.timeBased) ...[
              const Icon(Icons.water_drop, size: 14,
                  color: Color(0xFF2196F3)),
              const SizedBox(width: 4),
              Text('${cycle.targetLiters.toStringAsFixed(1)} L',
                  style: const TextStyle(color: Color(0xFF2196F3),
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 8),
            ],
            if (cycle.mode != OperationMode.literBased) ...[
              const Icon(Icons.timer_outlined, size: 14,
                  color: Colors.grey),
              const SizedBox(width: 4),
              Text('${cycle.startTimeStr} - ${cycle.endTimeStr}',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12)),
            ],
          ]),
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
