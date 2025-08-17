import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../utils/logger.dart';

class CustomPDFViewer extends StatefulWidget {
  final String filePath;
  final String userName;
  final bool showWatermark;

  const CustomPDFViewer({
    super.key,
    required this.filePath,
    required this.userName,
    this.showWatermark = true,
  });

  @override
  State<CustomPDFViewer> createState() => _CustomPDFViewerState();
}

class _CustomPDFViewerState extends State<CustomPDFViewer> {
  String? _errorMessage;
  bool _isLoading = true;
  bool _fileValidated = false;

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
                              });
                              _validateFile();
                            },
                            child: const Text('Try Again'),
                          ),
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

                  return SizedBox.expand(
                    child: PDFView(
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
                      },
                      onError: (error) {
                        Logger.e('Error rendering PDF: $error');
                        Logger.e('Stack trace: ${StackTrace.current}');

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
                  );
                } catch (e) {
                  Logger.e('Exception in PDFView creation: $e');
                  Logger.e('Stack trace: ${StackTrace.current}');

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error displaying PDF: $e',
                          style: TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
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
}
