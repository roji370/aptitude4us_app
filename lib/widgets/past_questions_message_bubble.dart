import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/past_questions_message.dart';
import '../widgets/attachment_preview.dart';
import '../utils/responsive_helper.dart';

class PastQuestionsMessageBubble extends StatefulWidget {
  final PastQuestionsMessage message;
  final bool isCurrentUser;
  final VoidCallback? onReply;
  final bool showAvatar;

  const PastQuestionsMessageBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.onReply,
    this.showAvatar = true,
  });

  @override
  State<PastQuestionsMessageBubble> createState() =>
      _PastQuestionsMessageBubbleState();
}

class _PastQuestionsMessageBubbleState extends State<PastQuestionsMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _slideAnimation = Tween<Offset>(
      begin:
          widget.isCurrentUser ? const Offset(0.5, 0) : const Offset(-0.5, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    // Start animation with a slight delay for staggered effect
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _animationController.forward();
      }
    });
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
    final time = DateFormat('HH:mm').format(widget.message.timestamp.toDate());

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Padding(
          padding: EdgeInsets.only(
            left:
                widget.isCurrentUser
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
                widget.isCurrentUser
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
              compact: 4.0,
              regular: 6.0,
              pro: 8.0,
              large: 10.0,
              extraLarge: 12.0,
            ),
            bottom: ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 4.0,
              regular: 6.0,
              pro: 8.0,
              large: 10.0,
              extraLarge: 12.0,
            ),
          ),
          child: Row(
            mainAxisAlignment:
                widget.isCurrentUser
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar for other users' messages
              if (!widget.isCurrentUser && widget.showAvatar) ...[
                _buildUserAvatar(context, colorScheme),
                SizedBox(
                  width: ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 8.0,
                    regular: 12.0,
                    pro: 14.0,
                    large: 16.0,
                    extraLarge: 18.0,
                  ),
                ),
              ],

              // Message content
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      widget.isCurrentUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                  children: [
                    // Message bubble
                    _buildMessageBubble(context, theme, colorScheme),

                    // Timestamp
                    SizedBox(
                      height: ResponsiveHelper.getAdaptiveSpacing(
                        context,
                        compact: 4.0,
                        regular: 6.0,
                        pro: 8.0,
                        large: 10.0,
                        extraLarge: 12.0,
                      ),
                    ),
                    _buildTimestamp(context, theme, time),
                  ],
                ),
              ),

              // No spacer needed for current user messages since they don't show avatars
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar(BuildContext context, ColorScheme colorScheme) {
    final avatarSize = ResponsiveHelper.adaptiveFontSize(context, 36.0);
    final initials =
        widget.message.senderName.isNotEmpty
            ? widget.message.senderName[0].toUpperCase()
            : '?';

    // Generate consistent color based on sender name
    final colorIndex =
        widget.message.senderName.hashCode % _avatarColors.length;
    final avatarColors = _avatarColors[colorIndex.abs()];

    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: avatarColors,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: avatarColors[0].withValues(alpha: 0.3),
            blurRadius: ResponsiveHelper.getAdaptiveElevation(context),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: ResponsiveHelper.adaptiveFontSize(context, 16.0),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isCurrentUser = widget.isCurrentUser;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: () {
          if (widget.onReply != null) {
            HapticFeedback.mediumImpact();
            widget.onReply!();
          }
        },
        onTap: () {
          HapticFeedback.selectionClick();
        },
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
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: EdgeInsets.all(
            ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 14.0,
              regular: 16.0,
              pro: 18.0,
              large: 20.0,
              extraLarge: 22.0,
            ),
          ),
          decoration: BoxDecoration(
            gradient:
                isCurrentUser
                    ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withValues(alpha: 0.85),
                      ],
                    )
                    : null,
            color: isCurrentUser ? null : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(
                ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 20.0,
                  regular: 24.0,
                  pro: 28.0,
                  large: 32.0,
                  extraLarge: 36.0,
                ),
              ),
              topRight: Radius.circular(
                ResponsiveHelper.getAdaptiveSpacing(
                  context,
                  compact: 20.0,
                  regular: 24.0,
                  pro: 28.0,
                  large: 32.0,
                  extraLarge: 36.0,
                ),
              ),
              bottomLeft: Radius.circular(
                isCurrentUser
                    ? ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 20.0,
                      regular: 24.0,
                      pro: 28.0,
                      large: 32.0,
                      extraLarge: 36.0,
                    )
                    : ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 6.0,
                      regular: 8.0,
                      pro: 10.0,
                      large: 12.0,
                      extraLarge: 14.0,
                    ),
              ),
              bottomRight: Radius.circular(
                isCurrentUser
                    ? ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 6.0,
                      regular: 8.0,
                      pro: 10.0,
                      large: 12.0,
                      extraLarge: 14.0,
                    )
                    : ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 20.0,
                      regular: 24.0,
                      pro: 28.0,
                      large: 32.0,
                      extraLarge: 36.0,
                    ),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: (isCurrentUser
                        ? colorScheme.primary
                        : colorScheme.shadow)
                    .withValues(alpha: 0.15),
                blurRadius: ResponsiveHelper.getAdaptiveElevation(context),
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sender name for other users
              if (!isCurrentUser) ...[
                Text(
                  widget.message.senderName,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.adaptiveFontSize(context, 13.0),
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
                SizedBox(
                  height: ResponsiveHelper.getAdaptiveSpacing(
                    context,
                    compact: 6.0,
                    regular: 8.0,
                    pro: 10.0,
                    large: 12.0,
                    extraLarge: 14.0,
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
                SelectableText(
                  widget.message.text,
                  style: TextStyle(
                    color:
                        isCurrentUser
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
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

  Widget _buildTimestamp(BuildContext context, ThemeData theme, String time) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.getAdaptiveSpacing(
          context,
          compact: 4.0,
          regular: 6.0,
          pro: 8.0,
          large: 10.0,
          extraLarge: 12.0,
        ),
      ),
      child: Text(
        time,
        style: TextStyle(
          fontSize: ResponsiveHelper.adaptiveFontSize(context, 11.0),
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // Predefined avatar color combinations for consistent user identification
  static const List<List<Color>> _avatarColors = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Indigo to Purple
    [Color(0xFF10B981), Color(0xFF059669)], // Emerald
    [Color(0xFFF59E0B), Color(0xFFD97706)], // Amber
    [Color(0xFFEF4444), Color(0xFFDC2626)], // Red
    [Color(0xFF3B82F6), Color(0xFF2563EB)], // Blue
    [Color(0xFF8B5CF6), Color(0xFF7C3AED)], // Purple
    [Color(0xFF06B6D4), Color(0xFF0891B2)], // Cyan
    [Color(0xFFEC4899), Color(0xFFDB2777)], // Pink
    [Color(0xFF84CC16), Color(0xFF65A30D)], // Lime
    [Color(0xFFF97316), Color(0xFFEA580C)], // Orange
  ];
}
