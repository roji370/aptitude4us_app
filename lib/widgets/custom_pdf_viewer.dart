import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:open_file/open_file.dart';
import '../utils/logger.dart';

class CustomPDFViewer extends StatefulWidget {
  final String filePath;
  final String userName;
  final bool showWatermark;
  /// Called once when the PDF renders successfully (for one-time-view tracking).
  final VoidCallback? onViewedCallback;

  const CustomPDFViewer({
    super.key,
    required this.filePath,
    required this.userName,
    this.showWatermark = true,
    this.onViewedCallback,
  });

  @override
  State<CustomPDFViewer> createState() => _CustomPDFViewerState();
}

class _CustomPDFViewerState extends State<CustomPDFViewer> {
  String? _errorMessage;
  bool _isLoading = true;
  bool _fileValidated = false;
  bool _hasCalledViewedCallback = false; // ensure we call it at most once
  int _retryCount = 0;
  static const int _maxRetries = 2;
  // Unique key to force PDFView rebuild on retry (works around iOS 26
  // platform-view lifecycle race where the native view isn't ready yet).
  Key _pdfViewKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _validateFile();
  }

  Future<void> _validateFile() async {
    try {
      // Check if file exists and is readable
      final file = File(widget.filePath);
      if (!await file.exists()) {
        Logger.w("CustomPDFViewer: File does not exist: ${widget.filePath}");
        setState(() {
          _errorMessage = "PDF file does not exist";
          _isLoading = false;
        });
        return;
      }

      final fileSize = await file.length();
      Logger.d("CustomPDFViewer: File size: $fileSize bytes");

      if (fileSize < 100) {
        // Arbitrary minimum size for a valid PDF
        Logger.w(
          "CustomPDFViewer: File is too small to be a valid PDF: $fileSize bytes",
        );
        setState(() {
          _errorMessage = "Invalid PDF file (file too small)";
          _isLoading = false;
        });
        return;
      }

      // Try to read the first few bytes to verify PDF signature
      try {
        final bytes = await file.openRead(0, 5).first;
        final headerStr = String.fromCharCodes(bytes);
        Logger.d("CustomPDFViewer: File header: $headerStr");

        if (!headerStr.startsWith('%PDF')) {
          Logger.w("CustomPDFViewer: File does not start with PDF signature");
          setState(() {
            _errorMessage = "Invalid PDF file format";
            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        Logger.e("CustomPDFViewer: Error reading file header: $e");
        setState(() {
          _errorMessage = "Cannot read PDF file: $e";
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _fileValidated = true;
      });
    } catch (e) {
      Logger.e("CustomPDFViewer: Error validating file: $e");
      Logger.e("CustomPDFViewer: Stack trace: ${StackTrace.current}");
      setState(() {
        _errorMessage = "Error opening PDF file: $e";
        _isLoading = false;
      });
    }
  }

  /// Retry rendering the PDF after a short delay.
  /// iOS 26 has a race condition where the native platform view isn't ready
  /// on the first attempt; a brief delay + fresh key usually resolves it.
  void _retryRender() {
    if (_retryCount >= _maxRetries) {
      Logger.w("CustomPDFViewer: Max retries reached, not retrying");
      return;
    }

    _retryCount++;
    Logger.i("CustomPDFViewer: Retrying PDF render (attempt $_retryCount/$_maxRetries)");

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
        _isLoading = true;
        _pdfViewKey = UniqueKey();
      });
    });
  }

  /// Open the PDF in the system viewer as a last-resort fallback.
  /// This ensures the user can always access the content even when the
  /// in-app PDFView widget fails on iOS 26.
  void _openInSystemViewer() {
    Logger.i("CustomPDFViewer: Opening PDF in system viewer as fallback");
    try {
      OpenFile.open(widget.filePath);
      // Fire viewed callback since the user is viewing the document
      if (!_hasCalledViewedCallback && widget.onViewedCallback != null) {
        _hasCalledViewedCallback = true;
        Logger.i('📄 PDF opened in system viewer – triggering one-time view callback');
        widget.onViewedCallback!();
      }
    } catch (e) {
      Logger.e("CustomPDFViewer: Failed to open in system viewer: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Logger.d(
          "CustomPDFViewer container size: ${constraints.maxWidth} x ${constraints.maxHeight}",
        );

        return Stack(
          children: [
            // PDF View with error handling
            Builder(
              builder: (context) {
                try {
                  if (_errorMessage != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error displaying PDF: $_errorMessage',
                            style: TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                                _isLoading = true;
                                _fileValidated = false;
                                _pdfViewKey = UniqueKey();
                              });
                              _validateFile();
                            },
                            child: const Text('Try Again'),
                          ),
                          // Fallback: open in system viewer (especially useful on iOS 26)
                          if (Platform.isIOS) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _openInSystemViewer,
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('Open in System Viewer'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  // Only show PDFView if file validation passed
                  if (!_fileValidated) {
                    return const SizedBox(); // Empty widget while validating
                  }

                  // Ensure we have valid dimensions to prevent zoom scale errors
                  if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                    Logger.w(
                      "CustomPDFViewer: Invalid container dimensions: ${constraints.maxWidth} x ${constraints.maxHeight}",
                    );
                    return const Center(child: CircularProgressIndicator());
                  }

                  // RepaintBoundary isolates the native platform view from
                  // Flutter's rendering pipeline, reducing the likelihood of
                  // iOS 26 gesture-recognizer and layout conflicts.
                  return RepaintBoundary(
                    child: SizedBox.expand(
                      child: PDFView(
                        key: _pdfViewKey,
                        filePath: widget.filePath,
                        enableSwipe: true,
                        swipeHorizontal: true,
                        autoSpacing: false,
                        pageFling: true,
                        pageSnap: true,
                        defaultPage: 0,
                        fitPolicy: FitPolicy.WIDTH,
                        preventLinkNavigation: true,
                        onRender: (pages) {
                          Logger.i("PDF rendered successfully with $pages pages");
                          setState(() {
                            _isLoading = false;
                          });
                          // Reset retry count on success
                          _retryCount = 0;
                          // One-time view: fire callback once on first successful render
                          if (!_hasCalledViewedCallback && widget.onViewedCallback != null) {
                            _hasCalledViewedCallback = true;
                            Logger.i('📄 PDF rendered – triggering one-time view callback');
                            widget.onViewedCallback!();
                          }
                        },
                        onError: (error) {
                          Logger.e('Error rendering PDF: $error');
                          Logger.e('Stack trace: ${StackTrace.current}');

                          // On iOS 26, platform view errors are often transient.
                          // Retry automatically before showing the error UI.
                          if (Platform.isIOS && _retryCount < _maxRetries) {
                            Logger.i("CustomPDFViewer: iOS error detected, auto-retrying...");
                            _retryRender();
                            return;
                          }

                          setState(() {
                            _isLoading = false;
                            _errorMessage = error.toString();
                          });
                        },
                        onPageError: (page, error) {
                          Logger.e('Error on page $page: $error');
                          Logger.e('Stack trace: ${StackTrace.current}');

                          setState(() {
                            _isLoading = false;
                            _errorMessage = "Error on page $page: $error";
                          });
                        },
                      ),
                    ),
                  );
                } on PlatformException catch (e) {
                  // Catch iOS platform view exceptions (common on iOS 26
                  // due to PDFKit lifecycle conflicts).
                  Logger.e('PlatformException in PDFView: ${e.code} – ${e.message}');

                  if (Platform.isIOS && _retryCount < _maxRetries) {
                    _retryRender();
                    return const Center(child: CircularProgressIndicator());
                  }

                  return _buildFallbackErrorWidget(
                    'Platform error displaying PDF: ${e.message}',
                  );
                } catch (e) {
                  Logger.e('Exception in PDFView creation: $e');
                  Logger.e('Stack trace: ${StackTrace.current}');

                  return _buildFallbackErrorWidget('Error displaying PDF: $e');
                }
              },
            ),

            // Loading indicator
            if (_isLoading) Center(child: CircularProgressIndicator()),

            // Watermark overlay
            if (widget.showWatermark)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Transform.rotate(
                      angle: -0.5,
                      child: Text(
                        widget.userName,
                        style: TextStyle(
                          color: Colors.black.withAlpha(
                            51,
                          ), // 0.2 opacity = 51 alpha (255 * 0.2)
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Shared error widget with system-viewer fallback for iOS.
  Widget _buildFallbackErrorWidget(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          if (Platform.isIOS) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _openInSystemViewer,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in System Viewer'),
            ),
          ],
        ],
      ),
    );
  }
}
