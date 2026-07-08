import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/dashboard_screen.dart';
import 'screens/cycles_screen.dart';
import 'screens/manual_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'providers/providers.dart';
void main() {
  runApp(const ProviderScope(child: SWCApp()));
}
class SWCApp extends StatelessWidget {
  const SWCApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Water Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 2,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
      ),
      home: const MainShell(),
    );
  }
}
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}
class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;
  final _screens = const [
    DashboardScreen(),
    CyclesScreen(),
    ManualScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];
  @override
  void initState() {
    super.initState();
    // Keep screen awake while app is in foreground — testing/monitoring
    // an active irrigation cycle shouldn't be interrupted by screen sleep.
    WakelockPlus.enable();
    // Auto-connect to the active transport (local SoftAP by default,
    // or cloud/MQTT if the user switched modes in Settings) on startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final device = ref.read(deviceServiceProvider);
      await device.connect();
    });
  }
  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.loop),      label: 'Cycles'),
          NavigationDestination(icon: Icon(Icons.pan_tool),  label: 'Manual'),
          NavigationDestination(icon: Icon(Icons.history),   label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings),  label: 'Settings'),
        ],
      ),
    );
  }
}
