import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reusable widget for showing inactive content messages
class InactiveContentMessage extends StatelessWidget {
  final String title;
  final String description;
  final String actionText;
  final IconData icon;
  final MaterialColor accentColor;
  final String contentType; // 'course', 'module', 'content'

  const InactiveContentMessage({
    super.key,
    required this.title,
    required this.description,
    required this.actionText,
    this.icon = Icons.schedule,
    this.accentColor = Colors.orange,
    this.contentType = 'content',
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon container
            Container(
              width: screenSize.width * 0.25,
              height: screenSize.width * 0.25,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: screenSize.width * 0.12,
                color: accentColor[400],
              ),
            ),
            
            SizedBox(height: 24),
            
            // Title
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: screenSize.width * 0.05,
                color: accentColor[700],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            
            SizedBox(height: 16),
            
            // Description container
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accentColor[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: accentColor[600],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Action text container
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: accentColor[700],
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            actionText,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: accentColor[700],
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Factory constructor for inactive modules
  factory InactiveContentMessage.modules() {
    return InactiveContentMessage(
      title: 'Modules Currently Inactive',
      description: 'This course has modules, but they are currently not active. The modules may be scheduled for future release or are temporarily unavailable.',
      actionText: 'Contact your instructor for more information about when these modules will be available.',
      icon: Icons.schedule,
      accentColor: Colors.orange,
      contentType: 'module',
    );
  }

  /// Factory constructor for no modules
  factory InactiveContentMessage.noModules() {
    return InactiveContentMessage(
      title: 'No Modules Available',
      description: 'This course doesn\'t have any modules yet. New modules will appear here when they become available.',
      actionText: 'Check back later or contact your instructor for updates.',
      icon: Icons.book_outlined,
      accentColor: Colors.grey,
      contentType: 'module',
    );
  }

  /// Factory constructor for inactive content
  factory InactiveContentMessage.content() {
    return InactiveContentMessage(
      title: 'Content Currently Inactive',
      description: 'This module has content that is currently not active. The content may be scheduled for future release or is temporarily unavailable.',
      actionText: 'Please contact your instructor for more information about when this content will be available.',
      icon: Icons.schedule,
      accentColor: Colors.amber,
      contentType: 'content',
    );
  }

  /// Factory constructor for no content
  factory InactiveContentMessage.noContent() {
    return InactiveContentMessage(
      title: 'No Content Available',
      description: 'This module doesn\'t have any content yet. New content will appear here when it becomes available.',
      actionText: 'Check back later or contact your instructor for updates.',
      icon: Icons.folder_open,
      accentColor: Colors.grey,
      contentType: 'content',
    );
  }
}
