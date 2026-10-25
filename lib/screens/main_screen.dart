import 'package:flutter/material.dart';
import 'assigned_courses_screen.dart';
import 'profile_screen.dart';
import '../widgets/custom_bottom_navigation.dart';
import '../utils/tab_notifier.dart';

/// A persistent shell screen that hosts the bottom navigation bar
/// and uses IndexedStack to keep Home and Profile screens alive,
/// eliminating loading screens when switching between tabs.
class MainScreen extends StatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;

  // Keep screens alive using keys
  final List<Widget> _screens = const [
    AssignedCoursesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    // Sync the global notifier with this screen's initial index.
    // Ensures consistency on re-login (new MainScreen, possibly different tab).
    activeTabNotifier.value = widget.initialIndex;
    activeTabNotifier.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  /// Called when a sub-screen sets activeTabNotifier.value via
  /// CustomBottomNavigation.handleNavigation().
  void _onTabChanged() {
    final newIndex = activeTabNotifier.value;
    if (_selectedIndex != newIndex) {
      setState(() => _selectedIndex = newIndex);
    }
  }

  void _onTabTapped(int index) {
    if (_selectedIndex == index) return; // Already on this tab
    activeTabNotifier.value = index; // Keep notifier in sync
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: CustomBottomNavigation(
        selectedIndex: _selectedIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
