import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';

/// Screen shown when user's access is blocked due to screenshot violations
///
/// This screen informs the user that their access has been blocked due to
/// taking multiple screenshots of protected content
class ScreenshotBlockedScreen extends StatelessWidget {
  final VoidCallback? onContactSupport;
  final VoidCallback? onGoBack;

  const ScreenshotBlockedScreen({
    Key? key,
    this.onContactSupport,
    this.onGoBack,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Logger.e('📱 Showing screenshot blocked access screen');

    return Scaffold(
      backgroundColor: Colors.red[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Blocked Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.block, size: 80, color: Colors.red[600]),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                'Access Blocked',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Blocked Message
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red[300]!, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Your access has been suspended',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'You have violated our content protection policy by taking multiple screenshots of protected material.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

                    // Violation Details
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.gavel,
                                color: Colors.red[600],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Policy Violation',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '• Screenshots of protected content are strictly prohibited\n'
                            '• You were warned after your first attempt\n'
                            '• Multiple violations result in access suspension',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red[600],
                              height: 1.4,
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
                  // Contact Support Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Logger.i(
                          '📱 User requesting support for screenshot violation',
                        );
                        if (onContactSupport != null) {
                          onContactSupport!();
                        } else {
                          _showContactInfo(context);
                        }
                      },
                      icon: const Icon(Icons.support_agent, size: 20),
                      label: const Text(
                        'Contact Support',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Go Back Button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Logger.i('📱 User going back from blocked screen');
                        if (onGoBack != null) {
                          onGoBack!();
                        } else {
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Go Back to Main Menu',
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

              // Additional Information
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange[600],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'If you believe this is an error, please contact our support team for assistance.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
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

  /// Show contact information dialog
  void _showContactInfo(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Contact Support'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please contact our support team for assistance with access issues:',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Text(
                  'Email: support@briffini.com',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 8),
                Text(
                  'Please include details about when this occurred and your account information.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}
