import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';

/// Dialog shown to first-time users requiring them to watch the exam overview
class ExamOverviewDialog extends StatelessWidget {
  final VoidCallback onProceed;
  
  const ExamOverviewDialog({
    super.key,
    required this.onProceed,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return PopScope(
      // Prevent dismissal by back button or swipe gesture
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 8,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: screenSize.width * 0.85,
              regular: 400,
              pro: 450,
              large: 500,
              extraLarge: 550,
            ),
          ),
          padding: EdgeInsets.all(
            ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 24.0,
              regular: 28.0,
              pro: 32.0,
              large: 36.0,
              extraLarge: 40.0,
            ),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: ResponsiveHelper.adaptiveFontSize(context, 80.0),
                height: ResponsiveHelper.adaptiveFontSize(context, 80.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  size: ResponsiveHelper.adaptiveFontSize(context, 48.0),
                  color: const Color(0xFF1565C0),
                ),
              ),
              
              SizedBox(
                height: ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 20.0,
                  regular: 24.0,
                ),
              ),
              
              // Title
              Text(
                'Welcome!',
                style: GoogleFonts.inter(
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 24.0),
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF171A1F),
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(
                height: ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 12.0,
                  regular: 16.0,
                ),
              ),
              
              // Message
              Text(
                'Before you begin, please watch the Exam Overview video to understand our Course and Examination.',
                style: GoogleFonts.inter(
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 15.0),
                  color: const Color(0xFF565E6C),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(
                height: ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 24.0,
                  regular: 28.0,
                ),
              ),
              
              // Proceed Button
              SizedBox(
                width: double.infinity,
                height: ResponsiveHelper.adaptiveFontSize(context, 50.0),
                child: ElevatedButton(
                  onPressed: () {
                    Logger.i('📚 User clicked Proceed to Exam Overview');
                    Navigator.of(context).pop(); // Close the dialog
                    onProceed(); // Execute the callback
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Proceed to Exam Overview',
                    style: GoogleFonts.inter(
                      fontSize: ResponsiveHelper.adaptiveFontSize(
                        context,
                        16.0,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
