import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/past_questions_message.dart';
import '../services/past_questions_service.dart';
import '../services/attachment_service.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../widgets/past_questions_message_bubble.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/protected_course_content.dart';
import '../utils/responsive_helper.dart';
import '../utils/logger.dart';

class PastQuestionsScreen extends StatefulWidget {
  const PastQuestionsScreen({super.key});

  @override
  State<PastQuestionsScreen> createState() => _PastQuestionsScreenState();
}

class _PastQuestionsScreenState extends State<PastQuestionsScreen>
    with TickerProviderStateMixin {
  final PastQuestionsService _chatService = PastQuestionsService();
  final AuthService _authService = AuthService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

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

    _refreshRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
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
        // Stop the spinner
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
    if (_messageController.text.trim().isEmpty || _isSending) return;

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

    setState(() => _isSending = true);

    try {
      // Get the actual user display name
      final senderName = await _getUserDisplayName();

      await _chatService.sendMessage(
        senderId: user.uid,
        senderName: senderName,
        text: messageText,
      );

      // Success feedback
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to send message: ${e.toString()}', isError: true);
        // Restore message text on error
        _messageController.text = messageText;
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
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
        contentTitle: 'Past Questions',
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
        'Past Questions',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      actions: [
        // Animated refresh button – spins while refreshing, shows a subtle
        // disabled appearance when a refresh is already in progress
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
    return StreamBuilder<List<PastQuestionsMessage>>(
      // Using a keyed stream so incrementing _streamKey forces a fresh
      // subscription (and therefore a genuine data reload) on refresh.
      key: ValueKey(_streamKey),
      stream: _chatService.getPastQuestionsMessages(),
      builder: (context, snapshot) {
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
          physics: const BouncingScrollPhysics(),
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

            return PastQuestionsMessageBubble(
              key: ValueKey(message.id),
              message: message,
              isCurrentUser: isCurrentUser,
              onReply: () => HapticFeedback.selectionClick(),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: ResponsiveHelper.adaptiveFontSize(context, 48.0),
            height: ResponsiveHelper.adaptiveFontSize(context, 48.0),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
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
            'Loading past questions...',
            style: TextStyle(
              fontSize: ResponsiveHelper.adaptiveFontSize(context, 16.0),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              Icons.quiz_outlined,
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
              'Welcome to Past Questions!',
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
              'Be the first to share a past exam question.\nHelp your fellow students prepare for exams!',
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
      child: Row(
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
                border: Border.all(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
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
                  : Icon(
                      Icons.send,
                      color: Colors.grey[600],
                      size: 24,
                    ),
            ),
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