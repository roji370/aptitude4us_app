import 'package:flutter/foundation.dart';

/// Global tab selector for the MainScreen bottom navigation.
///
/// Sub-screens write to this notifier when they want to switch tabs
/// (via [CustomBottomNavigation.handleNavigation]), and MainScreen
/// listens to it. This replaces the old pushAndRemoveUntil approach
/// that destroyed the entire navigation stack.
///
/// Reset to 0 on sign-out.
final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);
