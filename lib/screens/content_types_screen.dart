import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/content_model.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/firestore_service.dart';
import '../services/content_update_service.dart';
import '../utils/logger.dart';
import '../utils/route_transitions.dart';
import '../widgets/custom_bottom_navigation.dart';
import 'content_by_type_screen.dart';

class ContentTypesScreen extends StatefulWidget {
  final CourseModel course;
  final ModuleModel module;
  final bool isExamOverviewMode;

  const ContentTypesScreen({
    super.key,
    required this.course,
    required this.module,
    this.isExamOverviewMode = false,
  });

  @override
  State<ContentTypesScreen> createState() => _ContentTypesScreenState();
}

class _ContentTypesScreenState extends State<ContentTypesScreen> {
  bool _isLoading = true;
  Map<String, List<ContentModel>> _contentByType = {};
  String? _errorMessage;
  int _selectedIndex = 0;
  final _updateService = ContentUpdateService();
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
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

  Color _getColorForContentType(String type, int index) {
    // Alternate between blue and light blue
    return index % 2 == 0
        ? const Color(0xFF1565C0)
        : const Color(0xFF29ACD6);
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

  // Dynamic font size calculation based on title length
  double _getTitleFontSize(String title) {
    final length = title.length;
    if (length <= 20) return 18.0; // Short titles - normal size
    if (length <= 40) return 16.0; // Medium titles - slightly smaller
    return 14.0; // Long titles - smallest
  }

  // Dynamic card height based on title length
  double _getCardHeight(String title) {
    final length = title.length;
    if (length <= 40) return 130.0; // Normal height for short/medium titles
    return 145.0; // Taller for long titles
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isExamOverviewMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && widget.isExamOverviewMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please watch the Exam Overview before accessing the app',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.grey[50],
          elevation: 0,
          leading: widget.isExamOverviewMode
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
          title: Text(
            widget.module.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
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
                            backgroundColor: const Color(0xFF1565C0),
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
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Content Header
                                const Text(
                                  'Content',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                // Content Type Cards — one per type, with live update badges
                                ..._contentByType.entries.toList().asMap().entries.map((mapEntry) {
                                  final index = mapEntry.key;
                                  final entry = mapEntry.value;
                                  final type = entry.key;
                                  final contents = entry.value;
                                  final color = _getColorForContentType(type, index);
                                  final icon = _getIconForContentType(type);
                                  final displayName = _getDisplayNameForContentType(type);

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _buildContentTypeCard(
                                      type: type,
                                      contents: contents,
                                      displayName: displayName,
                                      color: color,
                                      icon: icon,
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
      bottomNavigationBar: widget.isExamOverviewMode
        ? null
        : CustomBottomNavigation(
            selectedIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
              CustomBottomNavigation.handleNavigation(context, index);
            },
          ),
      ),
    );
  }

  /// Returns the badge label and color for a content-type update record
  _ContentTypeBadge? _resolveBadge(Map<String, dynamic>? updateInfo) {
    if (updateInfo == null) return null;
    final changeType = updateInfo['changeType'] as String? ?? '';
    switch (changeType) {
      case 'added':
        return const _ContentTypeBadge(label: 'NEW', color: Colors.orange);
      case 'removed':
        return const _ContentTypeBadge(label: 'REMOVED', color: Colors.orange);
      case 'reordered':
        return const _ContentTypeBadge(label: 'REORDERED', color: Colors.orange);
      default:
        return const _ContentTypeBadge(label: 'UPDATED', color: Colors.orange);
    }
  }

  /// Content-type card wrapped in a FutureBuilder for live update detection.
  /// Uses dual-check (like module cards): content-type-level update OR item-level count.
  Widget _buildContentTypeCard({
    required String type,
    required List<ContentModel> contents,
    required String displayName,
    required Color color,
    required IconData icon,
  }) {
    if (_currentUserId == null) {
      return _buildContentTypeCardContent(
        type: type,
        contents: contents,
        displayName: displayName,
        color: color,
        icon: icon,
        badge: null,
        updateInfo: null,
      );
    }

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _updateService.getContentTypeUpdateInfo(
          widget.course.id,
          widget.module.id,
          type,
          _currentUserId!,
        ),
        _updateService.getContentItemUpdateCountForType(
          widget.course.id,
          widget.module.id,
          type,
          _currentUserId!,
        ),
      ]),
      builder: (context, snapshot) {
        final updateInfo = snapshot.data?[0] as Map<String, dynamic>?;
        final itemUpdateCount = (snapshot.data?[1] as int?) ?? 0;

        // Content-type badge takes priority; fall back to "UPDATED" when only items changed
        _ContentTypeBadge? badge = _resolveBadge(updateInfo);
        if (badge == null && itemUpdateCount > 0) {
          badge = _ContentTypeBadge(label: 'UPDATED', color: Colors.orange);
        }

        return _buildContentTypeCardContent(
          type: type,
          contents: contents,
          displayName: displayName,
          color: color,
          icon: icon,
          badge: badge,
          updateInfo: updateInfo,
          itemUpdateCount: itemUpdateCount,
        );
      },
    );
  }

  Widget _buildContentTypeCardContent({
    required String type,
    required List<ContentModel> contents,
    required String displayName,
    required Color color,
    required IconData icon,
    required _ContentTypeBadge? badge,
    required Map<String, dynamic>? updateInfo,
    int itemUpdateCount = 0,
  }) {
    return GestureDetector(
      onTap: () {
        // Navigate immediately and wait for return
        AppNavigator.navigateTo(
          context: context,
          page: ContentByTypeScreen(
            course: widget.course,
            module: widget.module,
            contentType: type,
            displayName: displayName,
            isExamOverviewMode: widget.isExamOverviewMode,
          ),
        ).then((_) {
          // Rebuild to refresh badges when returning
          if (mounted) {
            setState(() {
              // The setState will trigger the FutureBuilder to re-run _updateService calls
            });
          }
        });
      },
      child: Container(
        width: double.infinity,
        height: _getCardHeight(displayName),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Badge strip — always 28px tall; item count on left, update badge on right
            SizedBox(
              height: 28,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: item count bubble
                    if (itemUpdateCount > 0)
                      IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7.2,
                            vertical: 3.6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0),
                            borderRadius: BorderRadius.circular(10.8),
                          ),
                          child: Text(
                            '+$itemUpdateCount',
                            style: GoogleFonts.inter(
                              fontSize: 8.1,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    // Right: update badge
                    if (badge != null)
                      IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7.2,
                            vertical: 3.6,
                          ),
                          decoration: BoxDecoration(
                            color: badge.color,
                            borderRadius: BorderRadius.circular(10.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.circle, size: 5.4, color: Colors.white),
                              const SizedBox(width: 3.6),
                              Text(
                                badge.label,
                                style: GoogleFonts.inter(
                                  fontSize: 8.1,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${contents.length} ${contents.length == 1 ? 'Item' : 'Items'}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Flexible(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontSize: _getTitleFontSize(displayName),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.2,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildContentIcon(icon),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the icon container for content cards
  Widget _buildContentIcon(IconData icon) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 32,
      ),
    );
  }
}

/// Simple data holder for a content-type badge label + color
class _ContentTypeBadge {
  final String label;
  final Color color;
  const _ContentTypeBadge({required this.label, required this.color});
}