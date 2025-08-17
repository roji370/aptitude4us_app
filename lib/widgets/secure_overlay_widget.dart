import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/responsive_helper.dart';

/// A widget that applies iOS-specific screen capture protection
/// by overlaying a secure UITextField when viewing sensitive content
class SecureOverlayWidget extends StatefulWidget {
  final Widget child;
  final bool enableProtection;

  const SecureOverlayWidget({
    super.key,
    required this.child,
    this.enableProtection = true,
  });

  @override
  State<SecureOverlayWidget> createState() => _SecureOverlayWidgetState();
}

class _SecureOverlayWidgetState extends State<SecureOverlayWidget> {
  bool _isProtectionActive = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableProtection) {
      _enableProtection();
    }
  }

  @override
  void didUpdateWidget(SecureOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableProtection != oldWidget.enableProtection) {
      if (widget.enableProtection) {
        _enableProtection();
      } else {
        _disableProtection();
      }
    }
  }

  @override
  void dispose() {
    _disableProtection();
    super.dispose();
  }

  void _enableProtection() {
    if (!ResponsiveHelper.isIOS() || _isProtectionActive) return;

    const MethodChannel('flutter.native/screenProtection')
        .invokeMethod('secureView', true)
        .then((_) {
          setState(() {
            _isProtectionActive = true;
          });
        })
        .catchError((error) {
          debugPrint('Error enabling secure view: $error');
        });
  }

  void _disableProtection() {
    if (!ResponsiveHelper.isIOS() || !_isProtectionActive) return;

    const MethodChannel('flutter.native/screenProtection')
        .invokeMethod('secureView', false)
        .then((_) {
          setState(() {
            _isProtectionActive = false;
          });
        })
        .catchError((error) {
          debugPrint('Error disabling secure view: $error');
        });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
