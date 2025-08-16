import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../widgets/protected_course_content.dart';

import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final ChatService _chatService = ChatService();
  final FocusNode _inputFocusNode = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _isSending = false;
  DocumentSnapshot? _lastDocument;
  String? _error;
  final int _messagesPerBatch = 20;

  late AnimationController _inputAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _inputScaleAnimation;
  late Animation<double> _fabScaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadInitialMessages();
    _setupScrollListener();
    _setupInputListener();
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

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingMore &&
          _hasMoreMessages) {
        _loadMoreMessages();
      }
    });
  }

  Future<void> _loadInitialMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final messages = await _chatService.getMessagesPaginated(
        limit: _messagesPerBatch,
      );

      setState(() {
        _messages = messages;
        _isLoading = false;
        _hasMoreMessages = messages.length >= _messagesPerBatch;

        if (messages.isNotEmpty) {
          _lastDocument = messages.last['document'];
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading messages: $e';
        _isLoading = false;
      });
      Logger.e('Error loading initial messages: $e');
    }
  }

  Future<void> _loadMoreMessages() async {
    if (!_hasMoreMessages || _lastDocument == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final moreMessages = await _chatService.getMessagesPaginated(
        lastDocument: _lastDocument,
        limit: _messagesPerBatch,
      );

      if (!mounted) return;

      setState(() {
        if (moreMessages.isNotEmpty) {
          _messages.addAll(moreMessages);
          _lastDocument = moreMessages.last['document'];
        }

        _hasMoreMessages = moreMessages.length >= _messagesPerBatch;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingMore = false;
      });
      Logger.e('💬 ChatScreen: Error loading more messages: $e');
      if (mounted) {
        _showSnackBar('Error loading more messages', isError: true);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    // Haptic feedback
    HapticFeedback.lightImpact();

    // Animation feedback
    _fabAnimationController.forward().then((_) {
      _fabAnimationController.reverse();
    });

    setState(() {
      _isSending = true;
    });

    // Optimistic UI: insert a temporary bubble
    final tempMessage = <String, dynamic>{
      'id': 'temp-${DateTime.now().millisecondsSinceEpoch}',
      'text': text,
      'senderId': FirebaseAuth.instance.currentUser?.uid,
      'timestamp': DateTime.now(),
      'status': 'sending',
    };

    setState(() {
      _messages.insert(0, tempMessage);
    });
    _messageController.clear();

    // Ensure newest is visible
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );

    try {
      final result = await _chatService.sendMessage(text: text);

      if (!result['success']) {
        if (mounted) {
          _showSnackBar('Error: ${result['error']}', isError: true);
          // Remove temp message and restore text on error
          setState(() {
            if (_messages.isNotEmpty &&
                _messages.first['id'] == tempMessage['id']) {
              _messages.removeAt(0);
            }
          });
          _messageController.text = text;
        }
      } else {
        // Success feedback
        HapticFeedback.selectionClick();
        // Upgrade optimistic bubble to real one without reloading the whole list
        final String? newId = result['messageId'] as String?;
        setState(() {
          if (_messages.isNotEmpty &&
              _messages.first['id'] == tempMessage['id']) {
            _messages.first['status'] = 'sent';
            if (newId != null) {
              _messages.first['id'] = newId;
            }
          }
        });
        // Keep scrolled to newest
        if (mounted) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error sending message: $e', isError: true);
        _messageController.text = text;
        // Rollback optimistic insert
        setState(() {
          if (_messages.isNotEmpty &&
              _messages.first['id'] == tempMessage['id']) {
            _messages.removeAt(0);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
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
          borderRadius: BorderRadius.circular(
            ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 8.0,
              regular: 10.0,
              pro: 12.0,
              large: 12.0,
              extraLarge: 14.0,
            ),
          ),
        ),
        margin: ResponsiveHelper.getScreenHorizontalPadding(context),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _buildAppBar(theme),
      body: ProtectedCourseContent(
        contentTitle: 'Admin Chat',
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chat with Admin',
            style: TextStyle(
              fontSize: ResponsiveHelper.adaptiveFontSize(context, 20.0),
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          Text(
            _messages.isEmpty ? 'Loading...' : '${_messages.length} messages',
            style: TextStyle(
              fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
      elevation: 0,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.1),
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadInitialMessages,
          tooltip: 'Refresh messages',
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.1),
            foregroundColor: theme.colorScheme.onPrimary,
          ),
        ),

        SizedBox(
          width: ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 8.0,
            regular: 12.0,
            pro: 16.0,
            large: 16.0,
            extraLarge: 20.0,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    return Column(
      children: [
        // Messages list
        Expanded(child: _buildMessagesList()),
        // Message input
        _buildMessageInput(),
      ],
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
            'Loading messages...',
            style: TextStyle(
              fontSize: ResponsiveHelper.adaptiveFontSize(context, 16.0),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
              'Something went wrong',
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
              _error!,
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 24.0,
                regular: 28.0,
                pro: 32.0,
                large: 36.0,
                extraLarge: 40.0,
              ),
            ),
            FilledButton.icon(
              onPressed: _loadInitialMessages,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 20.0,
                    regular: 24.0,
                    pro: 28.0,
                    large: 32.0,
                    extraLarge: 36.0,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      itemCount: _messages.length + (_hasMoreMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _isLoadingMore
              ? Container(
                padding: EdgeInsets.all(
                  ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 16.0,
                    regular: 20.0,
                    pro: 24.0,
                    large: 28.0,
                    extraLarge: 32.0,
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: ResponsiveHelper.adaptiveFontSize(context, 24.0),
                    height: ResponsiveHelper.adaptiveFontSize(context, 24.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              )
              : const SizedBox.shrink();
        }
        final message = _messages[index];
        return _buildMessageItem(message, index);
      },
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> message, int index) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMe = message['senderId'] == currentUser?.uid;

    return MessageBubble(
      key: ValueKey(message['id'] ?? index),
      message: message,
      isMe: isMe,
      status: 'sent',
      onReply: () => HapticFeedback.selectionClick(),
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
              Icons.chat_bubble_outline_rounded,
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
              'No messages yet',
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
              'Start a conversation with your admin',
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);

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
                    hintText: 'Type your message...',
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
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
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
}
