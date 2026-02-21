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

  // Content-type-level update (e.g. "pdfs added"). Loaded once before being
  // marked as seen so we can badge newly added items in this screen.
  Map<String, dynamic>? _contentTypeUpdateInfo;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadContent();
    _loadAndMarkContentTypeUpdate();
  }

  /// Read the content-type update first, store it, then mark it as seen.
  /// Order matters: read → setState → mark as seen (fire-and-forget).
  Future<void> _loadAndMarkContentTypeUpdate() async {
    if (_currentUserId == null) return;
    try {
      final info = await _updateService.getContentTypeUpdateInfo(
        widget.course.id,
        widget.module.id,
        widget.contentType,
        _currentUserId!,
      );
      if (mounted) setState(() => _contentTypeUpdateInfo = info);
      if (info != null) {
        _updateService
            .markContentTypeAsSeen(
              widget.course.id,
              widget.module.id,
              widget.contentType,
              _currentUserId!,
            )
            .catchError((e) => Logger.w('Failed to mark content type as seen: $e'));
      }
    } catch (e) {
      Logger.w('Failed to load content type update info: $e');
    }
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

  Future<bool> _checkIfAllItemsSeen() async {
    for (var item in _contentList) {
      final info = await _updateService.getContentItemUpdateInfo(
        widget.course.id,
        widget.module.id,
        item.id,
        item.contentType,
        _currentUserId!,
      );
      if (info != null) return false;
    }
    return true;
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
                                
                                // Content Item Cards — with live update badges per item
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

  /// Maps a content-item changeType to a badge label + color
  _ContentItemBadge? _resolveItemBadge(Map<String, dynamic>? updateInfo) {
    if (updateInfo == null) return null;
    final changeType = updateInfo['changeType'] as String? ?? '';
    switch (changeType) {
      case 'added':
        return const _ContentItemBadge(label: 'NEW', color: Colors.orange);
      case 'url_changed':
        return const _ContentItemBadge(label: 'UPDATED', color: Colors.orange);
      case 'unpublished':
        return const _ContentItemBadge(label: 'UNAVAILABLE', color: Colors.orange);
      case 'published':
        return const _ContentItemBadge(label: 'AVAILABLE', color: Colors.orange);
      case 'title_changed':
        return const _ContentItemBadge(label: 'RENAMED', color: Colors.orange);
      case 'description_changed':
        return const _ContentItemBadge(label: 'UPDATED', color: Colors.orange);
      default:
        return const _ContentItemBadge(label: 'UPDATED', color: Colors.orange);
    }
  }

  /// Content item card wrapped in a FutureBuilder for live update detection
  Widget _buildContentItemCard({
    required ContentModel content,
    required int index,
    required Color backgroundColor,
  }) {
    if (_currentUserId == null) {
      return _buildContentItemCardContent(
        content: content,
        index: index,
        backgroundColor: backgroundColor,
        badge: null,
        updateInfo: null,
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _updateService.getContentItemUpdateInfo(
        widget.course.id,
        widget.module.id,
        content.id,
        content.contentType,
        _currentUserId!,
      ),
      builder: (context, snapshot) {
        final updateInfo = snapshot.data;
        _ContentItemBadge? badge = _resolveItemBadge(updateInfo);

        // Fallback: if no item-level badge but the content type had items added,
        // check if this item's createdAt falls within the update window.
        // notifyContentItemUpdate skips new items, so we infer newness from timestamp.
        if (badge == null && _contentTypeUpdateInfo?['changeType'] == 'added') {
          final rawTs = _contentTypeUpdateInfo!['timestamp'];
          DateTime? updateTime;
          try {
            updateTime = (rawTs as dynamic).toDate() as DateTime;
          } catch (_) {
            if (rawTs is DateTime) updateTime = rawTs;
          }
          if (updateTime != null && content.createdAt != null) {
            // Item created within 10 minutes before the update record was written
            if (content.createdAt!.isAfter(
              updateTime.subtract(const Duration(minutes: 10)),
            )) {
              badge = const _ContentItemBadge(label: 'NEW', color: Colors.orange);
            }
          }
        }

        // Optimistic override: if the user already tapped this item this session
        // (tracked in service-level static set, survives disposal), clear badge instantly.
        if (_updateService.isOptimisticallySeen(content.id)) badge = null;

        return _buildContentItemCardContent(
          content: content,
          index: index,
          backgroundColor: backgroundColor,
          badge: badge,
          updateInfo: updateInfo,
        );
      },
    );
  }

  Widget _buildContentItemCardContent({
    required ContentModel content,
    required int index,
    required Color backgroundColor,
    required _ContentItemBadge? badge,
    required Map<String, dynamic>? updateInfo,
  }) {
    return GestureDetector(
      onTap: () {
        // Immediately mark item as "seen" in local state (optimistic update).
        // This clears the badge right away without waiting for the async service.
        if (badge != null) {
          _updateService.markSeenOptimistically(content.id);
          setState(() {});  // trigger immediate badge removal
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
          // Persist the seen state and refresh badges when returning
          if (_currentUserId != null) {
            await _updateService
                .markContentItemAsSeen(
                  widget.course.id,
                  widget.module.id,
                  content.id,
                  content.contentType,
                  _currentUserId!,
                )
                .catchError((e) => Logger.w('Failed to mark item as seen: $e'));
          }
          if (mounted) setState(() {});
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
                  child: badge != null
                      ? IgnorePointer(
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
                      : const SizedBox.shrink(),
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

/// Simple data holder for a content-item badge label + color
class _ContentItemBadge {
  final String label;
  final Color color;
  const _ContentItemBadge({required this.label, required this.color});
}