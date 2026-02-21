import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/community_chat_message.dart';
import '../services/community_chat_service.dart';
import '../services/attachment_service.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../widgets/community_chat_message_bubble.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/protected_course_content.dart';
import '../widgets/reply_input_widget.dart';
import '../utils/responsive_helper.dart';
import '../utils/logger.dart';

class CommunityChatScreen extends StatefulWidget {
  const CommunityChatScreen({super.key});

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen>
    with TickerProviderStateMixin {
  final CommunityChatService _chatService = CommunityChatService();
  final AuthService _authService = AuthService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  // Reply functionality state
  CommunityChatMessage? _replyingToMessage;
  bool _isSendingReply = false;
  final GlobalKey<AnimatedListState> _messageListKey =
      GlobalKey<AnimatedListState>();

  // Message highlighting state
  String? _highlightedMessageId;
  late AnimationController _highlightAnimationController;
  late Animation<double> _highlightAnimation;

  // Scroll-to-message state
  bool _isScrollingToMessage = false;
  String? _searchingForMessageId;

  // Stream key used to force StreamBuilder to re-subscribe on refresh
  int _streamKey = 0;
  bool _isRefreshing = false;

  // Get the actual user display name from UserModel
  Future<String> _getUserDisplayName() async {
    try {
      // Try to get from cached user data first (faster)
      final cachedUser = await AuthPersistenceService.getUserData();
      if (cachedUser != null && cachedUser.displayName.isNotEmpty) {
        return cachedUser.displayName;
      }

      // Fallback to getting fresh user data from Firestore
      final userData = await _authService.getUserData();
      if (userData != null && userData.displayName.isNotEmpty) {
        return userData.displayName;
      }

      // Final fallback to Firebase Auth displayName
      final user = FirebaseAuth.instance.currentUser;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        return user.displayName!;
      }

      // Last resort fallback
      return 'Student';
    } catch (e) {
      Logger.e('Error getting user display name: $e');
      return 'Student';
    }
  }

  bool _isSending = false;

  late AnimationController _inputAnimationController;
  late AnimationController _fabAnimationController;
  late AnimationController _refreshAnimationController;
  late Animation<double> _inputScaleAnimation;
  late Animation<double> _fabScaleAnimation;
  late Animation<double> _refreshRotationAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupInputListener();
    _chatService.addWelcomeMessageIfNeeded();
  }

  void _initializeAnimations() {
    // Initialize highlight animation for scroll-to-message
    _highlightAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _highlightAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _highlightAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _inputAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _refreshAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _inputScaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(
        parent: _inputAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _fabScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeInOut),
    );

    _refreshRotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _refreshAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _setupInputListener() {
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        _inputAnimationController.forward();
      } else {
        _inputAnimationController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _inputAnimationController.dispose();
    _fabAnimationController.dispose();
    _highlightAnimationController.dispose();
    _refreshAnimationController.dispose();
    super.dispose();
  }

  /// Performs a functional refresh by:
  /// 1. Showing a spinner animation on the refresh icon
  /// 2. Re-initialising any welcome messages if the collection is empty
  /// 3. Incrementing [_streamKey] so that the StreamBuilder rebuilds with a
  ///    fresh subscription, discarding any cached / stale data
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    HapticFeedback.lightImpact();

    setState(() => _isRefreshing = true);
    _refreshAnimationController.repeat();

    try {
      // Re-trigger the welcome message in case the collection was cleared
      await _chatService.addWelcomeMessageIfNeeded();
    } catch (e) {
      Logger.e('Error during refresh: $e');
      if (mounted) {
        _showSnackBar('Refresh failed. Please try again.', isError: true);
      }
    } finally {
      if (mounted) {
        // Finish the spinner rotation cleanly
        await _refreshAnimationController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 200),
        );
        _refreshAnimationController.stop();
        _refreshAnimationController.reset();

        setState(() {
          _isRefreshing = false;
          // Bump the key → StreamBuilder rebuilds with a brand-new stream
          _streamKey++;
        });

        HapticFeedback.selectionClick();
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty ||
        _isSending ||
        _isSendingReply) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Haptic feedback
    HapticFeedback.lightImpact();

    // Animation feedback
    _fabAnimationController.forward().then((_) {
      _fabAnimationController.reverse();
    });

    final messageText = _messageController.text.trim();

    // Clear message input immediately for responsiveness
    _messageController.clear();

    setState(() {
      _isSending = true;
      _isSendingReply = _replyingToMessage != null;
    });

    try {
      // Get the actual user display name
      final senderName = await _getUserDisplayName();

      await _chatService.sendMessage(
        senderId: user.uid,
        senderName: senderName,
        text: messageText,
        replyToMessageId: _replyingToMessage?.id,
      );

      // Success feedback
      HapticFeedback.selectionClick();

      // Clear reply state after successful send
      if (_replyingToMessage != null) {
        setState(() {
          _replyingToMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to send message: ${e.toString()}', isError: true);
        // Restore message text on error
        _messageController.text = messageText;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isSendingReply = false;
        });
      }
    }
  }

  // Reply functionality methods
  void _startReply(CommunityChatMessage message) {
    setState(() {
      _replyingToMessage = message;
    });
    _inputFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  /// Enhanced scroll-to-message functionality with smooth scrolling and highlighting
  /// Implements WhatsApp-style message navigation with visual feedback
  Future<void> _scrollToMessage(String messageId) async {
    Logger.i('Community Chat - Scroll-to-message requested for ID: $messageId');

    if (_isScrollingToMessage || messageId.isEmpty) {
      Logger.w('Scroll operation already in progress or empty messageId');
      return;
    }

    setState(() {
      _isScrollingToMessage = true;
      _searchingForMessageId = messageId;
    });

    try {
      // Get current messages from the stream
      final messages = await _chatService.getCommunityMessages().first;
      Logger.i(
        'Community Chat - Got ${messages.length} messages from stream',
      );

      // Find the target message index
      final messageIndex = messages.indexWhere((msg) => msg.id == messageId);
      Logger.i(
        'Community Chat - Message index found: $messageIndex out of ${messages.length} messages',
      );

      if (messageIndex == -1) {
        // Message not found in current loaded messages
        Logger.w('Message not found in current loaded messages');
        await _handleMessageNotFound(messageId);
        return;
      }

      // Calculate scroll position
      // Since ListView is reversed, we need to calculate from the end
      final itemHeight = _estimateMessageHeight();
      final targetScrollOffset = messageIndex * itemHeight;
      Logger.i(
        'Community Chat - Calculated scroll offset: $targetScrollOffset (itemHeight: $itemHeight)',
      );

      // Smooth scroll to the target message
      await _performSmoothScroll(targetScrollOffset);

      // Highlight the message
      await _highlightMessage(messageId);

      Logger.i('Community Chat - Scroll-to-message completed successfully');
    } catch (e) {
      Logger.e('Error scrolling to message: $e');
      _showSnackBar('Could not find the message', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isScrollingToMessage = false;
          _searchingForMessageId = null;
        });
      }
    }
  }

  /// Estimates the average height of a message bubble for scroll calculations
  double _estimateMessageHeight() {
    return ResponsiveHelper.getAdaptiveSpacing(
      context,
      compact: 80.0,
      regular: 90.0,
      pro: 100.0,
      large: 110.0,
      extraLarge: 120.0,
    );
  }

  /// Performs smooth scrolling to the target offset with easing animation
  Future<void> _performSmoothScroll(double targetOffset) async {
    if (!_scrollController.hasClients) return;

    // Clamp the offset to valid scroll bounds
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScrollExtent);

    // Animate to the target position with smooth easing
    await _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );

    // Small delay to ensure the scroll is complete before highlighting
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Highlights the target message with a subtle animation
  Future<void> _highlightMessage(String messageId) async {
    if (!mounted) return;

    setState(() {
      _highlightedMessageId = messageId;
    });

    // Start the highlight animation
    await _highlightAnimationController.forward();

    // Wait for 1.5 seconds to show the highlight
    await Future.delayed(const Duration(milliseconds: 1500));

    // Fade out the highlight
    await _highlightAnimationController.reverse();

    // Clear the highlighted message
    if (mounted) {
      setState(() {
        _highlightedMessageId = null;
      });
    }
  }

  /// Handles the case when a message is not found in currently loaded messages
  Future<void> _handleMessageNotFound(String messageId) async {
    Logger.w('Message not found in current view: $messageId');
    _showSnackBar('Message not found or may have been deleted', isError: true);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: ResponsiveHelper.getAdaptiveBorderRadius(
            context,
            compact: 8.0,
            regular: 10.0,
            pro: 12.0,
            large: 12.0,
            extraLarge: 14.0,
          ),
        ),
        margin: ResponsiveHelper.getScreenHorizontalPadding(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(theme),
      body: ProtectedCourseContent(
        contentTitle: 'Student Details',
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Messages list
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  child: _buildMessagesList(currentUser),
                ),
              ),
              // Message input - no gap
              _buildMessageInput(theme),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Student Details',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      actions: [
        // Animated refresh button – spins while refreshing, disabled during
        // an in-progress refresh to prevent double-triggers
        AnimatedBuilder(
          animation: _refreshRotationAnimation,
          builder: (context, child) {
            return IconButton(
              icon: RotationTransition(
                turns: _refreshRotationAnimation,
                child: Icon(
                  Icons.refresh,
                  color: _isRefreshing ? Colors.grey[400] : Colors.black,
                ),
              ),
              onPressed: _isRefreshing ? null : _handleRefresh,
              tooltip: 'Refresh',
            );
          },
        ),
      ],
    );
  }

  Widget _buildMessagesList(User? currentUser) {
    return StreamBuilder<List<CommunityChatMessage>>(
      // Using a keyed stream so incrementing _streamKey forces a fresh
      // subscription (and therefore a genuine data reload) on refresh.
      key: ValueKey(_streamKey),
      stream: _chatService.getCommunityMessages(),
      builder: (context, snapshot) {
        // Show skeleton loader on initial load
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          return _buildErrorState('Error: ${snapshot.error}');
        }

        if (!snapshot.hasData) {
          return _buildLoadingState();
        }

        final messages = snapshot.data!;

        if (messages.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          cacheExtent: 500,
          itemCount: messages.length,
          padding: EdgeInsets.only(
            top: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 8.0,
              regular: 12.0,
              pro: 16.0,
              large: 20.0,
              extraLarge: 24.0,
            ),
            bottom: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 8.0,
              regular: 12.0,
              pro: 16.0,
              large: 20.0,
              extraLarge: 24.0,
            ),
          ),
          itemBuilder: (context, index) {
            final message = messages[index];
            final isCurrentUser = message.senderId == currentUser?.uid;

            return CommunityChatMessageBubble(
              key: ValueKey(message.id),
              message: message,
              isCurrentUser: isCurrentUser,
              onReply: () => _startReply(message),
              onScrollToMessage: _scrollToMessage,
              isHighlighted: _highlightedMessageId == message.id,
              highlightAnimation: _highlightAnimation,
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingState() {
    // Skeleton loader for smoother perceived performance
    return Container(
      color: Colors.grey[100],
      child: ListView.builder(
        padding: EdgeInsets.all(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 8.0,
            regular: 12.0,
            pro: 16.0,
            large: 20.0,
            extraLarge: 24.0,
          ),
        ),
        itemCount: 8,
        itemBuilder: (context, index) {
          final isMe = index % 3 == 0;
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 4.0,
                  regular: 6.0,
                  pro: 8.0,
                  large: 10.0,
                  extraLarge: 12.0,
                ),
                horizontal: ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 8.0,
                  regular: 12.0,
                  pro: 16.0,
                  large: 20.0,
                  extraLarge: 24.0,
                ),
              ),
              child: _buildSkeletonBubble(isMe),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonBubble(bool isMe) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: EdgeInsets.all(
        ResponsiveHelper.getAdaptiveSpacing(
          context,
          compact: 12.0,
          regular: 14.0,
          pro: 16.0,
          large: 18.0,
          extraLarge: 20.0,
        ),
      ),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[50] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender name skeleton
          if (!isMe)
            Container(
              width: 80,
              height: 10,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          // Message text skeleton
          Container(
            width: 140,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 100,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getScreenHorizontalPadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: ResponsiveHelper.adaptiveFontSize(context, 64.0),
              color: Theme.of(context).colorScheme.error,
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 16.0,
                regular: 20.0,
                pro: 24.0,
                large: 28.0,
                extraLarge: 32.0,
              ),
            ),
            Text(
              'Unable to load messages',
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 20.0),
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 8.0,
                regular: 10.0,
                pro: 12.0,
                large: 14.0,
                extraLarge: 16.0,
              ),
            ),
            Text(
              error,
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 16.0,
                regular: 20.0,
                pro: 24.0,
                large: 28.0,
                extraLarge: 32.0,
              ),
            ),
            // Retry button shown in the error state as well
            FilledButton.icon(
              onPressed: _isRefreshing ? null : _handleRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getScreenHorizontalPadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: ResponsiveHelper.adaptiveFontSize(context, 80.0),
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 16.0,
                regular: 20.0,
                pro: 24.0,
                large: 28.0,
                extraLarge: 32.0,
              ),
            ),
            Text(
              'Welcome to the Community!',
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 20.0),
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 8.0,
                regular: 10.0,
                pro: 12.0,
                large: 14.0,
                extraLarge: 16.0,
              ),
            ),
            Text(
              'Be the first to start the conversation.\nShare your thoughts and connect with others!',
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(ThemeData theme) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Reply input widget (if replying)
          if (_replyingToMessage != null)
            ReplyInputWidget(
              quotedMessage: _replyingToMessage,
              onCancelReply: _cancelReply,
              onSendReply: (text) {
                _messageController.text = text;
                _sendMessage();
              },
              textController: _messageController,
              focusNode: _inputFocusNode,
              isSending: _isSendingReply,
            ),

          // Regular message input
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Attachment Button
              GestureDetector(
                onTap: () {
                  _showAttachmentPicker(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.attach_file,
                    color: Colors.grey[600],
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Pill-shaped Text Input Field
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _inputFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[400],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: BorderSide.none,
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: BorderSide.none,
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: BorderSide.none,
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Send Button
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF1565C0),
                            ),
                          ),
                        )
                      : Icon(Icons.send, color: Colors.grey[600], size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAttachmentPicker(BuildContext context) {
    showAttachmentPicker(
      context,
      onAttachmentSelected: (AttachmentData attachment) {
        _sendAttachment(attachment);
      },
      onError: (String error) {
        _showSnackBar(error, isError: true);
      },
    );
  }

  Future<void> _sendAttachment(AttachmentData attachment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSending = true);

    try {
      // Get the actual user display name
      final senderName = await _getUserDisplayName();

      await _chatService.sendMessageWithAttachment(
        senderId: user.uid,
        senderName: senderName,
        attachment: attachment,
        text:
            _messageController.text.trim().isEmpty
                ? null
                : _messageController.text.trim(),
      );

      // Clear message input
      _messageController.clear();

      // Success feedback
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Failed to send attachment: ${e.toString()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }
}