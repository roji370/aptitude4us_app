import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../utils/logger.dart';
import '../services/apk_download_service.dart';
import '../services/version_check_service.dart';

class ForceUpdateScreen extends StatefulWidget {
  final String currentVersion;
  final String requiredVersion;
  final String? updateMessage;
  final String? apkDownloadPath; // Firebase Storage path for APK

  const ForceUpdateScreen({
    super.key,
    required this.currentVersion,
    required this.requiredVersion,
    this.updateMessage,
    this.apkDownloadPath,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  final ApkDownloadService _apkDownloadService = ApkDownloadService();
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  Future<void> _handleUpdate() async {
    if (Platform.isAndroid && widget.apkDownloadPath != null && widget.apkDownloadPath!.isNotEmpty) {
      // Download APK for Android users
      await _downloadAndInstallApk();
    } else if (Platform.isIOS) {
      // Open App Store for iOS users
      await _openAppStore();
    } else {
      // Fallback to Play Store if no APK path provided
      await _openPlayStore();
    }
  }

  Future<void> _downloadAndInstallApk() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Preparing download...';
    });

    try {
      final apkPath = widget.apkDownloadPath!;
      Logger.i('📥 Starting APK download from: $apkPath');

      // Check storage space
      final hasSpace = await _apkDownloadService.hasEnoughStorage();
      if (!hasSpace) {
        setState(() {
          _statusMessage = 'Not enough storage space';
          _isDownloading = false;
        });
        _showErrorDialog('Insufficient Storage', 
          'Please free up some space and try again.');
        return;
      }

      setState(() {
        _statusMessage = 'Downloading update...';
      });

      // Download and install the APK
      final success = await _apkDownloadService.downloadAndInstall(
        storagePath: apkPath,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress;
            _statusMessage = 'Downloading ${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      if (success) {
        setState(() {
          _statusMessage = 'Installation started...';
        });
        Logger.i('✅ APK installation initiated');
        // Note: The app will be closed when user approves installation
      } else {
        setState(() {
          _statusMessage = 'Download failed';
          _isDownloading = false;
        });
        _showErrorDialog('Download Failed', 
          'Failed to download or install the update. Please try again.');
      }
    } catch (e) {
      Logger.e('❌ Error during APK download: $e');
      setState(() {
        _statusMessage = 'Error occurred';
        _isDownloading = false;
      });
      _showErrorDialog('Update Error', 
        'An error occurred while updating. Please try again.');
    }
  }

  Future<void> _openAppStore() async {
    try {
      // Replace with your actual App Store ID
      final url = 'https://apps.apple.com/app/id1234567890';
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Logger.e('Could not launch App Store URL: $url');
      }
    } catch (e) {
      Logger.e('Error opening App Store: $e');
    }
  }

  Future<void> _openPlayStore() async {
    try {
      final url = 'https://play.google.com/store/apps/details?id=com.briffini.academy';
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Logger.e('Could not launch Play Store URL: $url');
      }
    } catch (e) {
      Logger.e('Error opening Play Store: $e');
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF323483),
              Color(0xFF4A4BA8),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App logo or update icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    size: 80,
                    color: Color(0xFF323483),
                  ),
                ),

                const SizedBox(height: 40),

                // Main heading
                Text(
                  'Update Required',
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Description
                Text(
                  widget.updateMessage ??
                      'A new version of Briffini Academy is available. Please update to continue using the app.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Version info card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Current Version:',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                          Text(
                            widget.currentVersion,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Required Version:',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                          Text(
                            widget.requiredVersion,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Download progress indicator (shown when downloading)
                if (_isDownloading) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Update button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isDownloading ? null : _handleUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF323483),
                      disabledBackgroundColor: Colors.white.withOpacity(0.5),
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isDownloading)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF323483)),
                            ),
                          )
                        else
                          const Icon(
                            Icons.download_rounded,
                            size: 24,
                          ),
                        const SizedBox(width: 12),
                        Text(
                          _isDownloading ? 'Downloading...' : 'Update Now',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Info text
                Text(
                  'This update includes important improvements\nand new features for a better experience.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.7),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

