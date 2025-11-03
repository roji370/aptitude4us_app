import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy'), elevation: 0),
      body: SingleChildScrollView(
        padding: ResponsiveHelper.getScreenHorizontalPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 16.0,
                regular: 20.0,
                pro: 24.0,
                large: 28.0,
                extraLarge: 32.0,
              ),
            ),

            Text(
              'Privacy Policy for Xfini Academy',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),

            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 16.0,
                regular: 20.0,
                pro: 24.0,
                large: 28.0,
                extraLarge: 32.0,
              ),
            ),

            Text(
              'Last updated: ${DateTime.now().toString().substring(0, 10)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 24.0,
                regular: 28.0,
                pro: 32.0,
                large: 36.0,
                extraLarge: 40.0,
              ),
            ),

            _buildSection(
              context,
              'Information We Collect',
              'We collect information you provide directly to us, such as when you create an account, access course content, or communicate with us. This may include your name, email address, profile information, and learning progress data.',
            ),

            _buildSection(
              context,
              'How We Use Your Information',
              'We use the information we collect to provide, maintain, and improve our educational services, personalize your learning experience, communicate with you about your account and courses, and ensure the security of our platform.',
            ),

            _buildSection(
              context,
              'Information Sharing',
              'We do not sell, trade, or otherwise transfer your personal information to third parties without your consent, except as described in this policy or as required by law.',
            ),

            _buildSection(
              context,
              'Data Security',
              'We implement appropriate security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. Your data is encrypted during transmission and storage.',
            ),

            _buildSection(
              context,
              'Push Notifications',
              'With your consent, we may send you push notifications about new content, messages, and important updates. You can disable these notifications at any time in your device settings or app preferences.',
            ),

            _buildSection(
              context,
              'Your Rights',
              'You have the right to access, update, or delete your personal information. You may also request a copy of your data or object to certain uses of your information. Contact us to exercise these rights.',
            ),

            _buildSection(
              context,
              'Contact Us',
              'If you have any questions about this Privacy Policy, please contact us at support@xfini.academy or through the app\'s support feature.',
            ),

            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 40.0,
                regular: 44.0,
                pro: 48.0,
                large: 52.0,
                extraLarge: 56.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(
          height: ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 8.0,
            regular: 10.0,
            pro: 12.0,
            large: 14.0,
            extraLarge: 16.0,
          ),
        ),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
        SizedBox(
          height: ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 20.0,
            regular: 24.0,
            pro: 28.0,
            large: 32.0,
            extraLarge: 36.0,
          ),
        ),
      ],
    );
  }
}
