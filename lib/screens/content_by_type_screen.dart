import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/content_model.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/content_update_service.dart';
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
  final bool isExamOverviewMode;

  const ContentByTypeScreen({
    super.key,
    required this.course,
    required this.module,
    required this.contentType,
    required this.displayName,
    this.isExamOverviewMode = false,
  });

  @override
  State<ContentByTypeScreen> createState() => _ContentByTypeScreenState();
}

class _ContentByTypeScreenState extends State<ContentByTypeScreen> {
  bool _isLoading = true;
  List<ContentModel> _contentList = [];
  String? _errorMessage;
  int _selectedIndex = 0;
  final _updateService = ContentUpdateService();
  String? _currentUserId;

  /// Set of content-item IDs that have unseen updates in this module.
  /// Fetched once on load and refreshed after returning from the viewer.
  Set<String> _unseenItemIds = {};

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

      // Fetch unseen item IDs — no validItemIds filter needed here because
      // orphaned IDs are naturally handled by the card check: if an ID isn't
      // in the content list, no card exists for it, so no badge is rendered.
      Set<String> unseen = {};
      if (_currentUserId != null) {
        unseen = await _updateService.getUnseenItemIds(
          widget.course.id,
          widget.module.id,
          _currentUserId!,
        );
      }

      setState(() {
        _contentList = filteredContent;
        _unseenItemIds = unseen;
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

  /// Re-fetch only the unseen item IDs (lighter than full content reload).
  Future<void> _refreshUnseenIds() async {
    if (_currentUserId == null) return;
    try {
      final unseen = await _updateService.getUnseenItemIds(
        widget.course.id,
        widget.module.id,
        _currentUserId!,
      );
      if (mounted) {
        setState(() => _unseenItemIds = unseen);
      }
    } catch (e) {
      Logger.w('Failed to refresh unseen IDs: $e');
    }
  }

  IconData _getIconForContent(ContentModel content) {
    switch (content.contentType.toLowerCase()) {
      case 'video':
        return Icons.play_circle_filled;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'audio':
        return Icons.headphones;
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

  Color _getColorForIndex(int index) {
    // Alternate between blue and light blue
    return index % 2 == 0
        ? const Color(0xFF1565C0)
        : const Color(0xFF29ACD6);
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

  /// Whether this content item should show an UPDATE badge.
  bool _hasUpdateBadge(ContentModel content) {
    // Session-scoped override takes priority (instant clear on tap).
    if (_updateService.isItemSeen(content.id)) return false;
    return _unseenItemIds.contains(content.id);
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
              : _contentList.isEmpty
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
                                // Header
                                Text(
                                  widget.displayName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                // Content Item Cards
                                ..._contentList.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final content = entry.value;
                                  final backgroundColor = _getColorForIndex(index);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _buildContentItemCard(
                                      content: content,
                                      index: index,
                                      backgroundColor: backgroundColor,
                                    ),
                                  );
                                }),
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

  /// Build a content item card with an optional "UPDATE" badge.
  Widget _buildContentItemCard({
    required ContentModel content,
    required int index,
    required Color backgroundColor,
  }) {
    final showBadge = _hasUpdateBadge(content);

    return GestureDetector(
      onTap: () {
        // Optimistic: mark item as seen instantly in memory.
        _updateService.markItemSeen(content.id);
        if (showBadge) {
          setState(() {}); // rebuild to hide badge
        }

        // Navigate to the viewer
        AppNavigator.navigateTo(
          context: context,
          page: ContentViewerScreen(
            course: widget.course,
            module: widget.module,
            initialContentIndex: index,
            filteredContentType: widget.contentType,
            singleContentMode: true,
            isExamOverviewMode: widget.isExamOverviewMode,
          ),
        ).then((_) async {
          // Persist the seen state in SharedPreferences + Firestore
          if (_currentUserId != null) {
            await _updateService
                .persistItemSeen(
                  widget.course.id,
                  widget.module.id,
                  content.id,
                  content.contentType,
                  _currentUserId!,
                )
                .catchError(
                  (e) => Logger.w('Failed to persist item as seen: $e'),
                );
          }
          // Refresh unseen IDs to update all cards
          await _refreshUnseenIds();
        });
      },
      child: Container(
        width: double.infinity,
        height: _getCardHeight(content.title),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Badge strip — always 28px tall, badge right-aligned when present
            SizedBox(
              height: 28,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // One-time view lock badge
                      if (content.isOneTimeView)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7.2,
                            vertical: 3.6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber[700],
                            borderRadius: BorderRadius.circular(10.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock, size: 8, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                'ONE-TIME',
                                style: GoogleFonts.inter(
                                  fontSize: 8.1,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // UPDATE badge
                      if (showBadge)
                        _buildUpdateBadgePill(),
                    ],
                  ),
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
                            '#${index + 1}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Flexible(
                            child: Text(
                              content.title,
                              style: TextStyle(
                                fontSize: _getTitleFontSize(content.title),
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
                    _buildContentIcon(widget.contentType),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The standard "UPDATE" badge pill used across all card levels.
  Widget _buildUpdateBadgePill() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7.2, vertical: 3.6),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(10.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 5.4, color: Colors.white),
            const SizedBox(width: 3.6),
            Text(
              'UPDATE',
              style: GoogleFonts.inter(
                fontSize: 8.1,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the icon container for content cards
  Widget _buildContentIcon(String contentType) {
    switch (contentType.toLowerCase()) {
      case 'video':
        return _buildVideoIcon();
      case 'pdf':
        return _buildPdfIcon();
      case 'image':
        return _buildImageIcon();
      default:
        return _buildDefaultIcon();
    }
  }

  /// Build video icon with stacked lines and play button
  Widget _buildVideoIcon() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Multiple layers to create the stacked effect
          Positioned(
            top: 8,
            child: Container(
              width: 45,
              height: 2,
              color: Colors.white,
            ),
          ),
          Positioned(
            top: 12,
            child: Container(
              width: 45,
              height: 2,
              color: Colors.white,
            ),
          ),
          Positioned(
            top: 16,
            child: Container(
              width: 45,
              height: 2,
              color: Colors.white,
            ),
          ),
          // Play button
          const Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: 32,
          ),
        ],
      ),
    );
  }

  /// Build PDF icon
  Widget _buildPdfIcon() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.picture_as_pdf_outlined,
        color: Colors.white,
        size: 32,
      ),
    );
  }

  /// Build image icon
  Widget _buildImageIcon() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.image_outlined,
        color: Colors.white,
        size: 32,
      ),
    );
  }

  /// Build default icon for other content types
  Widget _buildDefaultIcon() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.description_outlined,
        color: Colors.white,
        size: 32,
      ),
    );
  }
}