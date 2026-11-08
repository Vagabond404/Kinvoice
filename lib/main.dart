import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/search/presentation/screens/search_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KinvoiceApp());
}

/// Root application widget for Kinvoice.
/// Configures Material 3 ThemeData with system-driven automatic Light & Dark switching.
class KinvoiceApp extends StatelessWidget {
  const KinvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kinvoice',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const RootNavigationShell(),
    );
  }
}

/// Root navigation shell hosting the 3 core tabs: Timeline, Ask Memory, and Settings.
class RootNavigationShell extends StatefulWidget {
  const RootNavigationShell({super.key});

  @override
  State<RootNavigationShell> createState() => _RootNavigationShellState();
}

class _RootNavigationShellState extends State<RootNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mic_rounded),
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'Timeline',
            tooltip: 'Recordings Timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_rounded),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Ask Memory',
            tooltip: 'Search & Ask Memory',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
            tooltip: 'Models & Preferences',
          ),
        ],
      ),
    );
  }
}
