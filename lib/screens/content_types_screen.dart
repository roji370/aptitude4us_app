import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/content_model.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/firestore_service.dart';
import '../utils/logger.dart';
import '../utils/route_transitions.dart';
import '../widgets/custom_bottom_navigation.dart';
import 'content_by_type_screen.dart';

class ContentTypesScreen extends StatefulWidget {
  final CourseModel course;
  final ModuleModel module;

  const ContentTypesScreen({
    super.key,
    required this.course,
    required this.module,
  });

  @override
  State<ContentTypesScreen> createState() => _ContentTypesScreenState();
}

class _ContentTypesScreenState extends State<ContentTypesScreen> {
  bool _isLoading = true;
  Map<String, List<ContentModel>> _contentByType = {};
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Logger.i(
        "Loading content for module: ${widget.module.id} in course: ${widget.course.id}",
      );

      final contentList = await firestoreService.getModuleContent(
        widget.course.id,
        widget.module.id,
      );

      Logger.i("Loaded ${contentList.length} content items");

      // Group content by type
      final Map<String, List<ContentModel>> groupedContent = {};
      for (var content in contentList) {
        if (!groupedContent.containsKey(content.contentType)) {
          groupedContent[content.contentType] = [];
        }
        groupedContent[content.contentType]!.add(content);
      }

      // Sort each type's content by order
      groupedContent.forEach((type, contents) {
        contents.sort((a, b) => a.order.compareTo(b.order));
      });

      setState(() {
        _contentByType = groupedContent;
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

  IconData _getIconForContentType(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return Icons.play_circle_outline;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'ppt':
        return Icons.slideshow;
      case 'image':
        return Icons.image;
      case 'link':
        return Icons.link;
      case 'text':
        return Icons.text_fields;
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

  String _getDisplayNameForContentType(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return 'Videos';
      case 'pdf':
        return 'PDFs';
      case 'ppt':
        return 'Presentations';
      case 'image':
        return 'Images';
      case 'link':
        return 'Links';
      case 'text':
        return 'Documents';
      default:
        return type.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF323483),
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
              widget.module.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.course.title,
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
                            backgroundColor: const Color(0xFF323483),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _contentByType.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No Content Available',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'This module doesn\'t have any content yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
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
                          decoration: const BoxDecoration(
                            color: Color(0xFF323483),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(30),
                              bottomRight: Radius.circular(30),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Content Types',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Select a content type to view',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Content type cards
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _contentByType.length,
                            itemBuilder: (context, index) {
                              final type = _contentByType.keys.elementAt(index);
                              final contents = _contentByType[type]!;
                              final color = _getColorForContentType(type);
                              final icon = _getIconForContentType(type);
                              final displayName = _getDisplayNameForContentType(type);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    AppNavigator.navigateTo(
                                      context: context,
                                      page: ContentByTypeScreen(
                                        course: widget.course,
                                        module: widget.module,
                                        contentType: type,
                                        displayName: displayName,
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Row(
                                      children: [
                                        // Icon container
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            icon,
                                            color: color,
                                            size: 32,
                                          ),
                                        ),
                                        const SizedBox(width: 16),

                                        // Content type info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displayName,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF323483),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${contents.length} ${contents.length == 1 ? 'item' : 'items'}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Arrow icon
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          color: Colors.grey,
                                          size: 20,
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

