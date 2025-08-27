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
  late Animation<double> _inputScaleAnimation;
  late Animation<double> _fabScaleAnimation;

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

    _inputScaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(
        parent: _inputAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _fabScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeInOut),
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
    super.dispose();
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
      backgroundColor: theme.colorScheme.surface,
      appBar: _buildAppBar(theme),
      body: ProtectedCourseContent(
        contentTitle: 'Student Details',
        child: SafeArea(
          child: Column(
            children: [
              // Messages list
              Expanded(child: _buildMessagesList(currentUser)),
              // Message input
              _buildMessageInput(theme),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      title: Text(
        'Student Details',
        style: TextStyle(
          fontSize: ResponsiveHelper.adaptiveFontSize(context, 18.0),
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onPrimary,
        ),
      ),
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
      elevation: 0,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.1),
      surfaceTintColor: Colors.transparent,
    );
  }

  Widget _buildMessagesList(User? currentUser) {
    return StreamBuilder<List<CommunityChatMessage>>(
      stream: _chatService.getCommunityMessages(),
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

            return CommunityChatMessageBubble(
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
            'Loading community messages...',
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
      padding: EdgeInsets.all(
        ResponsiveHelper.getAdaptiveSpacing(
          context,
          compact: 12.0,
          regular: 16.0,
          pro: 20.0,
          large: 24.0,
          extraLarge: 28.0,
        ),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: ScaleTransition(
        scale: _inputScaleAnimation,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment button
            Container(
              width: ResponsiveHelper.adaptiveFontSize(context, 48.0),
              height: ResponsiveHelper.adaptiveFontSize(context, 48.0),
              margin: EdgeInsets.only(
                right: ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 8.0,
                  regular: 12.0,
                  pro: 16.0,
                  large: 20.0,
                  extraLarge: 24.0,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap:
                      _isSending ? null : () => _showAttachmentPicker(context),
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 24.0,
                      regular: 28.0,
                      pro: 32.0,
                      large: 36.0,
                      extraLarge: 40.0,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(
                        ResponsiveHelper.getAdaptiveSpacing(
                          context,
                          compact: 24.0,
                          regular: 28.0,
                          pro: 32.0,
                          large: 36.0,
                          extraLarge: 40.0,
                        ),
                      ),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      Icons.attach_file_rounded,
                      size: ResponsiveHelper.adaptiveFontSize(context, 20.0),
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

            // Message input field
            Expanded(
              child: Container(
                constraints: BoxConstraints(
                  minHeight: ResponsiveHelper.adaptiveFontSize(context, 48.0),
                  maxHeight: ResponsiveHelper.adaptiveFontSize(context, 120.0),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _inputFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Send a message to the community...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        ResponsiveHelper.getAdaptiveSpacing(
                          context,
                          compact: 24.0,
                          regular: 28.0,
                          pro: 32.0,
                          large: 36.0,
                          extraLarge: 40.0,
                        ),
                      ),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        ResponsiveHelper.getAdaptiveSpacing(
                          context,
                          compact: 24.0,
                          regular: 28.0,
                          pro: 32.0,
                          large: 36.0,
                          extraLarge: 40.0,
                        ),
                      ),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        ResponsiveHelper.getAdaptiveSpacing(
                          context,
                          compact: 24.0,
                          regular: 28.0,
                          pro: 32.0,
                          large: 36.0,
                          extraLarge: 40.0,
                        ),
                      ),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.getAdaptiveSpacing(
                        context,
                        compact: 16.0,
                        regular: 20.0,
                        pro: 24.0,
                        large: 28.0,
                        extraLarge: 32.0,
                      ),
                      vertical: ResponsiveHelper.getAdaptiveSpacing(
                        context,
                        compact: 12.0,
                        regular: 14.0,
                        pro: 16.0,
                        large: 18.0,
                        extraLarge: 20.0,
                      ),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: ResponsiveHelper.adaptiveFontSize(context, 16.0),
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),

            SizedBox(
              width: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 8.0,
                regular: 12.0,
                pro: 16.0,
                large: 20.0,
                extraLarge: 24.0,
              ),
            ),

            // Send button
            ScaleTransition(
              scale: _fabScaleAnimation,
              child: Container(
                width: ResponsiveHelper.adaptiveFontSize(context, 48.0),
                height: ResponsiveHelper.adaptiveFontSize(context, 48.0),
                child: FilledButton(
                  onPressed: _isSending ? null : _sendMessage,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    disabledBackgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        ResponsiveHelper.getAdaptiveSpacing(
                          context,
                          compact: 24.0,
                          regular: 28.0,
                          pro: 32.0,
                          large: 36.0,
                          extraLarge: 40.0,
                        ),
                      ),
                    ),
                    elevation: ResponsiveHelper.getAdaptiveElevation(context),
                  ),
                  child:
                      _isSending
                          ? SizedBox(
                            width: ResponsiveHelper.adaptiveFontSize(
                              context,
                              20.0,
                            ),
                            height: ResponsiveHelper.adaptiveFontSize(
                              context,
                              20.0,
                            ),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                          : Icon(
                            Icons.send_rounded,
                            size: ResponsiveHelper.adaptiveFontSize(
                              context,
                              20.0,
                            ),
                          ),
                ),
              ),
            ),
          ],
        ),
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
