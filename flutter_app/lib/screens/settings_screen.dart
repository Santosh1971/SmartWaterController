import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'local_setup_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(deviceStatusProvider);
    final connectedAsync = ref.watch(deviceConnectedProvider);
    final mode = ref.watch(transportModeProvider);
    final isConnected = connectedAsync.maybeWhen(data: (c) => c, orElse: () => false);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Settings',
            style: TextStyle(color: Colors.black87,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // Device status card -- reflects whichever transport is active,
          // not specifically MQTT (that's what deviceConnectedProvider is for).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isConnected ? const Color(0xFFE8F5E9) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isConnected
                    ? const Color(0xFF4CAF50) : Colors.grey.shade200),
            ),
            child: Row(children: [
              Icon(isConnected ? Icons.check_circle : Icons.error_outline,
                  color: isConnected ? const Color(0xFF4CAF50) : Colors.grey,
                  size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isConnected ? 'Device Online' : 'Device Offline',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isConnected
                          ? const Color(0xFF4CAF50) : Colors.grey)),
                statusAsync.maybeWhen(
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s.deviceId} • Firmware ${s.firmware}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                      Text('WiFi: ${s.wifiRssi} dBm • RTC: ${s.rtcDate} ${s.rtcTime}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  orElse: () => const SizedBox(),
                ),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // Connection mode -- manual switch between the device's own
          // SoftAP (works with no internet) and the cloud/MQTT broker
          // (works over the internet once the device is provisioned).
          _SettingsSection(title: 'Connection Mode', items: [
            _ModeTile(
              icon: Icons.wifi_tethering,
              color: const Color(0xFF2196F3),
              title: 'Local (Device WiFi)',
              subtitle: 'Connect directly to the device\'s own WiFi network — works with no internet',
              selected: mode == TransportMode.local,
              onTap: () async {
                await ref.read(transportModeProvider.notifier).setMode(TransportMode.local);
                await ref.read(deviceServiceProvider).connect();
              },
            ),
            _ModeTile(
              icon: Icons.cloud,
              color: const Color(0xFF4CAF50),
              title: 'Cloud (MQTT)',
              subtitle: 'Connect over the internet via the MQTT broker',
              selected: mode == TransportMode.cloud,
              onTap: () async {
                await ref.read(transportModeProvider.notifier).setMode(TransportMode.cloud);
                await ref.read(deviceServiceProvider).connect();
              },
            ),
          ]),
          const SizedBox(height: 16),

          // Local device setup (formerly BLE) -- WiFi/MQTT provisioning,
          // RTC sync, calibration, relay test, factory reset. Always uses
          // the local transport regardless of the mode switch above, since
          // provisioning inherently requires being on the device's WiFi.
          _SettingsSection(title: 'Device Setup', items: [
            _SettingsTile(
              icon: Icons.settings_ethernet,
              color: const Color(0xFF2196F3),
              title: 'Local Device Setup',
              subtitle: 'Configure WiFi, MQTT, RTC, calibration via the device\'s WiFi',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const LocalSetupScreen())),
            ),
          ]),
          const SizedBox(height: 16),

          // Connection info
          _SettingsSection(title: 'Connection Info', items: [
            _InfoTile(
              icon: Icons.cloud,
              color: const Color(0xFF4CAF50),
              title: 'MQTT Broker',
              value: 'mqtt.grty.co.in:1883',
            ),
            _InfoTile(
              icon: Icons.wifi_tethering,
              color: const Color(0xFF2196F3),
              title: 'Local Device Address',
              value: '192.168.4.1',
            ),
            _InfoTile(
              icon: Icons.devices,
              color: const Color(0xFF9C27B0),
              title: 'Device ID',
              value: 'SWC_001',
            ),
            statusAsync.maybeWhen(
              data: (s) => _InfoTile(
                icon: Icons.signal_wifi_4_bar,
                color: const Color(0xFF2196F3),
                title: 'WiFi Signal',
                value: '${s.wifiRssi} dBm',
              ),
              orElse: () => const SizedBox(),
            ),
          ]),
          const SizedBox(height: 16),

          // App info
          _SettingsSection(title: 'App Info', items: [
            _InfoTile(
              icon: Icons.info_outline,
              color: Colors.grey,
              title: 'App Version',
              value: '1.0.0',
            ),
            _InfoTile(
              icon: Icons.code,
              color: Colors.grey,
              title: 'Firmware',
              value: statusAsync.maybeWhen(
                  data: (s) => s.firmware, orElse: () => '—'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(color: Colors.grey,
                fontSize: 11, fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: items.asMap().entries.map((e) => Column(children: [
            e.value,
            if (e.key < items.length - 1)
              const Divider(height: 1, indent: 56),
          ])).expand((w) => [w]).toList(),
        ),
      ),
    ]);
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.color,
                       required this.title, required this.subtitle,
                       required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20)),
    title: Text(title,
        style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey)),
    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    onTap: onTap,
  );
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTile({required this.icon, required this.color,
                   required this.title, required this.subtitle,
                   required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20)),
    title: Text(title,
        style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey)),
    trailing: selected
        ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
        : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
    onTap: onTap,
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, value;
  const _InfoTile({required this.icon, required this.color,
                   required this.title, required this.value});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20)),
    title: Text(title,
        style: const TextStyle(fontWeight: FontWeight.w500)),
    trailing: Text(value,
        style: const TextStyle(color: Colors.grey, fontSize: 13)),
  );
}
