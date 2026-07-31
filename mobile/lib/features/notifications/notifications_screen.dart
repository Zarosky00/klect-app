import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../profile/fill_viewport.dart';
import '../profile/profile_queries.dart';
import '../profile/user_actions.dart';
import '../settings/notification_settings_screen.dart';
import 'notification_category.dart';
import 'notification_copy.dart';
import 'notification_filters.dart';
import 'notification_preferences.dart';
import 'notifications_controller.dart';

/// Icon and colour for one notification type.
///
/// Delegates to [NotificationCategory] so the banner glyph, this row's glyph
/// and the filter rail chip cannot drift (Requirement 1.6). Every tint is the
/// semantic action colour, with the Token_Set accent as the fallback.
({IconData icon, Color tint}) notificationStyle(
  KlectColors colors,
  NotificationType type,
) {
  final style = NotificationCategory.of(type).style(colors);
  return (icon: style.glyph, tint: style.tint);
}

/// The filter rail's options: `All` first, then the eleven categories in
/// Glossary order (Requirement 4.1).
///
/// `All` is `null` rather than a wrapper type, so the pure filter transform can
/// take the selection straight off [notificationFilterProvider] without
/// learning a second vocabulary.
const List<NotificationCategory?> notificationFilterOptions =
    <NotificationCategory?>[null, ...NotificationCategory.values];

/// Rail copy for one selection. `null` is `All`.
String notificationFilterLabel(NotificationCategory? selection) =>
    selection?.label ?? 'All';

/// The Alert Center's category selection — `null` meaning `All`.
///
/// Deliberately a plain [Notifier] and deliberately **not** `autoDispose`: the
/// root scope the shell builds holds it for the whole app session, so reopening
/// the Alert Center restores the selection while a fresh session starts at
/// `All` (Requirement 4.9).
class NotificationFilter extends Notifier<NotificationCategory?> {
  @override
  NotificationCategory? build() => null;

  /// Selects [category], or `All` when it is `null`.
  ///
  /// Re-selecting what is already selected is a no-op here on purpose: the
  /// indicator animation is driven by the tap, not by a state change, so the
  /// rail still confirms the tap without the list rebuilding (4.8).
  void select(NotificationCategory? category) {
    if (state == category) return;
    state = category;
  }
}

/// The session-scoped Alert Center filter selection.
final notificationFilterProvider =
    NotifierProvider<NotificationFilter, NotificationCategory?>(
      NotificationFilter.new,
      name: 'notificationFilter',
    );

/// Opens the per-type notification switches. Pushed rather than routed because
/// `lib/router.dart` is owned elsewhere and needs no change for this.
Future<void> openNotificationSettings(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => const NotificationSettingsScreen(),
      ),
    );

/// The Alerts tab.
///
/// Grouped by day, live over realtime, and every row routes to the thing it is
/// actually about. Reading a row marks it read and the tab badge follows.
class NotificationsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<NotificationModel>? _lastRows;
  Timer? _announcementTimer;
  String? _announcement;

  @override
  void dispose() {
    _announcementTimer?.cancel();
    super.dispose();
  }

  void _scheduleAnnouncement(NotificationCategory? selection) {
    _announcementTimer?.cancel();
    _announcementTimer = Timer(
      KMotion.duration(context, KDurations.deliberate),
      () {
        if (!mounted) return;
        final preferences = ref.read(resolvedNotificationPreferencesProvider);
        final count = filterNotifications(
          _lastRows ?? const <NotificationModel>[],
          selection,
          preferences,
        ).length;
        setState(() {
          _announcement =
              '${notificationFilterLabel(selection)}, $count notifications';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final notifications = ref.watch(notificationsProvider);
    final preferences = ref.watch(resolvedNotificationPreferencesProvider);
    final selection = ref.watch(notificationFilterProvider);
    final controller = ref.read(notificationsProvider.notifier);

    // Everything below is derived from the rows already in hand. Realtime
    // arrivals prepend to this same backing list in [NotificationsController],
    // so a new row raises its category's chip count whatever the selection is,
    // while the rendered list only moves when the row matches (4.11).
    final currentRows = notifications.value;
    if (currentRows != null) _lastRows = currentRows;
    final loaded = currentRows ?? _lastRows ?? const <NotificationModel>[];
    final underAll = filterNotifications(loaded, null, preferences);
    final counts = unreadCountsByCategory(underAll);

    ref.listen<NotificationCategory?>(notificationFilterProvider, (
      previous,
      next,
    ) {
      if (previous == next) return;
      _scheduleAnnouncement(next);
    });

    return KScaffold(
      appBar: KFixedAppBar(
        title: 'Alerts',
        actions: <Widget>[
          KIconButton(
            icon: Icons.tune_rounded,
            semanticLabel: 'Notification settings',
            onPressed: () => openNotificationSettings(context),
          ),
          KIconButton(
            icon: Icons.done_all_rounded,
            semanticLabel: 'Mark all as read',
            color: colors.textSecondary,
            onPressed: controller.markAllRead,
          ),
        ],
      ),
      onRefresh: controller.refresh,
      // The rail is pinned above every body state — list, skeleton, empty and
      // error — so the selected chip never disappears with the list (4.1, 4.6,
      // 4.10).
      body: Column(
        children: <Widget>[
          NotificationFilterRail(unreadCounts: counts),
          Semantics(
            liveRegion: true,
            label: _announcement,
            child: const SizedBox.shrink(),
          ),
          Expanded(
            child: _body(context, ref, notifications, preferences, selection),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<NotificationModel>> notifications,
    NotificationPreferenceSet preferences,
    NotificationCategory? selection,
  ) => notifications.when(
    loading: () =>
        const FillViewport(child: KSkeletonList(rows: 6, showMedia: false)),
    error: (error, _) {
      final previous = _lastRows;
      if (previous == null) {
        return FillViewport(
          child: KErrorState(
            error: error,
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
        );
      }
      return Column(
        children: <Widget>[
          KErrorState(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          Expanded(
            child: _bodyForRows(context, ref, previous, preferences, selection),
          ),
        ],
      );
    },
    data: (all) => _bodyForRows(context, ref, all, preferences, selection),
  );

  Widget _bodyForRows(
    BuildContext context,
    WidgetRef ref,
    List<NotificationModel> all,
    NotificationPreferenceSet preferences,
    NotificationCategory? selection,
  ) {
    // One pure pass over rows already loaded: no refetch when the selection
    // changes, which is what makes the 300 ms budget in 4.2 a non-event.
    final visible = filterNotifications(all, selection, preferences);
    if (visible.isEmpty) {
      return FillViewport(
        child: KEmptyState(
          title: selection == null ? 'Nothing yet' : 'Nothing here yet',
          message: selection == null
              ? 'Your alerts will appear here as soon as something happens.'
              : '${selection.label} alerts will show up here.',
          icon: Icons.notifications_none_rounded,
          actionLabel: 'Show all',
          onAction: () =>
              ref.read(notificationFilterProvider.notifier).select(null),
        ),
      );
    }
    return _GroupedList(entries: visible);
  }
}

/// The pinned category rail: `All` plus the eleven categories.
///
/// `KTabPager`-free on purpose — these are filters over one list, not pages, so
/// there is nothing to swipe between. The rail scrolls horizontally when the
/// twelve chips exceed the width, every chip carries a [Layout.tapTargetMin]
/// hit target, and the activated chip is scrolled fully into view (4.1).
class NotificationFilterRail extends ConsumerStatefulWidget {
  /// Creates the rail.
  const NotificationFilterRail({
    super.key,
    this.unreadCounts = const <NotificationCategory, int>{},
  });

  /// Unread rows per category, derived by [unreadCountsByCategory] from the
  /// loaded rows' `read_at` (Requirement 4.7). An absent or zero entry renders
  /// no badge at all.
  final Map<NotificationCategory, int> unreadCounts;

  /// One 44 pt chip row plus the indicator gutter beneath it.
  static const double height = Layout.tapTargetMin + Space.s2;

  @override
  ConsumerState<NotificationFilterRail> createState() =>
      NotificationFilterRailState();
}

/// The rail's state, public only so a test can observe the indicator travel it
/// is otherwise impossible to assert on from the tree.
class NotificationFilterRailState extends ConsumerState<NotificationFilterRail>
    with SingleTickerProviderStateMixin {
  static const double _indicatorHeight = Space.s05;

  final GlobalKey _contentKey = GlobalKey();
  final List<GlobalKey> _chipKeys = List<GlobalKey>.generate(
    notificationFilterOptions.length,
    (_) => GlobalKey(),
    growable: false,
  );

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.deliberate,
  );

  Curve _curve = KCurves.emphasized;

  /// Where the indicator started travelling from, and where it is heading.
  /// Both are measured, never assumed: chip widths are label-driven and move
  /// with the text scale.
  Rect? _from;
  Rect? _to;
  int _targetIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settleIndicator());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The indicator's travel, `0` the moment a chip is activated and `1` once it
  /// has arrived — including on a re-selection, where the travel is degenerate
  /// but still runs (4.8).
  @visibleForTesting
  Animation<double> get indicatorTravel => _controller.view;

  /// Where the indicator is drawn, relative to the chip row.
  @visibleForTesting
  Rect? get indicatorRect => _currentRect;

  double get _progress => _curve.transform(_controller.value.clamp(0.0, 1.0));

  Rect? get _currentRect {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return null;
    return Rect.lerp(from, to, _progress);
  }

  Rect? _rectFor(int index) {
    final content = _contentKey.currentContext?.findRenderObject();
    final chip = _chipKeys[index].currentContext?.findRenderObject();
    if (content is! RenderBox || chip is! RenderBox) return null;
    if (!content.hasSize || !chip.hasSize) return null;
    final origin = chip.localToGlobal(Offset.zero, ancestor: content);
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      chip.size.width,
      chip.size.height,
    );
  }

  /// Puts the indicator under the current target with no travel — the first
  /// frame, and after any relayout that moved the chip under it.
  void _settleIndicator() {
    if (!mounted || _controller.isAnimating) return;
    final rect = _rectFor(_targetIndex);
    if (rect == null || rect == _to) return;
    setState(() {
      _from = rect;
      _to = rect;
      // Settled, not mid-travel: a re-measure is not an animation.
      _controller.value = 1;
    });
  }

  /// Restarts the indicator travel towards [index].
  ///
  /// It restarts from zero even when [index] is already the target, so a tap on
  /// the selected chip is still confirmed (4.8).
  void _animateIndicatorTo(int index) {
    _targetIndex = index;
    final target = _rectFor(index);
    if (target == null) return;
    setState(() {
      _from = _currentRect ?? target;
      _to = target;
    });
    _controller.forward(from: 0);
  }

  void _revealChip(int index) {
    final chipContext = _chipKeys[index].currentContext;
    if (chipContext == null) return;
    unawaited(
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: KMotion.duration(context, KDurations.base),
        curve: KMotion.curve(context, KCurves.standard),
      ),
    );
  }

  void _activate(int index) {
    _animateIndicatorTo(index);
    ref
        .read(notificationFilterProvider.notifier)
        .select(notificationFilterOptions[index]);
    _revealChip(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    // Reduced motion shortens the travel rather than removing the
    // confirmation, exactly as elsewhere in the product.
    _controller.duration = KMotion.duration(context, KDurations.deliberate);
    _curve = KMotion.curve(context, KCurves.emphasized);

    final selected = ref.watch(notificationFilterProvider);
    // A selection made anywhere else — the empty state's "Show all", a restored
    // session — still moves the indicator.
    ref.listen<NotificationCategory?>(notificationFilterProvider, (_, next) {
      final index = notificationFilterOptions.indexOf(next);
      if (index < 0 || index == _targetIndex) return;
      _animateIndicatorTo(index);
      _revealChip(index);
    });
    // Chip geometry changes without the selection changing (text scale, a
    // rotation), so the indicator is re-measured after every frame and only
    // moved when it has actually drifted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _settleIndicator());

    return SizedBox(
      height: NotificationFilterRail.height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.s5),
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: Row(
                key: _contentKey,
                children: <Widget>[
                  for (final (index, option)
                      in notificationFilterOptions.indexed) ...<Widget>[
                    if (index > 0) const SizedBox(width: Space.s2),
                    _railChip(index, option, option == selected),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final rect = _currentRect;
                  if (rect == null) return const SizedBox.shrink();
                  return Transform.translate(
                    offset: Offset(rect.left, 0),
                    child: Container(
                      width: rect.width,
                      height: _indicatorHeight,
                      decoration: BoxDecoration(
                        color: colors.accentDefault,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railChip(int index, NotificationCategory? option, bool selected) {
    final label = notificationFilterLabel(option);
    // `All` carries no badge: Requirement 4.7 puts a count on a *category*
    // chip, and a total beside it would double-count what the chips already
    // say.
    final badge = option == null
        ? null
        : notificationCountLabel(widget.unreadCounts[option] ?? 0);
    final semantics = <String>[
      label,
      if (badge != null) '$badge unread',
      if (selected) 'selected',
    ].join(', ');

    return KPressable(
      key: _chipKeys[index],
      onTap: () => _activate(index),
      semanticLabel: semantics,
      child: SizedBox(
        height: Layout.tapTargetMin,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              KChip(label: label, selected: selected),
              if (badge != null) ...<Widget>[
                const SizedBox(width: Space.s1),
                _UnreadBadge(label: badge, selected: selected),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The unread count beside a rail chip.
///
/// Digits are drawn in `context.kt.count`, whose tabular figures keep the badge
/// from twitching as the count climbs from 9 to 10 (Requirements 4.7, 1.7).
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s15,
        vertical: Space.s05,
      ),
      decoration: BoxDecoration(
        color: selected ? colors.accentSubtle : colors.surface2,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: ExcludeSemantics(
        child: Text(
          label,
          style: context.kt.count.copyWith(
            color: selected ? colors.accentDefault : colors.textSecondary,
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.entries});

  final List<NotificationModel> entries;

  @override
  Widget build(BuildContext context) {
    // The server returns newest-first, so one pass produces the day sections
    // in order without sorting anything.
    final rows = <Widget>[];
    String? currentDay;
    for (final entry in entries) {
      final label = dayLabel(entry.createdAt);
      if (label != currentDay) {
        currentDay = label;
        rows.add(_DayHeader(label: label));
      }
      rows.add(NotificationRow(notification: entry));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Space.s20),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s5, Space.s5, Space.s5, Space.s2),
    child: Text(
      label.toUpperCase(),
      style: context.kt.micro.copyWith(color: context.kc.textTertiary),
    ),
  );
}

/// One notification.
class NotificationRow extends ConsumerWidget {
  /// Creates a row.
  const NotificationRow({required this.notification, super.key});

  /// What happened.
  final NotificationModel notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final style = notificationStyle(colors, notification.type);
    final actor = notification.actor;
    final preview = _preview();

    return KPressable(
      onTap: () => _open(context, ref),
      onLongPress: actor == null
          ? null
          : () => UserActions.showOverflow(context, profile: actor),
      enforceMinTapTarget: false,
      semanticLabel: _semanticLabel(),
      child: Container(
        color: notification.isUnread
            ? colors.accentSubtle
            : colors.bgBase.withValues(alpha: 0),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s5,
          vertical: Space.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                KAvatar(
                  imageUrl: avatarUrlOf(api, actor?.avatarPath),
                  name: actor?.name ?? 'KLECT',
                  size: Space.s12,
                ),
                Positioned(
                  right: -Space.s1,
                  bottom: -Space.s1,
                  child: Container(
                    padding: const EdgeInsets.all(Space.s1),
                    decoration: BoxDecoration(
                      color: colors.bgBase,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(style.icon, size: Space.s3, color: style.tint),
                  ),
                ),
              ],
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: _actorLabel(),
                          style: context.kt.bodyStrong,
                        ),
                        TextSpan(
                          text: ' ${_phrase()}',
                          style: context.kt.body.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (preview != null) ...<Widget>[
                    const SizedBox(height: Space.s1),
                    Text(
                      preview,
                      style: context.kt.callout.copyWith(
                        color: colors.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: Space.s1),
                  Text(
                    notification.createdAt == null
                        ? ''
                        : timeago.format(
                            notification.createdAt!,
                            locale: 'en_short',
                          ),
                    style: context.kt.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (notification.isUnread)
              Container(
                margin: const EdgeInsets.only(top: Space.s2, left: Space.s2),
                width: Space.s2,
                height: Space.s2,
                decoration: BoxDecoration(
                  color: colors.accentDefault,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _actorLabel() => notificationActorLabel(notification);

  String _phrase() => notificationPhrase(notification);

  String? _preview() => notificationPreview(notification);

  String _semanticLabel() {
    final when = notification.createdAt == null
        ? ''
        : ', ${timeago.format(notification.createdAt!)}';
    final unread = notification.isUnread ? ', unread' : '';
    return '${_actorLabel()} ${_phrase()}$when$unread';
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await ref.read(notificationsProvider.notifier).markRead(notification.id);
    if (!context.mounted) return;
    final destination = notificationDestination(notification);
    if (destination == null) return;
    await context.push(destination);
  }
}

/// `Today` / `Yesterday` / weekday / `4 Jul` — four shapes, no `intl`.
String dayLabel(DateTime? moment) {
  if (moment == null) return 'Earlier';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(moment.year, moment.month, moment.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  if (difference < 7) return _weekdays[day.weekday - 1];
  if (day.year == today.year) return '${day.day} ${_months[day.month - 1]}';
  return '${day.day} ${_months[day.month - 1]} ${day.year}';
}

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = <String>[
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
