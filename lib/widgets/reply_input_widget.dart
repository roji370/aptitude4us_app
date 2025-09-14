import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/community_chat_message.dart';
import '../services/attachment_service.dart';
import '../utils/responsive_helper.dart';

/// Widget for displaying reply input with quoted message preview
/// Similar to WhatsApp's reply interface
class ReplyInputWidget extends StatelessWidget {
  final CommunityChatMessage? quotedMessage;
  final VoidCallback onCancelReply;
  final Function(String text) onSendReply;
  final Function(AttachmentData attachment, String? text)? onSendReplyWithAttachment;
  final TextEditingController textController;
  final FocusNode focusNode;
  final bool isSending;

  const ReplyInputWidget({
    super.key,
    this.quotedMessage,
    required this.onCancelReply,
    required this.onSendReply,
    this.onSendReplyWithAttachment,
    required this.textController,
    required this.focusNode,
    this.isSending = false,
  });

  @override
  Widget build(BuildContext context) {
    if (quotedMessage == null) return const SizedBox.shrink();

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
      child: Column(
        children: [
          // Quoted message preview
          _buildQuotedMessagePreview(context),
          
          // Reply input field
          _buildReplyInput(context),
        ],
      ),
    );
  }

  Widget _buildQuotedMessagePreview(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
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
                  'Replying to ${quotedMessage!.senderName}',
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
                
                // Quoted message text or attachment preview
                _buildQuotedContent(context),
              ],
            ),
          ),
          
          // Cancel reply button
          IconButton(
            onPressed: onCancelReply,
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

  Widget _buildQuotedContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (quotedMessage!.hasAttachment) {
      // Show attachment preview
      return Row(
        children: [
          Icon(
            _getAttachmentIcon(quotedMessage!.attachmentType),
            size: ResponsiveHelper.adaptiveFontSize(context, 16.0),
            color: colorScheme.onSurfaceVariant,
          ),
          SizedBox(
            width: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 6.0,
              regular: 8.0,
              pro: 10.0,
              large: 10.0,
              extraLarge: 12.0,
            ),
          ),
          Expanded(
            child: Text(
              quotedMessage!.attachment?.fileName ?? 'Attachment',
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
        quotedMessage!.text,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
  }

  Widget _buildReplyInput(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.getAdaptiveSpacing(
          context,
          compact: 12.0,
          regular: 14.0,
          pro: 16.0,
          large: 18.0,
          extraLarge: 20.0,
        ),
        vertical: ResponsiveHelper.getAdaptiveSpacing(
          context,
          compact: 8.0,
          regular: 10.0,
          pro: 12.0,
          large: 14.0,
          extraLarge: 16.0,
        ),
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 20.0,
            regular: 24.0,
            pro: 28.0,
            large: 32.0,
            extraLarge: 36.0,
          ),
        ),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Text input field
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              enabled: !isSending,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type a reply...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 8.0,
                    regular: 10.0,
                    pro: 12.0,
                    large: 14.0,
                    extraLarge: 16.0,
                  ),
                  vertical: ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 8.0,
                    regular: 10.0,
                    pro: 12.0,
                    large: 14.0,
                    extraLarge: 16.0,
                  ),
                ),
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                ),
              ),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
              ),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty && !isSending) {
                  onSendReply(text.trim());
                }
              },
            ),
          ),
          
          // Send button
          Container(
            margin: EdgeInsets.only(
              left: ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 8.0,
                regular: 10.0,
                pro: 12.0,
                large: 14.0,
                extraLarge: 16.0,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isSending ? null : () {
                  final text = textController.text.trim();
                  if (text.isNotEmpty) {
                    onSendReply(text);
                  }
                },
                borderRadius: BorderRadius.circular(
                  ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 16.0,
                    regular: 18.0,
                    pro: 20.0,
                    large: 22.0,
                    extraLarge: 24.0,
                  ),
                ),
                child: Container(
                  padding: EdgeInsets.all(
                    ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 8.0,
                      regular: 10.0,
                      pro: 12.0,
                      large: 14.0,
                      extraLarge: 16.0,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: isSending 
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                        : colorScheme.primary,
                    borderRadius: BorderRadius.circular(
                      ResponsiveHelper.getAdaptiveSpacing(
                        context,
                        compact: 16.0,
                        regular: 18.0,
                        pro: 20.0,
                        large: 22.0,
                        extraLarge: 24.0,
                      ),
                    ),
                  ),
                  child: isSending
                      ? SizedBox(
                          width: ResponsiveHelper.adaptiveFontSize(context, 16.0),
                          height: ResponsiveHelper.adaptiveFontSize(context, 16.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Icon(
                          Icons.send,
                          size: ResponsiveHelper.adaptiveFontSize(context, 16.0),
                          color: colorScheme.onPrimary,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
