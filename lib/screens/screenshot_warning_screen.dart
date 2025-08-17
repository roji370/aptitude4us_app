import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';

/// Screen shown when user takes their first screenshot
///
/// This screen warns the user that taking screenshots is not allowed
/// and that further attempts will result in access being blocked
class ScreenshotWarningScreen extends StatelessWidget {
  final VoidCallback? onContinue;
  final VoidCallback? onGoBack;

  const ScreenshotWarningScreen({Key? key, this.onContinue, this.onGoBack})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    Logger.w('📱 Showing screenshot warning screen');

    return Scaffold(
      backgroundColor: Colors.red[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Warning Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 80,
                  color: Colors.red[600],
                ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                'Screenshot Detected!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Warning Message
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[300]!, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      'Screenshots are not allowed',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'This content is protected and screenshots are prohibited to maintain security and protect intellectual property.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red[600],
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Warning: If you attempt to take another screenshot, your access to this content will be blocked.',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.red[700],
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Action Buttons
              Column(
                children: [
                  // Continue Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Logger.i('📱 User acknowledged screenshot warning');
                        if (onContinue != null) {
                          onContinue!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'I Understand - Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Go Back Button (Optional)
                  if (onGoBack != null)
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Logger.i(
                            '📱 User chose to go back from screenshot warning',
                          );
                          onGoBack!();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Go Back',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 24),

              // Additional Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This is your first and only warning. Please respect our content protection policies.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
