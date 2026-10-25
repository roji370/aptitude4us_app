import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/apk_download_service.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';

/// Download state for the in-app APK update flow.
enum _UpdateState { idle, downloading, downloaded, installing, error }

/// Force Update Screen — downloads and installs the APK from Firebase Storage
/// on Android, or redirects to the App Store on iOS.
class ForceUpdateScreen extends StatefulWidget {
  final String currentVersion;
  final String requiredVersion;
  final String? updateMessage;
  final String? apkDownloadPath;

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
  _UpdateState _state = _UpdateState.idle;
  double _downloadProgress = 0.0;
  String? _downloadedFilePath;
  String? _errorMessage;
  late final ApkDownloadService _apkService;

  @override
  void initState() {
    super.initState();
    _apkService = ApkDownloadService();
  }

  // ---------------------------------------------------------------------------
  // Update handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleUpdate() async {
    // On iOS (or if no APK path is configured), fall back to the App Store.
    if (!Platform.isAndroid || widget.apkDownloadPath == null || widget.apkDownloadPath!.isEmpty) {
      await _openStore();
      return;
    }

    // Android in-app download flow
    await _downloadApk();
  }

  Future<void> _downloadApk() async {
    setState(() {
      _state = _UpdateState.downloading;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final filePath = await _apkService.downloadApk(
        storagePath: widget.apkDownloadPath!,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
      );

      if (!mounted) return;

      if (filePath == null) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = 'Download failed. Please check your internet connection and try again.';
        });
        return;
      }

      setState(() {
        _state = _UpdateState.downloaded;
        _downloadedFilePath = filePath;
      });

      // Automatically trigger install
      await _installApk();
    } catch (e) {
      Logger.e('Error downloading APK: $e');
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = 'Download failed: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _installApk() async {
    if (_downloadedFilePath == null) return;

    setState(() => _state = _UpdateState.installing);

    try {
      final success = await _apkService.installApk(_downloadedFilePath!);

      if (!mounted) return;

      if (success) {
        // The OS package installer is now open. Exit the old app so that
        // when the user finishes installing, the NEW version launches fresh
        // instead of returning to this (old) process which would loop.
        Logger.i('Install intent launched — closing old app process');
        await Future.delayed(const Duration(milliseconds: 500));
        SystemNavigator.pop();
        return;
      }

      setState(() {
        _state = _UpdateState.error;
        _errorMessage = 'Could not launch the installer. Please try again.';
      });
    } catch (e) {
      Logger.e('Error installing APK: $e');
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = 'Installation failed: ${e.toString()}';
        });
      }
    }
  }

  /// Fallback: open the Play Store / App Store.
  Future<void> _openStore() async {
    setState(() => _state = _UpdateState.downloading);
    try {
      final url = 'https://play.google.com/store/apps/details?id=com.briffini.academy';
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Logger.e('Could not launch store URL: $url');
      }
    } catch (e) {
      Logger.e('Error opening store: $e');
    } finally {
      if (mounted) setState(() => _state = _UpdateState.idle);
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  /// Returns the appropriate icon for the current state.
  Widget _buildButtonIcon() {
    switch (_state) {
      case _UpdateState.idle:
        return const Icon(Icons.download_rounded, size: 24);
      case _UpdateState.downloading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: _downloadProgress > 0 ? _downloadProgress : null,
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        );
      case _UpdateState.downloaded:
      case _UpdateState.installing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        );
      case _UpdateState.error:
        return const Icon(Icons.refresh_rounded, size: 24);
    }
  }

  /// Returns the button label text for the current state.
  String _buttonLabel() {
    switch (_state) {
      case _UpdateState.idle:
        // If no APK path, show Play Store label
        if (!Platform.isAndroid || widget.apkDownloadPath == null || widget.apkDownloadPath!.isEmpty) {
          return 'Update on Play Store';
        }
        return 'Download Update';
      case _UpdateState.downloading:
        final pct = (_downloadProgress * 100).toInt();
        return pct > 0 ? 'Downloading... $pct%' : 'Starting Download...';
      case _UpdateState.downloaded:
        return 'Opening Installer...';
      case _UpdateState.installing:
        return 'Installing...';
      case _UpdateState.error:
        return 'Retry Download';
    }
  }

  /// Whether the main button should be disabled.
  bool get _isButtonBusy =>
      _state == _UpdateState.downloading ||
      _state == _UpdateState.downloaded ||
      _state == _UpdateState.installing;

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
              AppColors.primary,
              AppColors.primaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Update icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    size: 80,
                    color: AppColors.primary,
                  ),
                ),

                const SizedBox(height: 40),

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

                Text(
                  widget.updateMessage ??
                      'A new version of Xfini Academy is available. Please update to continue.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Version info card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
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
                              color: Colors.white.withValues(alpha: 0.8),
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
                              color: Colors.white.withValues(alpha: 0.8),
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

                const SizedBox(height: 32),

                // Download progress bar (visible during download)
                if (_state == _UpdateState.downloading && _downloadProgress > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            minHeight: 8,
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_downloadProgress * 100).toInt()}% downloaded',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Error message
                if (_state == _UpdateState.error && _errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.9),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Main action button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isButtonBusy ? null : _handleUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                      elevation: 8,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildButtonIcon(),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _buttonLabel(),
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'This update includes important improvements\nand new features for a better experience.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
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
