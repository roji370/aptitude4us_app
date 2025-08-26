import 'package:url_launcher/url_launcher.dart';
import '../utils/logger.dart';

/// Service for launching WhatsApp with specific phone numbers
class WhatsAppService {
  /// Admin contact phone number
  static const String adminPhoneNumber = '+353894196175';

  /// Launch WhatsApp with a specific phone number and optional message
  static Future<bool> openWhatsAppChat({
    String? phoneNumber,
    String? message,
  }) async {
    try {
      final phone = phoneNumber ?? adminPhoneNumber;
      // Remove all non-digit characters except the leading +
      final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');

      Logger.i('🟢 Opening WhatsApp chat with: $cleanPhone');

      // Create WhatsApp URL
      String whatsappUrl = 'https://wa.me/$cleanPhone';

      // Add message if provided
      if (message != null && message.isNotEmpty) {
        final encodedMessage = Uri.encodeComponent(message);
        whatsappUrl += '?text=$encodedMessage';
      }

      Logger.i('🔗 WhatsApp URL: $whatsappUrl');

      final Uri uri = Uri.parse(whatsappUrl);

      // Check if the URL can be launched
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (launched) {
          Logger.i('✅ WhatsApp opened successfully');
          return true;
        } else {
          Logger.e('❌ Failed to launch WhatsApp');
          return false;
        }
      } else {
        Logger.e('❌ Cannot launch WhatsApp URL: $whatsappUrl');
        return false;
      }
    } catch (e) {
      Logger.e('❌ Error opening WhatsApp: $e');
      return false;
    }
  }

  /// Launch WhatsApp with admin contact
  static Future<bool> openAdminChat({String? message}) async {
    String defaultMessage =
        message ??
        'Hello, I need assistance with my account access. Please help me resolve this issue.';

    return await openWhatsAppChat(
      phoneNumber: adminPhoneNumber,
      message: defaultMessage,
    );
  }

  /// Launch WhatsApp with admin for screenshot violation
  static Future<bool> openAdminChatForScreenshotViolation() async {
    const message =
        'Hello, my account access has been suspended due to screenshot violations. '
        'I would like to request a review of my account and discuss restoring my access. '
        'Please help me resolve this issue.';

    return await openAdminChat(message: message);
  }

  /// Get formatted admin phone number for display
  static String getFormattedAdminPhone() {
    return '+353 89 419 6175';
  }

  /// Get clean admin phone number for WhatsApp URL
  static String getCleanAdminPhone() {
    return adminPhoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
  }
}
