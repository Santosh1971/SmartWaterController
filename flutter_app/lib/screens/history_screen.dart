import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/providers.dart';
import '../models/history_entry.dart';
import '../models/cycle.dart';
import '../services/mqtt_service.dart';

const String _kHistoryCacheKey = 'cached_history';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _filter = 'All';
  DateTime _date = DateTime.now();
  List<HistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mqttServiceProvider).getHistory();
      ref.read(mqttServiceProvider).historyStream.listen((entries) {
        if (mounted) setState(() { _entries = entries; _loading = false; });
        _saveToCache(entries);
      });
      // Timeout loading after 3 seconds — fall back to whatever we have (cache or empty)
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _loading) setState(() => _loading = false);
      });
    });
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistoryCacheKey);
    if (raw == null || !mounted) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted && _entries.isEmpty) {
        setState(() { _entries = list; _loading = false; });
      }
    } catch (_) {
      // Corrupt cache — ignore, MQTT will repopulate
    }
  }

  Future<void> _saveToCache(List<HistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_kHistoryCacheKey, raw);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterEntries(_entries);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        title: const Text('History',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.black87),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            _FilterTab('All',    selected: _filter == 'All',
                onTap: () => setState(() => _filter = 'All')),
            const SizedBox(width: 8),
            _FilterTab('Auto',   selected: _filter == 'Auto',
                onTap: () => setState(() => _filter = 'Auto')),
            const SizedBox(width: 8),
            _FilterTab('Manual', selected: _filter == 'Manual',
                onTap: () => setState(() => _filter = 'Manual')),
          ]),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() =>
                  _date = _date.subtract(const Duration(days: 1))),
            ),
            Expanded(
              child: Center(
                child: Text(DateFormat('d MMM yyyy').format(_date),
                    style: const TextStyle(fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _date.isBefore(DateTime.now().subtract(
                  const Duration(days: 1)))
                  ? () => setState(
                        () => _date = _date.add(const Duration(days: 1)))
                  : null,
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: Color(0xFF2196F3)))
              : filtered.isEmpty
                  ? _buildEmpty()
                  : _buildList(filtered),
        ),
        if (!_loading && filtered.isNotEmpty)
          Builder(builder: (_) {
            final totalLiters = filtered.fold<double>(
                0, (sum, e) => sum + e.litersDelivered);
            final totalCycles = filtered
                .where((e) => e.status != 'manual').length;
            return Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _TotalItem(label: 'Total Water',
                      value: '${totalLiters.toStringAsFixed(1)} L',
                      color: const Color(0xFF2196F3)),
                  _TotalItem(label: 'Total Cycles',
                      value: '$totalCycles',
                      color: const Color(0xFF4CAF50)),
                ],
              ),
            );
          }),
      ]),
    );
  }

  List<HistoryEntry> _filterEntries(List<HistoryEntry> entries) {
    return entries.where((e) {
      final sameDay = e.dateTime.day == _date.day &&
          e.dateTime.month == _date.month &&
          e.dateTime.year == _date.year;
      if (!sameDay) return false;
      if (_filter == 'Manual') return e.status == 'manual';
      if (_filter == 'Auto')   return e.status != 'manual';
      return true;
    }).toList();
  }

  Widget _buildEmpty() => const Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.history, size: 64, color: Colors.grey),
      SizedBox(height: 16),
      Text('No history for this date',
          style: TextStyle(color: Colors.grey, fontSize: 16)),
    ]),
  );

  Widget _buildList(List<HistoryEntry> entries) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (_, i) => _HistoryTile(entry: entries[i]),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterTab(this.label, {required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2196F3) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: selected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w500)),
    ),
  );
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryTile({required this.entry});

  Color get _statusColor => switch (entry.status) {
        'completed' => const Color(0xFF4CAF50),
        'manual'    => const Color(0xFF2196F3),
        'paused'    => const Color(0xFFFF9800),
        _           => Colors.grey,
      };

  String get _modeName => switch (entry.mode) {
        OperationMode.literBased      => 'Liter Based',
        OperationMode.timeBased       => 'Time Based',
        OperationMode.timeWindowLiter => 'Time Window + Liter',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        SizedBox(
          width: 60,
          child: Text(DateFormat('hh:mm a').format(entry.dateTime),
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.cycleName.isEmpty
              ? (entry.status == 'manual'
                  ? 'Manual Use' : 'Cycle ${entry.cycleId} ($_modeName)')
              : '${entry.cycleName} ($_modeName)',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 2),
          Text(entry.status[0].toUpperCase() + entry.status.substring(1),
              style: TextStyle(color: _statusColor, fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${entry.litersDelivered.toStringAsFixed(1)} L',
              style: const TextStyle(fontWeight: FontWeight.bold,
                  color: Color(0xFF2196F3))),
          Text(entry.durationStr,
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ]),
      ]),
    );
  }
}

class _TotalItem extends StatelessWidget {
  final String label, value;
  final Color color;
  const _TotalItem({required this.label, required this.value,
                    required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold,
        fontSize: 18)),
  ]);
}
