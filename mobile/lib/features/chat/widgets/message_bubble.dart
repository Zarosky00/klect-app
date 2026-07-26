import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../chat_models.dart';
import 'chat_media.dart';
import 'shared_entity_card.dart';

/// The maximum share of the thread width one bubble may take.
const double _bubbleWidthFraction = 0.78;

/// One message.
///
/// Consecutive messages from the same author inside a few minutes are grouped:
/// only the first carries the name, only the last carries the avatar, the
/// timestamp and the read receipt, and the corner nearest the tail is tightened
/// so the group reads as one utterance rather than a stack of cards.
class MessageBubble extends StatelessWidget {
  /// Creates a bubble.
  const MessageBubble({
    required this.message,
    required this.isMine,
    super.key,
    this.viewerId,
    this.avatarUrl,
    this.isFirstOfGroup = true,
    this.isLastOfGroup = true,
    this.showAuthorName = false,
    this.seen = false,
    this.showReceipt = false,
    this.localPreview,
    this.highlighted = false,
    this.onLongPress,
    this.onDoubleTap,
    this.onReplyTap,
    this.onSwipeReply,
    this.onRetry,
    this.onDiscard,
    this.onReactionTap,
  });

  /// The message.
  final ChatMessage message;

  /// Whether the viewer wrote it.
  final bool isMine;

  /// The viewer's id, so reaction pills know which are theirs.
  final String? viewerId;

  /// Resolved avatar URL of the author, for the tail of an incoming run.
  final String? avatarUrl;

  /// First of a run by the same author.
  final bool isFirstOfGroup;

  /// Last of a run by the same author.
  final bool isLastOfGroup;

  /// Group threads name the author above the first bubble of a run.
  final bool showAuthorName;

  /// Whether the other side has read this far.
  final bool seen;

  /// Only the viewer's own most recent message carries a receipt.
  final bool showReceipt;

  /// Bytes for a photo still uploading.
  final Uint8List? localPreview;

  /// Plays the brief accent pulse a quote-jump or search-jump lands with.
  final bool highlighted;

  /// Opens the message actions sheet.
  final VoidCallback? onLongPress;

  /// Double tap is the quick reaction — the same escalation idea as the
  /// surf-card gesture contract, one level down.
  final VoidCallback? onDoubleTap;

  /// Jumps to the quoted message.
  final VoidCallback? onReplyTap;

  /// Arms the composer's reply target — fired when a rightward swipe on the
  /// row crosses the trigger. Null disables the gesture entirely.
  final VoidCallback? onSwipeReply;

  /// Retries a failed send.
  final VoidCallback? onRetry;

  /// Throws a failed send away.
  final VoidCallback? onDiscard;

  /// Toggles one of the reaction pills.
  final void Function(String emoji)? onReactionTap;

  @override
  Widget build(BuildContext context) {
    if (message.message.kind == MessageKind.callEvent) {
      return CallEventRow(message: message);
    }
    if (message.message.kind == MessageKind.system) {
      return SystemMessageRow(body: message.message.body ?? '');
    }

    final colors = context.kc;
    final text = context.kt;
    final maxWidth = MediaQuery.sizeOf(context).width * _bubbleWidthFraction;
    final reactions = message.summarise(viewerId);

    final tail = Radius.circular(isLastOfGroup ? Radii.xs : Radii.lg);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(Radii.lg),
      topRight: const Radius.circular(Radii.lg),
      bottomLeft: isMine ? const Radius.circular(Radii.lg) : tail,
      bottomRight: isMine ? tail : const Radius.circular(Radii.lg),
    );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s2,
      ),
      decoration: BoxDecoration(
        color: isMine ? colors.accentSubtle : colors.surface2,
        borderRadius: radius,
        border: Border.all(
          color: isMine ? colors.accentRing : colors.borderSubtle,
          width: Strokes.thin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (message.replyTo != null) ...<Widget>[
            _ReplyQuote(parent: message.replyTo!, onTap: onReplyTap),
            const SizedBox(height: Space.s2),
          ],
          for (final attachment in message.attachments) ...<Widget>[
            ChatPhoto(
              attachment: attachment,
              localBytes: localPreview,
              maxWidth: maxWidth,
              onTap: () => ChatPhotoViewer.open(
                context,
                attachment: attachment,
                localBytes: localPreview,
              ),
            ),
            const SizedBox(height: Space.s2),
          ],
          if (message.message.hasSharedEntity) ...<Widget>[
            SizedBox(
              width: maxWidth - Space.s6,
              child: SharedEntityCard(
                entityType: message.message.sharedEntityType!,
                entityId: message.message.sharedEntityId!,
                onDark: isMine,
              ),
            ),
            if (message.hasText) const SizedBox(height: Space.s2),
          ],
          if (message.hasText)
            Text(message.message.body!, style: text.body),
        ],
      ),
    );

    final column = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showAuthorName && isFirstOfGroup && !isMine)
          Padding(
            padding: const EdgeInsets.only(left: Space.s2, bottom: Space.s05),
            child: Text(
              message.message.author?.name ?? 'Someone',
              style: text.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        KGestureRegion(
          behavior: HitTestBehavior.deferToChild,
          onDoubleTap: onDoubleTap,
          onLongPress: onLongPress,
          semanticLabel: _semanticLabel,
          child: Opacity(
            opacity: message.pending ? Opacities.hover : 1,
            child: bubble,
          ),
        ),
        if (reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: _ReactionRow(
              summaries: reactions,
              onTap: onReactionTap,
            ),
          ),
        if (message.failed)
          _FailedFooter(onRetry: onRetry, onDiscard: onDiscard)
        else if (isLastOfGroup)
          _MetaFooter(
            message: message,
            isMine: isMine,
            seen: seen,
            showReceipt: showReceipt,
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(
        left: Space.s4,
        right: Space.s4,
        top: isFirstOfGroup ? Space.s2 : Space.s05,
      ),
      child: _HighlightPulse(
        active: highlighted,
        child: _SwipeToReply(
          onReply: onSwipeReply,
          child: Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (!isMine) ...<Widget>[
                SizedBox(
                  width: Space.s8,
                  child: isLastOfGroup
                      ? KAvatar(
                          size: Space.s8,
                          name: message.message.author?.name,
                          imageUrl: avatarUrl,
                        )
                      : null,
                ),
                const SizedBox(width: Space.s2),
              ],
              Flexible(child: column),
            ],
          ),
        ),
      ),
    );
  }

  String get _semanticLabel {
    final who = isMine ? 'You' : (message.message.author?.name ?? 'Them');
    final body = message.hasText
        ? message.message.body!
        : (message.attachments.isNotEmpty ? 'a photo' : 'a shared collection');
    return '$who: $body';
  }
}

/// The accent wash a jumped-to message lands with, then lets go of.
///
/// System-driven, so it is a curve, not a spring; the screen holds [active]
/// for a beat and the container animates both directions.
class _HighlightPulse extends StatelessWidget {
  const _HighlightPulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return AnimatedContainer(
      duration: KMotion.duration(context, KDurations.base),
      curve: Curves_.standard,
      decoration: BoxDecoration(
        color: active
            ? colors.accentSubtle
            : colors.accentSubtle.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: child,
    );
  }
}

/// Swipe a message rightwards to reply to it — the WhatsApp gesture.
///
/// The row tracks the finger one-to-one up to the trigger, then resists, so
/// the thumb feels where "armed" is; a light haptic confirms it. Releasing
/// past the trigger hands the message to the composer as its reply target —
/// the same path as the long-press sheet's Reply, which stays available
/// because a swipe is not discoverable and is impossible for a switch-control
/// user. Only the horizontal drag is claimed, so the vertical list scroll and
/// the tap / double-tap / long-press contract on the bubble are untouched.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, this.onReply});

  final Widget child;
  final VoidCallback? onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  /// Drag distance that arms the reply.
  static const double _trigger = Space.s14;

  /// How much of the finger's travel the row keeps past [_trigger] — the
  /// resistance that says "far enough". A ratio like [KMotion.pressScale];
  /// it belongs in `tokens.json` the next time that file is regenerated.
  static const double _overdragResistance = 0.25;

  late final AnimationController _offset =
      AnimationController.unbounded(vsync: this);

  double _raw = 0;
  bool _armed = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _offset.stop();
    _raw = _offset.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _raw = (_raw + details.primaryDelta!).clamp(0.0, double.infinity);
    _offset.value = _raw <= _trigger
        ? _raw
        : _trigger + (_raw - _trigger) * _overdragResistance;
    final armed = _raw >= _trigger;
    if (armed == _armed) return;
    setState(() => _armed = armed);
    if (armed) unawaited(HapticFeedback.lightImpact());
  }

  void _onDragEnd(DragEndDetails details) {
    if (_armed) widget.onReply?.call();
    _release();
  }

  void _release() {
    _raw = 0;
    if (_armed) setState(() => _armed = false);
    if (KMotion.reduced(context)) {
      _offset.value = 0;
      return;
    }
    // The finger drove it out, so a spring brings it home.
    _offset.animateWith(
      SpringSimulation(KMotion.spring(Springs.snappy), _offset.value, 0, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final colors = context.kc;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _release,
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) {
          final travel = _offset.value < 0 ? 0.0 : _offset.value;
          final progress = (travel / _trigger).clamp(0.0, 1.0);
          return Stack(
            alignment: AlignmentDirectional.centerStart,
            children: <Widget>[
              if (travel > 0)
                Positioned(
                  left: Space.s2,
                  child: Opacity(
                    opacity: progress,
                    child: Container(
                      width: Space.s8,
                      height: Space.s8,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _armed ? colors.accentSubtle : colors.surface2,
                        border: Border.all(
                          color: _armed
                              ? colors.accentDefault
                              : colors.borderSubtle,
                          width: Strokes.thin,
                        ),
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        size: Space.s4,
                        color: _armed
                            ? colors.accentDefault
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(travel, 0), child: child),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A date heading between two days of conversation.
class ChatDateSeparator extends StatelessWidget {
  /// Creates a date separator.
  const ChatDateSeparator({required this.date, super.key});

  /// The day the messages below belong to.
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s4,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Divider(color: colors.borderSubtle, height: Strokes.hairline),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s3),
            child: Text(
              label(date),
              style: context.kt.micro.copyWith(color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: Divider(color: colors.borderSubtle, height: Strokes.hairline),
          ),
        ],
      ),
    );
  }

  /// "Today" / "Yesterday" / a weekday / a full date.
  static String label(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'TODAY';
    if (difference == 1) return 'YESTERDAY';
    if (difference < 7) return _weekdays[day.weekday - 1].toUpperCase();
    return '${day.day} ${_months[day.month - 1]} ${day.year}'.toUpperCase();
  }

  static const List<String> _weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// The in-thread call log entry written when a call ends, is missed or is
/// declined.
class CallEventRow extends StatelessWidget {
  /// Creates a call event row.
  const CallEventRow({required this.message, super.key});

  /// The `call_event` message.
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final body = message.message.body ?? 'Call';
    final missed = body.toLowerCase().contains('missed') ||
        body.toLowerCase().contains('declined') ||
        body.toLowerCase().contains('failed');
    final tint = missed ? colors.semanticDanger : colors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s2,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s3,
            vertical: Space.s15,
          ),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(Radii.full),
            border:
                Border.all(color: colors.borderSubtle, width: Strokes.thin),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                missed ? Icons.call_end_rounded : Icons.call_rounded,
                size: Space.s4,
                color: tint,
              ),
              const SizedBox(width: Space.s15),
              Text(body, style: context.kt.caption.copyWith(color: tint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A server-generated notice ("X joined").
class SystemMessageRow extends StatelessWidget {
  /// Creates a system row.
  const SystemMessageRow({required this.body, super.key});

  /// The notice.
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s6,
          vertical: Space.s2,
        ),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: context.kt.caption.copyWith(color: context.kc.textTertiary),
        ),
      );
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.parent, this.onTap});

  final MessageModel parent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final preview = switch (parent.kind) {
      MessageKind.image => 'Photo',
      MessageKind.callEvent => parent.body ?? 'Call',
      _ => parent.body ?? (parent.sharedEntityId != null ? 'Shared' : ''),
    };

    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: 'Replying to $preview',
      child: Container(
        padding: const EdgeInsets.only(left: Space.s2),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colors.accentDefault,
              width: Strokes.thick,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              parent.author?.name ?? 'Message',
              style: context.kt.micro.copyWith(color: colors.accentDefault),
            ),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.kt.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.summaries, this.onTap});

  final List<ReactionSummary> summaries;
  final void Function(String emoji)? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Wrap(
      spacing: Space.s1,
      runSpacing: Space.s1,
      children: <Widget>[
        for (final summary in summaries)
          KPressable(
            enforceMinTapTarget: false,
            semanticLabel: '${summary.emoji} ${summary.count}'
                '${summary.mine ? ', yours' : ''}',
            onTap: onTap == null ? null : () => onTap!(summary.emoji),
            child: AnimatedContainer(
              duration: KMotion.duration(context, KDurations.fast),
              curve: Curves_.emphasized,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s15,
                vertical: Space.s05,
              ),
              decoration: BoxDecoration(
                color: summary.mine ? colors.accentSubtle : colors.surface3,
                borderRadius: BorderRadius.circular(Radii.full),
                border: Border.all(
                  color:
                      summary.mine ? colors.accentDefault : colors.borderSubtle,
                  width: Strokes.thin,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(summary.emoji, style: context.kt.caption),
                  if (summary.count > 1) ...<Widget>[
                    const SizedBox(width: Space.s05),
                    Text(
                      '${summary.count}',
                      style: context.kt.count.copyWith(
                        color: summary.mine
                            ? colors.accentDefault
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MetaFooter extends StatelessWidget {
  const _MetaFooter({
    required this.message,
    required this.isMine,
    required this.seen,
    required this.showReceipt,
  });

  final ChatMessage message;
  final bool isMine;
  final bool seen;
  final bool showReceipt;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final style = context.kt.micro.copyWith(color: colors.textTertiary);
    final time = TimeOfDay.fromDateTime(message.createdAt).format(context);

    return Padding(
      padding: const EdgeInsets.only(top: Space.s05, left: Space.s1, right: Space.s1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(time, style: style),
          if (message.isEdited) ...<Widget>[
            const SizedBox(width: Space.s1),
            Text('edited', style: style),
          ],
          if (message.pending) ...<Widget>[
            const SizedBox(width: Space.s1),
            Icon(
              Icons.schedule_rounded,
              size: Space.s3,
              color: colors.textTertiary,
            ),
          ] else if (isMine && showReceipt) ...<Widget>[
            const SizedBox(width: Space.s1),
            Icon(
              seen ? Icons.done_all_rounded : Icons.done_rounded,
              size: Space.s4,
              color: seen ? colors.accentDefault : colors.textTertiary,
              semanticLabel: seen ? 'Seen' : 'Sent',
            ),
          ],
        ],
      ),
    );
  }
}

class _FailedFooter extends StatelessWidget {
  const _FailedFooter({this.onRetry, this.onDiscard});

  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: Space.s4,
            color: colors.semanticDanger,
          ),
          const SizedBox(width: Space.s1),
          Text(
            'Not sent',
            style: context.kt.micro.copyWith(color: colors.semanticDanger),
          ),
          const SizedBox(width: Space.s2),
          KPressable(
            onTap: onRetry,
            enforceMinTapTarget: false,
            semanticLabel: 'Retry sending',
            child: Text(
              'Retry',
              style: context.kt.micro.copyWith(color: colors.accentDefault),
            ),
          ),
          const SizedBox(width: Space.s2),
          KPressable(
            onTap: onDiscard,
            enforceMinTapTarget: false,
            semanticLabel: 'Discard message',
            child: Text(
              'Discard',
              style: context.kt.micro.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
