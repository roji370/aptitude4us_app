import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Modal consent dialog shown the first time a student opens a recorded
/// lecture. The dialog is intentionally short, privacy-forward and **not
/// dismissible** — keeping the camera on is a required part of watching the
/// lecture, so the only way out of the dialog is to tap "Enable Camera".
///
/// The dialog suppresses both:
/// * Tap-outside dismissal (`barrierDismissible: false`).
/// * Android system back / predictive back gesture (`PopScope(canPop: false)`).
///
/// Returns `true` when the user accepts. The only way it can ever resolve to
/// `false` is if the dialog is closed programmatically by the host (e.g. the
/// lecture screen is popped out of the navigation stack while the dialog is
/// up); the [LearnerPresenceVideoWrapper] then keeps the video blocked.
class LearnerPresenceConsentDialog extends StatelessWidget {
  const LearnerPresenceConsentDialog({super.key});

  /// Shows the dialog and resolves with the user's choice.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LearnerPresenceConsentDialog(),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.primary;
    // PopScope(canPop: false) blocks Android back / predictive back gesture
    // so the student cannot bypass the camera requirement by hitting back.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.videocam_rounded, color: brand),
            SizedBox(width: 10),
            Expanded(child: Text('Camera Required')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To watch this lecture, the app shows a small self-preview from '
              'your front camera in the corner of the screen.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brand.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: brand),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The preview stays on your device — it is never '
                      'recorded or uploaded.',
                      style: TextStyle(
                        fontSize: 13,
                        color: brand,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Enable Camera',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
