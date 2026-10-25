import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/content_model.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/content_update_service.dart';
import '../services/firestore_service.dart';
import '../utils/app_colors.dart';
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Course access (subscription + assignment) was already verified by
      // ProtectedCourseContent at the AssignedCoursesScreen level. The old
      // hasAccessToCourse() call here cost 2+ Firestore reads and was
      // redundant for every screen in the navigation chain below it.

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
    return index % 2 == 0 ? AppColors.primary : AppColors.secondary;
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
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: widget.isExamOverviewMode
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              ),
          title: Text(
            widget.module.title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
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
                            backgroundColor: AppColors.primary,
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
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface,
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

  /// Build a content item card — Stitch accent strip design.
  Widget _buildContentItemCard({
    required ContentModel content,
    required int index,
    required Color backgroundColor,
  }) {
    final showBadge = _hasUpdateBadge(content);
    final icon = _getIconForContent(content);

    return GestureDetector(
      onTap: () {
        _updateService.markItemSeen(content.id);
        if (showBadge) {
          setState(() {});
        }

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
                  (e) => Logger.w('Failed to persist item as seen: \$e'),
                );
          }
          await _refreshUnseenIds();
        });
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 6, color: backgroundColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 20, color: backgroundColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          content.title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                            letterSpacing: 0.14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '#${index + 1}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // One-time-view pill
                  if (content.isOneTimeView)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, size: 10, color: AppColors.error),
                          const SizedBox(width: 3),
                          Text(
                            '1×',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Update badge
                  if (showBadge) _buildUpdateBadgePill(),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.outline,
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Teal update badge pill.
  Widget _buildUpdateBadgePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 6, color: AppColors.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            'New',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
