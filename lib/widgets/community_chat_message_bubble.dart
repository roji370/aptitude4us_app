import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/community_chat_message.dart';
import '../services/attachment_service.dart';
import '../widgets/attachment_preview.dart';
import '../utils/responsive_helper.dart';

/// Enhanced message bubble widget for community chat with reply support
/// Similar to WhatsApp's message bubble design
class CommunityChatMessageBubble extends StatefulWidget {
  final CommunityChatMessage message;
  final bool isCurrentUser;
  final VoidCallback onReply;
  final Function(String messageId)? onScrollToMessage;
  final bool showAvatar;

  const CommunityChatMessageBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    required this.onReply,
    this.onScrollToMessage,
    this.showAvatar = true,
  });

  @override
  State<CommunityChatMessageBubble> createState() => _CommunityChatMessageBubbleState();
}

class _CommunityChatMessageBubbleState extends State<CommunityChatMessageBubble>
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
      begin: widget.isCurrentUser ? const Offset(0.3, 0) : const Offset(-0.3, 0),
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

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Padding(
          padding: EdgeInsets.only(
            left: widget.isCurrentUser
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
            right: widget.isCurrentUser
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
            mainAxisAlignment: widget.isCurrentUser 
                ? MainAxisAlignment.end 
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar for received messages
              if (!widget.isCurrentUser && widget.showAvatar) ...[
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
                  crossAxisAlignment: widget.isCurrentUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Reply indicator (quoted message preview)
                    if (widget.message.isReply)
                      _buildReplyIndicator(context),

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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final senderName = widget.message.senderName;
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

  Widget _buildReplyIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () {
        // Scroll to the original message
        if (widget.onScrollToMessage != null && widget.message.replyToMessageId != null) {
          widget.onScrollToMessage!(widget.message.replyToMessageId!);
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
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
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
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Vertical line indicator
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            
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
            
            // Quoted message content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Replying to ${widget.message.replyToMessage?.senderName ?? 'Unknown'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
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
                  _buildQuotedContent(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotedContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quotedMessage = widget.message.replyToMessage;

    if (quotedMessage == null) {
      return Text(
        'Message not found',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
          fontStyle: FontStyle.italic,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (quotedMessage.hasAttachment) {
      // Show attachment preview
      return Row(
        children: [
          Icon(
            _getAttachmentIcon(quotedMessage.attachmentType),
            size: ResponsiveHelper.adaptiveFontSize(context, 14.0),
            color: colorScheme.onSurfaceVariant,
          ),
          SizedBox(
            width: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 4.0,
              regular: 6.0,
              pro: 8.0,
              large: 8.0,
              extraLarge: 10.0,
            ),
          ),
          Expanded(
            child: Text(
              quotedMessage.attachment?.fileName ?? 'Attachment',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else {
      // Show text content
      return Text(
        quotedMessage.text,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
  }

  Widget _buildMessageContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isMe = widget.isCurrentUser;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: () {
          HapticFeedback.selectionClick();
          widget.onReply();
        },
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
            gradient: isMe
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
                  widget.message.senderName,
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
              if (widget.message.hasAttachment) ...[
                AttachmentPreview(
                  attachment: widget.message.attachment!,
                  isCompact: true,
                ),
                if (widget.message.text.isNotEmpty)
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
              if (widget.message.text.isNotEmpty)
                Text(
                  widget.message.text,
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
  }

  Widget _buildMessageMeta(BuildContext context, ThemeData theme) {
    final timestamp = _formatTimestamp(widget.message.timestamp.toDate());

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
        if (widget.isCurrentUser) ...[
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

    switch (widget.message.status) {
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

  String _formatTimestamp(DateTime timestamp) {
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

  IconData _getAttachmentIcon(AttachmentType? type) {
    switch (type) {
      case AttachmentType.image:
        return Icons.image;
      case AttachmentType.video:
        return Icons.videocam;
      case AttachmentType.document:
        return Icons.description;
      default:
        return Icons.attach_file;
    }
  }
}