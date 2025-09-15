import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/attachment_service.dart';
import '../widgets/attachment_preview.dart';
import '../utils/responsive_helper.dart';

class MessageBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String status;
  final VoidCallback onReply;
  final bool showAvatar;
  final bool isHighlighted;
  final Animation<double>? highlightAnimation;
  final Function(String messageId)? onScrollToMessage;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.status,
    required this.onReply,
    this.showAvatar = true,
    this.isHighlighted = false,
    this.highlightAnimation,
    this.onScrollToMessage,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _slideAnimation = Tween<Offset>(
      begin: widget.isMe ? const Offset(0.3, 0) : const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final replyToMessageId = widget.message['replyToMessageId'] as String?;

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Padding(
          padding: EdgeInsets.only(
            left:
                widget.isMe
                    ? ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 20.0,
                      regular: 25.0,
                      pro: 30.0,
                      large: 35.0,
                      extraLarge: 40.0,
                    )
                    : ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 8.0,
                      regular: 10.0,
                      pro: 12.0,
                      large: 12.0,
                      extraLarge: 14.0,
                    ),
            right:
                widget.isMe
                    ? ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 6.0,
                      regular: 8.0,
                      pro: 10.0,
                      large: 10.0,
                      extraLarge: 12.0,
                    )
                    : ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 3.0,
                      regular: 4.0,
                      pro: 5.0,
                      large: 5.0,
                      extraLarge: 6.0,
                    ),
            top: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 6.0,
              regular: 8.0,
              pro: 8.0,
              large: 10.0,
              extraLarge: 12.0,
            ),
            bottom: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 6.0,
              regular: 8.0,
              pro: 8.0,
              large: 10.0,
              extraLarge: 12.0,
            ),
          ),
          child: Row(
            mainAxisAlignment:
                widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar for received messages
              if (!widget.isMe && widget.showAvatar) ...[
                _buildAvatar(context),
                SizedBox(
                  width: ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 8.0,
                    regular: 10.0,
                    pro: 12.0,
                    large: 12.0,
                    extraLarge: 14.0,
                  ),
                ),
              ],

              // Message content
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      widget.isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                  children: [
                    // Reply indicator
                    if (replyToMessageId != null)
                      _buildReplyIndicator(context, replyToMessageId),

                    // Main message bubble
                    _buildMessageContent(context, theme, colorScheme),

                    // Timestamp and status
                    SizedBox(
                      height: ResponsiveHelper.getAdaptiveSpacing(
                        context,
                        compact: 4.0,
                        regular: 6.0,
                        pro: 6.0,
                        large: 8.0,
                        extraLarge: 8.0,
                      ),
                    ),
                    _buildMessageMeta(context, theme),
                  ],
                ),
              ),

              // No spacer needed for sent messages since they don't show avatars
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final senderName = widget.message['senderName'] as String? ?? 'Unknown';
    final avatarSize = ResponsiveHelper.adaptiveFontSize(context, 32.0);

    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primaryContainer,
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: ResponsiveHelper.getAdaptiveElevation(context),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildReplyIndicator(BuildContext context, String replyToMessageId) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: FirebaseFirestore.instance
          .collection('messages')
          .doc(replyToMessageId)
          .get()
          .then((doc) => doc.exists ? {'id': doc.id, ...doc.data()!} : null),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final replyMessage = snapshot.data;
        if (replyMessage == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            // Provide haptic feedback for better user experience
            HapticFeedback.selectionClick();
            // Scroll to the original message
            if (widget.onScrollToMessage != null) {
              widget.onScrollToMessage!(replyToMessageId);
            }
          },
          child: Container(
            margin: EdgeInsets.only(
              bottom: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 6.0,
                regular: 8.0,
                pro: 8.0,
                large: 10.0,
                extraLarge: 12.0,
              ),
            ),
            padding: EdgeInsets.all(
              ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 8.0,
                regular: 10.0,
                pro: 12.0,
                large: 12.0,
                extraLarge: 14.0,
              ),
            ),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 12.0,
                  regular: 14.0,
                  pro: 16.0,
                  large: 16.0,
                  extraLarge: 18.0,
                ),
              ),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Replying to ${replyMessage['senderName'] ?? 'Unknown'}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 11.0),
                ),
              ),
              SizedBox(
                height: ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 2.0,
                  regular: 3.0,
                  pro: 4.0,
                  large: 4.0,
                  extraLarge: 5.0,
                ),
              ),
              Text(
                replyMessage['text'] ?? '',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isMe = widget.isMe;
    final messageText = widget.message['text'] as String? ?? '';

    // Wrap with highlighting animation if needed
    Widget messageContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: widget.onReply,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 18.0,
            regular: 20.0,
            pro: 22.0,
            large: 24.0,
            extraLarge: 26.0,
          ),
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 14.0,
              regular: 16.0,
              pro: 18.0,
              large: 20.0,
              extraLarge: 22.0,
            ),
            vertical: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 10.0,
              regular: 12.0,
              pro: 14.0,
              large: 16.0,
              extraLarge: 18.0,
            ),
          ),
          decoration: BoxDecoration(
            gradient:
                isMe
                    ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withValues(alpha: 0.9),
                      ],
                    )
                    : null,
            color: isMe ? null : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(
                ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 18.0,
                  regular: 20.0,
                  pro: 22.0,
                  large: 24.0,
                  extraLarge: 26.0,
                ),
              ),
              topRight: Radius.circular(
                ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 18.0,
                  regular: 20.0,
                  pro: 22.0,
                  large: 24.0,
                  extraLarge: 26.0,
                ),
              ),
              bottomLeft: Radius.circular(
                isMe
                    ? ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 18.0,
                      regular: 20.0,
                      pro: 22.0,
                      large: 24.0,
                      extraLarge: 26.0,
                    )
                    : ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 4.0,
                      regular: 6.0,
                      pro: 8.0,
                      large: 8.0,
                      extraLarge: 10.0,
                    ),
              ),
              bottomRight: Radius.circular(
                isMe
                    ? ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 4.0,
                      regular: 6.0,
                      pro: 8.0,
                      large: 8.0,
                      extraLarge: 10.0,
                    )
                    : ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 18.0,
                      regular: 20.0,
                      pro: 22.0,
                      large: 24.0,
                      extraLarge: 26.0,
                    ),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: (isMe ? colorScheme.primary : colorScheme.shadow)
                    .withValues(alpha: 0.1),
                blurRadius: ResponsiveHelper.getAdaptiveElevation(context),
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sender name for received messages
              if (!isMe) ...[
                Text(
                  widget.message['senderName'] ?? 'Unknown',
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
                    pro: 6.0,
                    large: 8.0,
                    extraLarge: 8.0,
                  ),
                ),
              ],

              // Attachment preview
              if (widget.message['attachment'] != null) ...[
                AttachmentPreview(
                  attachment: AttachmentData.fromMap(
                    widget.message['attachment'] as Map<String, dynamic>,
                  ),
                  isCompact: true,
                ),
                if (messageText.isNotEmpty)
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
              ],

              // Message text
              if (messageText.isNotEmpty)
                Text(
                  messageText,
                  style: TextStyle(
                    color: isMe ? colorScheme.onPrimary : colorScheme.onSurface,
                    fontSize: ResponsiveHelper.adaptiveFontSize(context, 15.0),
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // Add highlighting effect if this message is highlighted
    if (widget.isHighlighted && widget.highlightAnimation != null) {
      return AnimatedBuilder(
        animation: widget.highlightAnimation!,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 18.0,
                  regular: 20.0,
                  pro: 22.0,
                  large: 24.0,
                  extraLarge: 26.0,
                ),
              ),
              // Subtle highlight effect that fades in and out
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(
                    alpha: 0.3 * widget.highlightAnimation!.value,
                  ),
                  blurRadius: 12.0 * widget.highlightAnimation!.value,
                  spreadRadius: 2.0 * widget.highlightAnimation!.value,
                ),
              ],
              // Optional: subtle background color change
              border: Border.all(
                color: colorScheme.primary.withValues(
                  alpha: 0.4 * widget.highlightAnimation!.value,
                ),
                width: 2.0 * widget.highlightAnimation!.value,
              ),
            ),
            child: messageContent,
          );
        },
      );
    }

    return messageContent;
  }

  Widget _buildMessageMeta(BuildContext context, ThemeData theme) {
    final timestamp = _formatTimestamp(
      widget.message['timestamp'] as DateTime?,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timestamp,
          style: TextStyle(
            fontSize: ResponsiveHelper.adaptiveFontSize(context, 11.0),
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (widget.isMe) ...[
          SizedBox(
            width: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 4.0,
              regular: 6.0,
              pro: 6.0,
              large: 8.0,
              extraLarge: 8.0,
            ),
          ),
          _buildStatusIcon(context, theme),
        ],
      ],
    );
  }

  Widget _buildStatusIcon(BuildContext context, ThemeData theme) {
    IconData iconData;
    Color iconColor;

    switch (widget.status) {
      case 'sending':
        iconData = Icons.schedule;
        iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
        break;
      case 'sent':
        iconData = Icons.check;
        iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
        break;
      case 'delivered':
        iconData = Icons.done_all;
        iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
        break;
      case 'read':
        iconData = Icons.done_all;
        iconColor = theme.colorScheme.primary;
        break;
      default:
        iconData = Icons.check;
        iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    }

    return Icon(
      iconData,
      size: ResponsiveHelper.adaptiveFontSize(context, 14.0),
      color: iconColor,
    );
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    final hour = timestamp.hour;
    final minute = timestamp.minute;

    if (diff.inDays > 0) {
      return '${timestamp.day}/${timestamp.month} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } else {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }
  }
}
