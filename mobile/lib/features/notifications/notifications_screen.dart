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
///
/// Kept deliberately quiet: one title with a live "new" count, one rail whose
/// selection pill glides between filters, and rows that carry their meaning in
/// a single coloured glyph rather than a tinted background.
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
    final unread = counts.values.fold<int>(0, (sum, count) => sum + count);

    ref.listen<NotificationCategory?>(notificationFilterProvider, (
      previous,
      next,
    ) {
      if (previous == next) return;
      _scheduleAnnouncement(next);
    });

    return KScaffold(
      appBar: KFixedAppBar(
        titleWidget: _AlertsTitle(unread: unread),
        actions: <Widget>[
          _FadeScale(
            visible: unread > 0,
            child: KIconButton(
              icon: Icons.done_all_rounded,
              semanticLabel: 'Mark all as read',
              color: colors.textSecondary,
              onPressed: controller.markAllRead,
            ),
          ),
          KIconButton(
            icon: Icons.tune_rounded,
            semanticLabel: 'Notification settings',
            color: colors.textSecondary,
            onPressed: () => openNotificationSettings(context),
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
            // Changing the filter cross-fades the list instead of snapping it,
            // and every list state lands the same way.
            child: AnimatedSwitcher(
              duration: KMotion.duration(context, KDurations.medium),
              switchInCurve: KMotion.curve(context, KCurves.emphasized),
              switchOutCurve: KMotion.curve(context, KCurves.accelerate),
              child: KeyedSubtree(
                key: ValueKey<String>(
                  '${notifications.isLoading && _lastRows == null}'
                  ':${selection?.wire ?? 'all'}',
                ),
                child: _body(
                  context,
                  ref,
                  notifications,
                  preferences,
                  selection,
                ),
              ),
            ),
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
    loading: () => const FillViewport(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.s5),
        child: KSkeletonList(rows: 7, showMedia: false),
      ),
    ),
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
          title: selection == null ? 'All caught up' : 'Nothing here yet',
          message: selection == null
              ? 'Likes, follows, replies and messages will land here.'
              : '${selection.label} alerts will show up here.',
          icon: selection == null
              ? Icons.notifications_none_rounded
              : selection.style(context.kc).glyph,
          actionLabel: selection == null ? null : 'Show all',
          onAction: selection == null
              ? null
              : () =>
                    ref.read(notificationFilterProvider.notifier).select(null),
        ),
      );
    }
    return _GroupedList(entries: visible);
  }
}

/// "Alerts" with a small live count of what is still unread beside it.
class _AlertsTitle extends StatelessWidget {
  const _AlertsTitle({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final label = notificationCountLabel(unread);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Alerts', style: context.kt.title2),
        const SizedBox(width: Space.s2),
        _FadeScale(
          visible: label != null,
          child: Semantics(
            label: '$unread unread',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2,
                vertical: Space.s05,
              ),
              decoration: BoxDecoration(
                color: colors.accentSubtle,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
              child: Text(
                '${label ?? ''} new',
                style: context.kt.count.copyWith(color: colors.accentHover),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grows and fades [child] in and out instead of popping it.
class _FadeScale extends StatelessWidget {
  const _FadeScale({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: KMotion.duration(context, KDurations.base),
    switchInCurve: KMotion.curve(context, KCurves.overshoot),
    switchOutCurve: KMotion.curve(context, KCurves.accelerate),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: animation, child: child),
    ),
    child: visible
        ? KeyedSubtree(key: const ValueKey<bool>(true), child: child)
        : const SizedBox.shrink(key: ValueKey<bool>(false)),
  );
}

/// The pinned category rail: `All` plus the eleven categories.
///
/// `KTabPager`-free on purpose — these are filters over one list, not pages, so
/// there is nothing to swipe between. The rail scrolls horizontally when the
/// twelve chips exceed the width, every chip carries a [Layout.tapTargetMin]
/// hit target, and the activated chip is scrolled fully into view (4.1).
///
/// The chips themselves are bare labels; one soft pill glides behind the
/// selected chip and resizes to fit it, and the labels cross-fade with it.
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

  /// One 44 pt chip row plus the gutter beneath it.
  static const double height = Layout.tapTargetMin + Space.s2;

  @override
  ConsumerState<NotificationFilterRail> createState() =>
      NotificationFilterRailState();
}

/// The rail's state, public only so a test can observe the indicator travel it
/// is otherwise impossible to assert on from the tree.
class NotificationFilterRailState extends ConsumerState<NotificationFilterRail>
    with SingleTickerProviderStateMixin {
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
  int _fromIndex = 0;
  int _targetIndex = 0;

  @override
  void initState() {
    super.initState();
    final selected = notificationFilterOptions.indexOf(
      ref.read(notificationFilterProvider),
    );
    _targetIndex = selected < 0 ? 0 : selected;
    _fromIndex = _targetIndex;
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

  /// How selected chip [index] looks right now, `0..1`, following the pill.
  double _selectionProgress(int index) {
    if (_fromIndex == _targetIndex) return index == _targetIndex ? 1 : 0;
    if (index == _targetIndex) return _progress;
    if (index == _fromIndex) return 1 - _progress;
    return 0;
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
      _fromIndex = _targetIndex;
      // Settled, not mid-travel: a re-measure is not an animation.
      _controller.value = 1;
    });
  }

  /// Restarts the indicator travel towards [index].
  ///
  /// It restarts from zero even when [index] is already the target, so a tap on
  /// the selected chip is still confirmed (4.8).
  void _animateIndicatorTo(int index) {
    _fromIndex = _targetIndex;
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
        duration: KMotion.duration(context, KDurations.medium),
        curve: KMotion.curve(context, KCurves.emphasized),
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

    return Container(
      height: NotificationFilterRail.height,
      // Painted over rather than laid out, so the hairline never eats into
      // the 44 pt hit targets above it.
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: Strokes.thin),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          Space.s3,
          Space.s0,
          Space.s3,
          Space.s2,
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final rect = _currentRect;
            return Stack(
              children: <Widget>[
                if (rect != null)
                  Positioned.fromRect(
                    rect: rect,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface3,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                    ),
                  ),
                Row(
                  key: _contentKey,
                  children: <Widget>[
                    for (final (index, option)
                        in notificationFilterOptions.indexed)
                      _railChip(index, option, option == selected),
                  ],
                ),
              ],
            );
          },
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
      onTap: () => _activate(index),
      semanticLabel: semantics,
      child: ConstrainedBox(
        constraints: const BoxConstraints.tightFor(
          height: Layout.tapTargetMin,
        ).copyWith(minWidth: Layout.tapTargetMin),
        child: Center(
          // The pill is measured off this box, so it hugs the label and its
          // badge rather than the taller hit target around them.
          child: Padding(
            key: _chipKeys[index],
            padding: EdgeInsets.only(right: badge == null ? 0 : Space.s15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                KChip(
                  label: label,
                  quiet: true,
                  selectionProgress: _selectionProgress(index),
                ),
                if (badge != null) _UnreadBadge(label: badge),
              ],
            ),
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
  const _UnreadBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      constraints: const BoxConstraints(minWidth: Space.s5),
      padding: const EdgeInsets.symmetric(horizontal: Space.s15),
      decoration: BoxDecoration(
        color: colors.accentDefault,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        child: Text(
          label,
          style: context.kt.count.copyWith(color: colors.textOnAccent),
          maxLines: 1,
        ),
      ),
    );
  }
}

class _GroupedList extends StatefulWidget {
  const _GroupedList({required this.entries});

  final List<NotificationModel> entries;

  @override
  State<_GroupedList> createState() => _GroupedListState();
}

class _GroupedListState extends State<_GroupedList> {
  /// How many of the first rows stagger in when the list appears.
  static const int _staggered = 10;

  /// Rows on screen when this list was built; only these stagger.
  late final Set<String> _initial = <String>{
    for (final entry in widget.entries) entry.id,
  };

  /// Rows that already played (or skipped) their entrance.
  final Set<String> _shown = <String>{};

  @override
  Widget build(BuildContext context) {
    // The server returns newest-first, so one pass produces the day sections
    // in order without sorting anything.
    final rows = <Widget>[];
    String? currentDay;
    var position = 0;
    for (final entry in widget.entries) {
      final label = dayLabel(entry.createdAt);
      if (label != currentDay) {
        currentDay = label;
        rows.add(_DayHeader(label: label, first: rows.isEmpty));
      }
      final fresh = _shown.add(entry.id);
      // A realtime arrival slides in wherever it lands; the first screenful
      // staggers in once; anything reached later by scrolling just appears.
      final arriving = fresh && !_initial.contains(entry.id);
      final opening = fresh && position < _staggered;
      rows.add(
        KReveal(
          key: ValueKey<String>(entry.id),
          animate: arriving || opening,
          delay: opening
              ? KMotion.staggerDelay(position, grid: false)
              : Duration.zero,
          child: NotificationRow(notification: entry),
        ),
      );
      position++;
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Space.s20),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      Space.s5,
      first ? Space.s4 : Space.s6,
      Space.s5,
      Space.s1,
    ),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: context.kt.label.copyWith(color: context.kc.textTertiary),
      ),
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
    final unread = notification.isUnread;
    final createdAt = notification.createdAt;
    final duration = KMotion.duration(context, KDurations.base);

    return KPressable(
      onTap: () => _open(context, ref),
      onLongPress: actor == null
          ? null
          : () => UserActions.showOverflow(context, profile: actor),
      enforceMinTapTarget: false,
      semanticLabel: _semanticLabel(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s5,
          vertical: Space.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _GlyphAvatar(
              imageUrl: avatarUrlOf(api, actor?.avatarPath),
              name: actor?.name ?? 'KLECT',
              icon: style.icon,
              tint: style.tint,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: duration,
                          style: context.kt.body.copyWith(
                            color: unread
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text: _actorLabel(),
                                  style: context.kt.bodyStrong.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                TextSpan(text: ' ${_phrase()}'),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.s2),
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s05),
                        child: Text(
                          createdAt == null
                              ? ''
                              : timeago.format(createdAt, locale: 'en_short'),
                          style: context.kt.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (preview != null) ...<Widget>[
                    const SizedBox(height: Space.s15),
                    Container(
                      padding: const EdgeInsets.only(left: Space.s25),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: colors.borderDefault,
                            width: Strokes.thick,
                          ),
                        ),
                      ),
                      child: Text(
                        preview,
                        style: context.kt.callout.copyWith(
                          color: colors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Space.s2),
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: AnimatedScale(
                duration: duration,
                curve: KMotion.curve(context, KCurves.emphasized),
                scale: unread ? 1 : 0,
                child: Container(
                  width: Space.s2,
                  height: Space.s2,
                  decoration: BoxDecoration(
                    color: colors.accentDefault,
                    shape: BoxShape.circle,
                  ),
                ),
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

/// The actor's avatar with the notification's type glyph on its corner.
class _GlyphAvatar extends StatelessWidget {
  const _GlyphAvatar({
    required this.imageUrl,
    required this.name,
    required this.icon,
    required this.tint,
  });

  final String? imageUrl;
  final String name;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        KAvatar(imageUrl: imageUrl, name: name, size: Space.s12),
        Positioned(
          right: -Space.s05,
          bottom: -Space.s05,
          child: Container(
            padding: const EdgeInsets.all(Space.s05),
            decoration: BoxDecoration(
              color: colors.bgBase,
              shape: BoxShape.circle,
            ),
            child: Container(
              width: Space.s5,
              height: Space.s5,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, size: Space.s3, color: colors.textOnAccent),
            ),
          ),
        ),
      ],
    );
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
