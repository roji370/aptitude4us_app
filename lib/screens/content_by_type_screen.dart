import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/content_model.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../utils/logger.dart';
import '../utils/route_transitions.dart';
import '../widgets/custom_bottom_navigation.dart';
import 'content_viewer_screen.dart';

class ContentByTypeScreen extends StatefulWidget {
  final CourseModel course;
  final ModuleModel module;
  final String contentType;
  final String displayName;

  const ContentByTypeScreen({
    super.key,
    required this.course,
    required this.module,
    required this.contentType,
    required this.displayName,
  });

  @override
  State<ContentByTypeScreen> createState() => _ContentByTypeScreenState();
}

class _ContentByTypeScreenState extends State<ContentByTypeScreen> {
  bool _isLoading = true;
  List<ContentModel> _contentList = [];
  String? _errorMessage;
  int _selectedIndex = 0; // For bottom navigation

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    final authService = Provider.of<AuthService>(context, listen: false);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // First verify the user has access to this course
      Logger.i("Verifying access to course: ${widget.course.id}");
      final hasAccess = await authService.hasAccessToCourse(widget.course.id);

      if (!hasAccess) {
        Logger.w(
          "Access denied: User does not have access to course ${widget.course.id}",
        );
        setState(() {
          _errorMessage = 'You do not have access to this course content.';
          _isLoading = false;
        });
        return;
      }

      Logger.i("Access granted: User has access to course ${widget.course.id}");

      // Load all content for the module
      final allContent = await firestoreService.getModuleContent(
        widget.course.id,
        widget.module.id,
      );

      Logger.i("Loaded ${allContent.length} total content items");

      // Filter by content type
      final filteredContent = allContent
          .where((content) => content.contentType == widget.contentType)
          .toList();

      // Sort by order
      filteredContent.sort((a, b) => a.order.compareTo(b.order));

      Logger.i(
        "Filtered to ${filteredContent.length} items of type ${widget.contentType}",
      );

      setState(() {
        _contentList = filteredContent;
        _isLoading = false;
      });
    } catch (e) {
      Logger.e("Error loading content: $e");
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  IconData _getIconForContent(ContentModel content) {
    switch (content.contentType.toLowerCase()) {
      case 'video':
        return Icons.play_circle_filled;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'ppt':
        return Icons.slideshow;
      case 'image':
        return Icons.image;
      case 'link':
        return Icons.link;
      case 'text':
        return Icons.article;
      default:
        return Icons.description;
    }
  }

  Color _getColorForContentType(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return const Color(0xFFE53935); // Red
      case 'pdf':
        return const Color(0xFFD32F2F); // Deep red
      case 'ppt':
        return const Color(0xFFFB8C00); // Orange
      case 'image':
        return const Color(0xFF7B1FA2); // Purple
      case 'link':
        return const Color(0xFF1976D2); // Blue
      case 'text':
        return const Color(0xFF388E3C); // Green
      default:
        return const Color(0xFF323483); // Default brand color
    }
  }

  String _getContentDuration(ContentModel content) {
    if (content.contentType == 'video' && content.duration != null) {
      final duration = Duration(seconds: content.duration!.toInt());
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getColorForContentType(widget.contentType);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.displayName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.module.title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF323483)),
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Error Loading Content',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadContent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _contentList.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: themeColor.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No Content Available',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No ${widget.displayName.toLowerCase()} found in this module.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: themeColor,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(30),
                              bottomRight: Radius.circular(30),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.displayName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_contentList.length} ${_contentList.length == 1 ? 'item' : 'items'} available',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Content list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _contentList.length,
                            itemBuilder: (context, index) {
                              final content = _contentList[index];
                              final duration = _getContentDuration(content);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    // Navigate to content viewer with this specific content
                                    // Pass the index within the filtered list and enable single content mode
                                    AppNavigator.navigateTo(
                                      context: context,
                                      page: ContentViewerScreen(
                                        course: widget.course,
                                        module: widget.module,
                                        initialContentIndex: index,
                                        filteredContentType: widget.contentType,
                                        singleContentMode: true,
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        // Icon
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: themeColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            _getIconForContent(content),
                                            color: themeColor,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),

                                        // Content info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                content.title,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF323483),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (duration.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.access_time,
                                                      size: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      duration,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),

                                        // Order number
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: themeColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '#${index + 1}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: themeColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
      bottomNavigationBar: CustomBottomNavigation(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          CustomBottomNavigation.handleNavigation(context, index);
        },
      ),
    );
  }
}

