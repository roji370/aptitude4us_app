import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';

/// A utility class for handling platform-specific page transitions and navigation
class AdaptiveNavigation {
  /// Navigate to a new screen with platform-specific animation
  static Future<T?> navigateTo<T>({
    required BuildContext context,
    required Widget page,
    bool fullscreenDialog = false,
    bool replace = false,
  }) {
    final route = _createPlatformRoute<T>(
      page: page,
      fullscreenDialog: fullscreenDialog,
    );

    if (replace) {
      return Navigator.of(context).pushReplacement(route);
    } else {
      return Navigator.of(context).push(route);
    }
  }

  /// Push a named route with platform-specific animation
  static Future<T?> pushNamed<T>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamed<T>(routeName, arguments: arguments);
  }

  /// Replace current screen with a new one
  static Future<T?> replace<T, TO>({
    required BuildContext context,
    required Widget page,
    TO? result,
  }) {
    final route = _createPlatformRoute<T>(page: page);
    return Navigator.of(context).pushReplacement(route, result: result);
  }

  /// Pop to a specific route and then push a new route
  static Future<T?> popAndPushNamed<T, TO>(
    BuildContext context,
    String routeName, {
    TO? result,
    Object? arguments,
  }) {
    return Navigator.of(
      context,
    ).popAndPushNamed<T, TO>(routeName, result: result, arguments: arguments);
  }

  /// Clear the navigation stack and set a new screen as root
  static Future<T?> pushAndRemoveUntil<T>(
    BuildContext context,
    Widget page, {
    bool Function(Route<dynamic>)? predicate,
  }) {
    final route = _createPlatformRoute<T>(page: page);
    return Navigator.of(
      context,
    ).pushAndRemoveUntil<T>(route, predicate ?? (route) => false);
  }

  /// Create a platform-specific route
  static Route<T> _createPlatformRoute<T>({
    required Widget page,
    bool fullscreenDialog = false,
  }) {
    if (Platform.isIOS) {
      // iOS-style slide transition with swipe-to-go-back gesture
      return CupertinoPageRoute<T>(
        builder: (context) => page,
        fullscreenDialog: fullscreenDialog,
      );
    } else {
      // Android-style transition
      return _createAndroidRoute<T>(
        page: page,
        fullscreenDialog: fullscreenDialog,
      );
    }
  }

  /// Create an Android-specific page transition
  static Route<T> _createAndroidRoute<T>({
    required Widget page,
    bool fullscreenDialog = false,
  }) {
    // If it's a fullscreen dialog, use a different animation
    if (fullscreenDialog) {
      return PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOut;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        fullscreenDialog: true,
      );
    } else {
      // Standard Material route with custom transition
      return PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutQuad;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          // Fade + slide for Android
          return SlideTransition(
            position: animation.drive(tween),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      );
    }
  }

  /// Create a hero transition between screens
  static Widget createHeroDestination({
    required BuildContext context,
    required String tag,
    required Widget child,
  }) {
    return Hero(
      tag: tag,
      flightShuttleBuilder: (
        BuildContext flightContext,
        Animation<double> animation,
        HeroFlightDirection flightDirection,
        BuildContext fromHeroContext,
        BuildContext toHeroContext,
      ) {
        return Material(color: Colors.transparent, child: toHeroContext.widget);
      },
      child: child,
    );
  }
}
