import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cycle.dart';
import '../providers/providers.dart';

class AddCycleScreen extends ConsumerStatefulWidget {
  final Cycle? cycle;
  const AddCycleScreen({super.key, this.cycle});

  @override
  ConsumerState<AddCycleScreen> createState() => _AddCycleScreenState();
}

class _AddCycleScreenState extends ConsumerState<AddCycleScreen> {
  final _nameController = TextEditingController();
  final _litersController = TextEditingController(text: '20.0');
  OperationMode _mode = OperationMode.timeWindowLiter;
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime   = const TimeOfDay(hour: 11, minute: 0);
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    if (widget.cycle != null) {
      final c = widget.cycle!;
      _nameController.text    = c.name;
      _litersController.text  = c.targetLiters.toString();
      _mode                   = c.mode;
      _startTime = TimeOfDay(hour: c.startHour, minute: c.startMinute);
      _endTime   = TimeOfDay(hour: c.endHour,   minute: c.endMinute);
      _enabled   = c.enabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _litersController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) setState(() {
      if (isStart) _startTime = picked; else _endTime = picked;
    });
  }

  void _save() {
    final mqtt = ref.read(mqttServiceProvider);
    final cyclesAsync = ref.read(cyclesProvider);
    final existingCycles = cyclesAsync.maybeWhen(
        data: (c) => c, orElse: () => <Cycle>[]);

    final newCycle = Cycle(
      id:           widget.cycle?.id ?? (existingCycles.length + 1),
      name:         _nameController.text,
      startHour:    _startTime.hour,
      startMinute:  _startTime.minute,
      endHour:      _endTime.hour,
      endMinute:    _endTime.minute,
      mode:         _mode,
      targetLiters: double.tryParse(_litersController.text) ?? 20.0,
      enabled:      _enabled,
    );

    final updated = List<Cycle>.from(existingCycles);
    if (widget.cycle != null) {
      final idx = updated.indexWhere((c) => c.id == widget.cycle!.id);
      if (idx >= 0) updated[idx] = newCycle; else updated.add(newCycle);
    } else {
      updated.add(newCycle);
    }

    mqtt.setCycles(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.cycle != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        title: Text(isEdit ? 'Edit Cycle' : 'Add Cycle',
            style: const TextStyle(color: Colors.black87,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(color: Color(0xFF2196F3),
                    fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(children: [
            _FieldLabel('Cycle Name (Optional)'),
            TextField(
              controller: _nameController,
              decoration: _inputDecoration('Cycle 1'),
            ),
          ]),
          const SizedBox(height: 12),

          _SectionCard(children: [
            _FieldLabel('Cycle Start Time'),
            _TimePicker(
              time: _startTime,
              onTap: () => _pickTime(true),
            ),
          ]),
          const SizedBox(height: 12),

          // Operation Mode
          _SectionCard(children: [
            _FieldLabel('Operation Mode'),
            const SizedBox(height: 8),
            Row(children: [
              _ModeCard(
                icon: Icons.water_drop,
                label: 'Liter Based',
                selected: _mode == OperationMode.literBased,
                color: const Color(0xFF2196F3),
                onTap: () => setState(() => _mode = OperationMode.literBased),
              ),
              const SizedBox(width: 8),
              _ModeCard(
                icon: Icons.access_time,
                label: 'Time Based',
                selected: _mode == OperationMode.timeBased,
                color: const Color(0xFF4CAF50),
                onTap: () => setState(() => _mode = OperationMode.timeBased),
              ),
              const SizedBox(width: 8),
              _ModeCard(
                icon: Icons.timer,
                label: 'Time Window + Liter',
                selected: _mode == OperationMode.timeWindowLiter,
                color: const Color(0xFF9C27B0),
                onTap: () => setState(
                    () => _mode = OperationMode.timeWindowLiter),
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFF2196F3), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_modeDescription,
                      style: const TextStyle(
                          color: Color(0xFF2196F3), fontSize: 12)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),

          // End time (if needed)
          if (_mode != OperationMode.literBased) ...[
            _SectionCard(children: [
              _FieldLabel('Cycle End Time'),
              _TimePicker(time: _endTime, onTap: () => _pickTime(false)),
            ]),
            const SizedBox(height: 12),
          ],

          // Target liters (if needed)
          if (_mode != OperationMode.timeBased) ...[
            _SectionCard(children: [
              _FieldLabel('Target Quantity (Liter)'),
              TextField(
                controller: _litersController,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: _inputDecoration('20.0').copyWith(
                  suffix: const Text('Liters',
                      style: TextStyle(color: Colors.grey))),
              ),
              const SizedBox(height: 8),
              Text(_modeHint,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            const SizedBox(height: 12),
          ],

          // Status
          _SectionCard(children: [
            Row(children: [
              const Text('Status',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
              const Spacer(),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeColor: const Color(0xFF4CAF50),
              ),
            ]),
            Text(_enabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                    color: _enabled
                        ? const Color(0xFF4CAF50) : Colors.grey,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 24),

          // Buttons
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  String get _modeDescription => switch (_mode) {
        OperationMode.literBased =>
            'Pump starts at configured time and stops after delivering target liters.',
        OperationMode.timeBased =>
            'Pump starts at start time and stops at end time.',
        OperationMode.timeWindowLiter =>
            'Pump stops after delivering target liters OR at end time, whichever comes first.',
      };

  String get _modeHint => switch (_mode) {
        OperationMode.literBased =>
            'Pump will stop after delivering ${_litersController.text} Liters.',
        OperationMode.timeWindowLiter =>
            'Pump will stop after delivering ${_litersController.text} Liters or at ${_endTime.format(context)} (whichever comes first).',
        _ => '',
      };

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
          blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
  );
}

class _TimePicker extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;
  const _TimePicker({required this.time, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Text(time.format(context),
            style: const TextStyle(fontSize: 15)),
        const Spacer(),
        const Icon(Icons.access_time, color: Colors.grey, size: 20),
      ]),
    ),
  );
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ModeCard({required this.icon, required this.label,
                   required this.selected, required this.color,
                   required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 2)),
        child: Column(children: [
          Icon(icon, color: selected ? color : Colors.grey, size: 24),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? color : Colors.grey)),
        ]),
      ),
    ),
  );
}
