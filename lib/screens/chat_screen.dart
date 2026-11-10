import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../services/attachment_service.dart';
import '../utils/app_colors.dart';
import '../utils/chat_merge.dart';
import '../widgets/attachment_picker.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../widgets/protected_course_content.dart';

import '../widgets/message_bubble.dart';
import '../widgets/new_message_entrance.dart';
import '../widgets/reply_input_widget.dart';

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
  // Compound cursor for correct cross-query pagination.
  Timestamp? _lastCursorTimestamp;
  String? _lastCursorId;
  String? _error;
  final int _messagesPerBatch = 20;

  // Reply functionality state
  Map<String, dynamic>? _replyingToMessage;
  bool _isSendingReply = false;

  // Message highlighting state
  String? _highlightedMessageId;
  late AnimationController _highlightAnimationController;
  late Animation<double> _highlightAnimation;

  // Scroll-to-message state
  bool _isScrollingToMessage = false;
  String? _searchingForMessageId;

  late AnimationController _inputAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _inputScaleAnimation;
  late Animation<double> _fabScaleAnimation;

  // ── Entrance animation tracking ──
  // Only ids/clientIds in this set will play the entrance animation.
  // Messages from cache, initial load, and pagination are NEVER added.
  final Set<String> _entering = {};

  // ── Pending incoming messages (user is scrolled up) ──
  // Held here instead of inserting into _messages, to avoid shifting the
  // scroll position. Merged in when the user taps the pill or scrolls back
  // near the bottom.
  List<Map<String, dynamic>> _pendingIncoming = [];

  // ── Pending full replace (stale cache while scrolled up) ──
  // When mergeFetchedPage returns wasReplaced but the user is scrolled up,
  // store the fetched page here. Applied on pill tap / scroll-to-bottom.
  // Not null when a deferred replace is waiting.
  List<Map<String, dynamic>>? _pendingReplace;

  // ── Live listener for incoming messages ──
  StreamSubscription<({String id, String? senderId, String? clientId})?>?
      _newestMessageSub;
  String? _lastKnownNewestId;

  // ── Refresh guard: prevents overlapping silent refreshes ──
  bool _isRefreshing = false;
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupScrollListener();
    _setupInputListener();

    // ── Cache-first instant open ──
    final cached = ChatService.cachedMessages;
    if (cached.isNotEmpty) {
      _messages = cached;
      _isLoading = false;
      _hasMoreMessages = cached.length >= _messagesPerBatch;
      _extractCursor(cached);
      // Silently refresh in the background — don't show spinner.
      _requestSilentRefresh();
    } else {
      // No cache — show skeleton, then load.
      _loadInitialMessages();
    }

    // Start listening for new incoming messages in real time.
    _startLiveListener();
  }

  /// Extract the compound cursor (timestamp + docId) from the last message
  /// in a list. Works with both cached and freshly-fetched messages.
  void _extractCursor(List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) return;
    final last = messages.last;
    _lastCursorTimestamp = last['_firestoreTimestamp'] as Timestamp?;
    _lastCursorId = last['id'] as String?;
  }

  /// Lightweight Firestore listener (3× limit-1 queries merged) that detects
  /// new messages in real time and triggers a silent refresh.
  void _startLiveListener() {
    _newestMessageSub = _chatService.newestMessageStream().listen((event) {
      if (!mounted || event == null) return;
      if (event.id == _lastKnownNewestId) return;

      // If this message is already in our list (by doc id), nothing to do.
      if (_messages.any((m) => m['id'] == event.id) ||
          _pendingIncoming.any((m) => m['id'] == event.id) ||
          (_pendingReplace?.any((m) => m['id'] == event.id) ?? false)) {
        _lastKnownNewestId = event.id;
        return;
      }

      // Skip ONLY if this is our own in-flight send: the emitted doc's
      // clientId matches a temp-* bubble we're still holding. _sendMessage
      // will swap it in place. Everything else (admin messages, broadcasts,
      // other users' messages) always triggers a refresh.
      if (event.clientId != null) {
        final isOwnInFlight = _messages.any((m) {
          final id = m['id'] as String?;
          return m['clientId'] == event.clientId &&
              id != null &&
              id.startsWith('temp-');
        });
        if (isOwnInFlight) {
          _lastKnownNewestId = event.id;
          return;
        }
      }

      // Don't set _lastKnownNewestId yet — only after a successful refresh.
      // If the fetch fails (flaky network), the next event for the same id
      // must retry instead of being silently skipped.
      _requestSilentRefresh(pendingNewestId: event.id);
    });
  }

  /// Guarded entry point for silent refreshes. Prevents overlapping fetches:
  /// if a refresh is already running, queues exactly one follow-up.
  /// [pendingNewestId] — the newest-message id that triggered this refresh;
  /// set as [_lastKnownNewestId] only on success.
  void _requestSilentRefresh({String? pendingNewestId}) {
    if (_isRefreshing) {
      _refreshQueued = true;
      return;
    }
    _doSilentRefresh(pendingNewestId: pendingNewestId);
  }

  Future<void> _doSilentRefresh({String? pendingNewestId}) async {
    _isRefreshing = true;
    _refreshQueued = false;
    try {
      await _loadInitialMessages(silent: true);
      // Only mark the id as processed after a successful refresh.
      if (pendingNewestId != null) {
        _lastKnownNewestId = pendingNewestId;
      }
    } finally {
      _isRefreshing = false;
      // If another refresh was requested while we were running, run one more.
      if (_refreshQueued && mounted) {
        _refreshQueued = false;
        _doSilentRefresh();
      }
    }
  }

  void _initializeAnimations() {
    // Initialize highlight animation for scroll-to-message
    _highlightAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _highlightAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _highlightAnimationController,
      curve: Curves.easeInOut,
    ));

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
      if (!mounted) return;

      // Pagination: load more when near the top (oldest messages).
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingMore &&
          _hasMoreMessages) {
        _loadMoreMessages();
      }

      // Merge pending incoming / apply deferred replace when near bottom.
      if (_scrollController.offset < 100) {
        if (_pendingReplace != null) {
          _applyPendingReplace();
        } else if (_pendingIncoming.isNotEmpty) {
          _mergePendingIncoming();
        }
      }
    });
  }

  Future<void> _loadInitialMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final fetched = await _chatService.getMessagesPaginated(
        limit: _messagesPerBatch,
      );

      if (!mounted) return;

      if (!silent) {
        // ── First load (no existing messages) — just set the list. ──
        setState(() {
          _messages = fetched;
          _isLoading = false;
          _hasMoreMessages = fetched.length >= _messagesPerBatch;
          _extractCursor(fetched);
        });
        ChatService.updateCache(fetched);
        return;
      }

      // ── Silent refresh: merge page-1 into the existing list. ──
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final result = mergeFetchedPage(
        existing: _messages,
        fetched: fetched,
        currentUid: currentUid,
      );

      final isNearBottom = !_scrollController.hasClients ||
          _scrollController.offset < 100;

      if (result.wasReplaced) {
        if (isNearBottom) {
          // Stale cache, near bottom — apply immediately.
          setState(() {
            _messages = result.messages;
            _hasMoreMessages = fetched.length >= _messagesPerBatch;
            _extractCursor(fetched);
            _pendingIncoming = [];
            _pendingReplace = null;
          });
          // Animate incoming messages.
          for (final key in result.newIncomingKeys) {
            _entering.add(key);
          }
        } else {
          // Stale cache, scrolled up — defer the replace.
          // Don't touch _messages, cursor, or scroll position.
          setState(() {
            _pendingReplace = fetched;
            // Clear any older pending incoming — they're obsolete now.
            _pendingIncoming = [];
          });
        }
      } else if (result.newIncomingKeys.isEmpty) {
        // No new messages — just update existing entries in-place.
        setState(() {
          _messages = result.messages;
        });
      } else if (isNearBottom) {
        // Near bottom — insert new messages directly and animate.
        for (final key in result.newIncomingKeys) {
          _entering.add(key);
        }
        setState(() {
          _messages = result.messages;
        });
        // Auto-scroll to bottom.
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      } else {
        // Scrolled up — hold new messages in _pendingIncoming.
        // Update existing entries in-place (keys that already existed).
        // But do NOT insert the new messages into _messages.
        final updatedWithoutNew = mergeFetchedPage(
          existing: _messages,
          fetched: fetched.where((msg) {
            final key =
                (msg['clientId'] as String?) ?? (msg['id'] as String?) ?? '';
            return !result.newIncomingKeys.contains(key);
          }).toList(),
          currentUid: currentUid,
        );
        setState(() {
          _messages = updatedWithoutNew.messages;
          // Add genuinely new messages to pending.
          for (final msg in fetched) {
            final key =
                (msg['clientId'] as String?) ?? (msg['id'] as String?) ?? '';
            if (result.newIncomingKeys.contains(key)) {
              // Avoid duplicates in pending.
              if (!_pendingIncoming.any((m) =>
                  ((m['clientId'] as String?) ?? (m['id'] as String?)) ==
                  key)) {
                _pendingIncoming.add(msg);
              }
            }
          }
        });
      }

      // Only set cursor if we didn't have one (first load from cache path).
      if (_lastCursorTimestamp == null && fetched.isNotEmpty) {
        _extractCursor(fetched);
      }

      // Cache only the latest page.
      ChatService.updateCache(fetched);
    } catch (e) {
      if (!mounted) return;

      // In silent mode, swallow the error — stale cache is better than a
      // spinner or error screen. Do NOT mark _lastKnownNewestId; the caller
      // (_doSilentRefresh) only marks it on success.
      if (silent) {
        Logger.w('Silent refresh failed (keeping cache): $e');
        return;
      }

      setState(() {
        _error = 'Error loading messages: $e';
        _isLoading = false;
      });
      Logger.e('Error loading initial messages: $e');
    }
  }

  /// Merge pending incoming messages into _messages and scroll to bottom.
  /// Called when the user taps the "new messages" pill or scrolls near bottom.
  void _mergePendingIncoming() {
    if (_pendingIncoming.isEmpty) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // Add animation keys for the pending messages.
    for (final msg in _pendingIncoming) {
      final key =
          (msg['clientId'] as String?) ?? (msg['id'] as String?) ?? '';
      if (key.isNotEmpty && msg['senderId'] != currentUid) {
        _entering.add(key);
      }
    }

    // Merge pending into the existing list.
    final merged = mergeFetchedPage(
      existing: _messages,
      fetched: _pendingIncoming,
      currentUid: currentUid,
    );

    setState(() {
      _messages = merged.messages;
      _pendingIncoming = [];
    });

    // Scroll to bottom.
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// Apply a deferred full replace (stale cache while scrolled up).
  /// Replaces _messages with the stored fetched page, keeping in-flight
  /// temp-* bubbles pinned at front. Resets cursor and pagination.
  /// No entrance animations — the user is jumping to a fresh view.
  void _applyPendingReplace() {
    if (!mounted) return;
    final fetched = _pendingReplace;
    if (fetched == null) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // mergeFetchedPage with the current _messages preserves in-flight temps
    // and returns wasReplaced=true with temps pinned at front.
    final result = mergeFetchedPage(
      existing: _messages,
      fetched: fetched,
      currentUid: currentUid,
    );

    setState(() {
      _messages = result.messages;
      _hasMoreMessages = fetched.length >= _messagesPerBatch;
      _pendingReplace = null;
      _pendingIncoming = [];
    });
    _extractCursor(fetched);

    // Jump to bottom with no animation on the messages.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    // The stored page may be minutes old — refresh to catch anything newer.
    _requestSilentRefresh();
  }

  /// Pill tap handler — applies a deferred replace if one is pending,
  /// otherwise merges pending incoming messages.
  void _onPendingPillTapped() {
    if (!mounted) return;
    if (_pendingReplace != null) {
      _applyPendingReplace();
    } else {
      _mergePendingIncoming();
    }
  }

  /// Label for the "new messages" pill.
  String get _pendingPillLabel {
    if (_pendingReplace != null) {
      return 'New messages';
    }
    final n = _pendingIncoming.length;
    return n == 1 ? '1 new message' : '$n new messages';
  }

  Future<void> _loadMoreMessages() async {
    if (!_hasMoreMessages || _lastCursorTimestamp == null || _lastCursorId == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final moreMessages = await _chatService.getMessagesPaginated(
        lastTimestamp: _lastCursorTimestamp,
        lastId: _lastCursorId,
        limit: _messagesPerBatch,
      );

      if (!mounted) return;

      setState(() {
        if (moreMessages.isNotEmpty) {
          _messages.addAll(moreMessages);
          _extractCursor(moreMessages);
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
    if (text.isEmpty || _isSending || _isSendingReply) return;

    // Haptic feedback
    HapticFeedback.lightImpact();

    // Animation feedback
    _fabAnimationController.forward().then((_) {
      _fabAnimationController.reverse();
    });

    setState(() {
      _isSending = true;
      _isSendingReply = _replyingToMessage != null;
    });

    // ── Stable clientId for optimistic messages ──
    final clientId = 'c-${DateTime.now().microsecondsSinceEpoch}';

    // Optimistic UI: insert a temporary bubble
    final tempMessage = <String, dynamic>{
      'id': 'temp-$clientId',
      'clientId': clientId,
      'text': text,
      'senderId': FirebaseAuth.instance.currentUser?.uid,
      'timestamp': DateTime.now(),
      'status': 'sending',
    };

    // Mark for entrance animation
    _entering.add(clientId);

    setState(() {
      _messages.insert(0, tempMessage);
    });
    _messageController.clear();

    // Ensure newest is visible
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );

    try {
      final result = await _chatService.sendMessage(
        text: text,
        replyToMessageId: _replyingToMessage?['id'],
        clientId: clientId,
      );

      if (!result['success']) {
        if (mounted) {
          _showSnackBar('Error: ${result['error']}', isError: true);
          // Remove temp message and restore text on error
          setState(() {
            final idx = _messages.indexWhere((m) => m['clientId'] == clientId);
            if (idx != -1) {
              _messages.removeAt(idx);
            }
          });
          _entering.remove(clientId);
          _messageController.text = text;
        }
      } else {
        // Success feedback
        HapticFeedback.selectionClick();
        // Upgrade optimistic bubble IN PLACE — keep the same clientId so
        // the ValueKey stays stable and the widget is NOT remounted.
        final String? newId = result['messageId'] as String?;
        setState(() {
          final idx = _messages.indexWhere((m) => m['clientId'] == clientId);
          if (idx != -1) {
            _messages[idx]['status'] = 'sent';
            if (newId != null) {
              _messages[idx]['id'] = newId;
            }
          }
          // Clear reply state after successful send
          if (_replyingToMessage != null) {
            _replyingToMessage = null;
          }
        });

        // Update cache after successful send.
        ChatService.updateCache(_messages);

        // Keep scrolled to newest
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
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
          final idx = _messages.indexWhere((m) => m['clientId'] == clientId);
          if (idx != -1) {
            _messages.removeAt(idx);
          }
        });
        _entering.remove(clientId);
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
  void _startReply(Map<String, dynamic> message) {
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
  /// Implements WhatsApp-style message navigation with visual feedback for private chat
  Future<void> _scrollToMessage(String messageId) async {
    Logger.i('Scroll-to-message requested for ID: $messageId');
    
    if (_isScrollingToMessage || messageId.isEmpty) {
      Logger.w('Scroll operation already in progress or empty messageId');
      return;
    }

    setState(() {
      _isScrollingToMessage = true;
      _searchingForMessageId = messageId;
    });

    try {
      // Find the target message index in current loaded messages
      final messageIndex = _messages.indexWhere((msg) => msg['id'] == messageId);
      Logger.i('Message index found: $messageIndex out of ${_messages.length} messages');
      
      if (messageIndex == -1) {
        // Message not found in current loaded messages
        Logger.w('Message not found in current loaded messages');
        await _handleMessageNotFound(messageId);
        return;
      }

      // Calculate scroll position
      // Private chat uses reversed ListView, same as community chat
      final itemHeight = _estimateMessageHeight();
      final targetScrollOffset = messageIndex * itemHeight;
      Logger.i('Calculated scroll offset: $targetScrollOffset (itemHeight: $itemHeight)');
      
      // Smooth scroll to the target message
      await _performSmoothScroll(targetScrollOffset);
      
      // Highlight the message
      await _highlightMessage(messageId);
      
      Logger.i('Scroll-to-message completed successfully');
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
  /// This is a rough estimate - in a production app, you might want to measure actual heights
  double _estimateMessageHeight() {
    // Base message bubble height + padding + margins
    // This is an approximation - actual heights vary based on content
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
  /// In a production app, this might trigger loading more messages or searching history
  Future<void> _handleMessageNotFound(String messageId) async {
    Logger.w('Message not found in current view: $messageId');
    
    // For now, show an error message
    // In a full implementation, you might:
    // 1. Load more messages from history
    // 2. Search in the database
    // 3. Show a "message not available" dialog
    _showSnackBar('Message not found or may have been deleted', isError: true);
    
    // You could implement pagination loading here:
    // await _loadMoreMessagesUntilFound(messageId);
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
    _newestMessageSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _inputAnimationController.dispose();
    _fabAnimationController.dispose();
    _highlightAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(theme),
      body: ProtectedCourseContent(
        contentTitle: 'Admin Chat',
        child: SafeArea(
          bottom: false, // Remove bottom safe area padding
          child: _buildBody(),
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
        'Chat',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.black),
          onPressed: () => _loadInitialMessages(),
          tooltip: 'Refresh',
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
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: Stack(
              children: [
                _buildMessagesList(),
                // "N new messages" pill — shown when messages are held pending
                // or a full replace is deferred.
                if (_pendingIncoming.isNotEmpty || _pendingReplace != null)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _onPendingPillTapped,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.arrow_downward,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _pendingPillLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Message input - no gap
        _buildMessageInput(),
      ],
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
        itemCount: 8, // Show 8 skeleton items
        itemBuilder: (context, index) {
          final isMe = index % 2 == 0;
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
        maxWidth: MediaQuery.of(context).size.width * 0.7,
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          SizedBox(height: 8),
          Container(
            width: 80,
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
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      // Add cacheExtent for smoother scrolling
      cacheExtent: 500,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _messages.length + (_hasMoreMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _isLoadingMore
              ? Container(
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
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Loading more...',
                        style: TextStyle(
                          fontSize: ResponsiveHelper.adaptiveFontSize(context, 13.0),
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

    // ── Stable key: prefer clientId (survives optimistic→confirmed upgrade)
    // over Firestore id, with index as last resort.
    final animKey =
        (message['clientId'] as String?) ?? (message['id'] as String?) ?? '$index';

    final shouldAnimate = _entering.contains(animKey);

    final bubble = MessageBubble(
      key: ValueKey(animKey),
      message: message,
      isMe: isMe,
      status: 'sent',
      onReply: () => _startReply(message),
      isHighlighted: _highlightedMessageId == message['id'],
      highlightAnimation: _highlightAnimation,
      onScrollToMessage: _scrollToMessage,
      // Disable MessageBubble's own slide+scale for non-entering messages
      // AND for entering messages (NewMessageEntrance handles their anim).
      animate: false,
    );

    if (shouldAnimate) {
      return NewMessageEntrance(
        key: ValueKey('enter-$animKey'),
        animate: true,
        isMe: isMe,
        onDone: () {
          // Remove without setState so recycled items never re-animate.
          _entering.remove(animKey);
        },
        child: bubble,
      );
    }

    return bubble;
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
          
          // Pill-shaped Text Input Field (matching search bar design)
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
                    // Explicitly set all border states to maintain rounded corners
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
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
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

  Widget _buildReplyInputWidget() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.getAdaptiveSpacing(
          context,
          compact: 8.0,
          regular: 10.0,
          pro: 12.0,
          large: 14.0,
          extraLarge: 16.0,
        ),
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
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 12.0,
            regular: 14.0,
            pro: 16.0,
            large: 18.0,
            extraLarge: 20.0,
          ),
        ),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Vertical line indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          SizedBox(
            width: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 12.0,
              regular: 14.0,
              pro: 16.0,
              large: 18.0,
              extraLarge: 20.0,
            ),
          ),
          
          // Quoted message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sender name
                Text(
                  'Replying to ${_replyingToMessage?['senderName'] ?? 'Unknown'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                    fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
                  ),
                ),
                
                SizedBox(
                  height: ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 4.0,
                    regular: 6.0,
                    pro: 8.0,
                    large: 8.0,
                    extraLarge: 10.0,
                  ),
                ),
                
                // Quoted message text
                Text(
                  _replyingToMessage?['text'] ?? '',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Cancel reply button
          IconButton(
            onPressed: _cancelReply,
            icon: Icon(
              Icons.close,
              size: ResponsiveHelper.adaptiveFontSize(context, 20.0),
              color: colorScheme.onSurfaceVariant,
            ),
            padding: EdgeInsets.all(
              ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 4.0,
                regular: 6.0,
                pro: 8.0,
                large: 8.0,
                extraLarge: 10.0,
              ),
            ),
            constraints: const BoxConstraints(),
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
    setState(() => _isSending = true);

    try {
      final result = await _chatService.sendMessageWithAttachment(
        attachment: attachment,
        text:
            _messageController.text.trim().isEmpty
                ? null
                : _messageController.text.trim(),
      );

      if (!result['success']) {
        if (mounted) {
          _showSnackBar('Error: ${result['error']}', isError: true);
        }
      } else {
        // Clear message input
        _messageController.clear();

        // Success feedback
        HapticFeedback.selectionClick();

        // Reload messages to show the new attachment (guarded).
        _requestSilentRefresh();

        // Scroll to the bottom so the user sees their own attachment.
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error sending attachment: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }
}