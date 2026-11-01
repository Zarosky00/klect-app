import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/feedback/interaction_feedback.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../data/pulse_feed_controller.dart';
import '../data/pulse_filters.dart';

/// The Pulse filter sheet — a bottom sheet over the stream, opened from the
/// tune button in the Pulse header.
///
/// Type, time window and shared taste apply live (they are client-side over
/// the fetched pages, so every change is instant and the stream behind the
/// sheet already shows the result). The search field queries `search_all`'s
/// posts section; while a search is active its results replace the filter
/// options, and each hit deep-links to its thread.
abstract final class PulseFilterSheet {
  /// Presents the sheet for the stream in [mode].
  static Future<void> show(BuildContext context, {required PulseMode mode}) =>
      KSheet.show<void>(
        context: context,
        maxHeightFraction: 0.92,
        builder: (_) => _PulseFilterSheetBody(mode: mode),
      );
}

class _PulseFilterSheetBody extends ConsumerStatefulWidget {
  const _PulseFilterSheetBody({required this.mode});

  final PulseMode mode;

  @override
  ConsumerState<_PulseFilterSheetBody> createState() =>
      _PulseFilterSheetBodyState();
}

class _PulseFilterSheetBodyState extends ConsumerState<_PulseFilterSheetBody> {
  final TextEditingController _query = TextEditingController();

  List<PostSearchHit>? _hits;
  bool _searching = false;
  String? _searchError;
  String _lastQuery = '';

  bool get _searchActive => _searching || _hits != null || _searchError != null;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _hits = null;
        _searchError = null;
        _searching = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
      _lastQuery = query;
    });
    try {
      final results = await ref
          .read(klectApiProvider)
          .searchAll(query, limit: 8);
      if (!mounted || _lastQuery != query) return;
      setState(() => _hits = results.posts);
    } on KlectError catch (error) {
      if (!mounted || _lastQuery != query) return;
      setState(() => _searchError = error.message);
    } finally {
      if (mounted && _lastQuery == query) setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _query.clear();
    unawaited(_search(''));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final filters = ref.watch(pulseFiltersProvider);
    final controller = ref.read(pulseFiltersProvider.notifier);
    final feed = ref.watch(pulseFeedProvider(widget.mode));
    final tasteIds = filters.sharedTaste
        ? ref.watch(matchedCollectorIdsProvider).value
        : null;
    final visible = filters.apply(feed.items, tasteIds).length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: Space.s2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('Filters', style: text.title2),
                      const SizedBox(height: Space.s05),
                      Text(
                        'Tune what your Pulse shows',
                        style: text.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: filters.isActive ? 1 : 0,
                  duration: KMotion.duration(context, KDurations.fast),
                  child: IgnorePointer(
                    ignoring: !filters.isActive,
                    child: KButton(
                      label: 'Reset',
                      variant: KButtonVariant.ghost,
                      size: KButtonSize.small,
                      icon: Icons.restart_alt_rounded,
                      onPressed: controller.clear,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s4),
            KTextField(
              controller: _query,
              hint: 'Search posts',
              prefixIcon: Icons.search_rounded,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => unawaited(_search(value)),
              suffix: _searching
                  ? Padding(
                      padding: const EdgeInsets.all(Space.s2),
                      child: SizedBox(
                        width: Space.s4,
                        height: Space.s4,
                        child: CircularProgressIndicator(
                          strokeWidth: Strokes.thick,
                          color: colors.accentDefault,
                        ),
                      ),
                    )
                  : !_searchActive
                  ? null
                  : KIconButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Clear search',
                      size: Space.s4,
                      onPressed: _clearSearch,
                    ),
            ),
            AnimatedSize(
              duration: KMotion.duration(context, KDurations.medium),
              curve: KMotion.curve(context, KCurves.emphasized),
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: KMotion.duration(context, KDurations.base),
                switchInCurve: KCurves.emphasized,
                switchOutCurve: KCurves.accelerate,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[...previous, ?current],
                ),
                child: _searchActive
                    ? KeyedSubtree(
                        key: const ValueKey<String>('search'),
                        child: _searchResults(),
                      )
                    : KeyedSubtree(
                        key: const ValueKey<String>('filters'),
                        child: _filterOptions(filters, controller),
                      ),
              ),
            ),
            const SizedBox(height: Space.s5),
            KButton(
              label: _searchActive
                  ? 'Back to Pulse'
                  : visible == 0
                  ? 'Nothing loaded matches yet'
                  : 'Show $visible ${visible == 1 ? 'post' : 'posts'}',
              size: KButtonSize.large,
              expand: true,
              animateChanges: true,
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterOptions(PulseFilters filters, PulseFiltersController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: Space.s5),
        const _SectionLabel('SHOW'),
        const SizedBox(height: Space.s2),
        _TypeGrid(selected: filters.type, onSelect: controller.setType),
        const SizedBox(height: Space.s5),
        const _SectionLabel('FROM'),
        const SizedBox(height: Space.s2),
        _SlidingSegments<PulseTimeFilter>(
          values: PulseTimeFilter.values,
          selected: filters.time,
          labelOf: (time) => time == PulseTimeFilter.all ? 'All time' : time.label,
          onSelect: controller.setTime,
        ),
        const SizedBox(height: Space.s5),
        _TasteToggle(
          value: filters.sharedTaste,
          onChanged: () {
            triggerInteractionTapFeedback(context);
            controller.toggleSharedTaste();
          },
        ),
      ],
    );
  }

  Widget _searchResults() {
    final colors = context.kc;
    final text = context.kt;
    final error = _searchError;
    final hits = _hits;

    final Widget content;
    if (error != null) {
      content = KInlineError(
        message: error,
        onRetry: () => unawaited(_search(_lastQuery)),
      );
    } else if (hits == null) {
      content = const KSkeletonList(rows: 2, showMedia: false);
    } else if (hits.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s6),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: Space.s8,
              color: colors.textTertiary,
            ),
            const SizedBox(height: Space.s2),
            Text(
              'No posts match “$_lastQuery”',
              textAlign: TextAlign.center,
              style: text.callout.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final hit in hits)
            _PostHitRow(key: ValueKey<String>(hit.id), hit: hit),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: content,
    );
  }
}

/// A quiet, tracked eyebrow above each group.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: context.kt.micro.copyWith(color: context.kc.textTertiary),
  );
}

/// The five row shapes as a three-column grid of selectable tiles.
class _TypeGrid extends StatelessWidget {
  const _TypeGrid({required this.selected, required this.onSelect});

  final PulseTypeFilter selected;
  final ValueChanged<PulseTypeFilter> onSelect;

  static const int _columns = 3;
  static const double _gap = Space.s2;

  static IconData _iconOf(PulseTypeFilter type) => switch (type) {
    PulseTypeFilter.all => Icons.all_inclusive_rounded,
    PulseTypeFilter.text => Icons.notes_rounded,
    PulseTypeFilter.photos => Icons.photo_outlined,
    PulseTypeFilter.collections => Icons.collections_bookmark_outlined,
    PulseTypeFilter.quotes => Icons.format_quote_rounded,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width =
          (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: <Widget>[
          for (final type in PulseTypeFilter.values)
            SizedBox(
              width: width,
              child: _TypeTile(
                icon: _iconOf(type),
                label: type.label,
                selected: type == selected,
                onTap: () => onSelect(type),
              ),
            ),
        ],
      );
    },
  );
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final duration = KMotion.duration(context, KDurations.medium);
    final curve = KMotion.curve(context, KCurves.emphasized);
    return Semantics(
      selected: selected,
      child: KPressable(
        onTap: onTap,
        enforceMinTapTarget: false,
        semanticLabel: selected ? '$label, selected' : label,
        child: AnimatedContainer(
          duration: duration,
          curve: curve,
          height: Space.s16,
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(
            color: selected ? colors.accentSubtle : colors.surface2,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected ? colors.accentDefault : colors.borderSubtle,
              width: Strokes.thin,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: Space.s5,
                    color: selected
                        ? colors.accentHover
                        : colors.textSecondary,
                  ),
                  const Spacer(),
                  AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: duration,
                    curve: KMotion.curve(context, KCurves.overshoot),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: Space.s4,
                      color: colors.accentHover,
                    ),
                  ),
                ],
              ),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: curve,
                style: context.kt.label.copyWith(
                  color: selected ? colors.textPrimary : colors.textSecondary,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill segmented control whose thumb glides between segments.
class _SlidingSegments<T> extends StatelessWidget {
  const _SlidingSegments({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    final x = values.length <= 1 ? 0.0 : -1 + 2 * index / (values.length - 1);
    final duration = KMotion.duration(context, KDurations.medium);
    final curve = KMotion.curve(context, KCurves.emphasized);

    return Container(
      height: Space.s10 + Space.s1,
      padding: const EdgeInsets.all(Space.s05),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: colors.borderSubtle, width: Strokes.hairline),
      ),
      child: Stack(
        children: <Widget>[
          AnimatedAlign(
            alignment: Alignment(x, 0),
            duration: duration,
            curve: curve,
            child: FractionallySizedBox(
              widthFactor: 1 / values.length,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface4,
                  borderRadius: BorderRadius.circular(Radii.full),
                  boxShadow: KlectTheme.shadow(Elevation.low),
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              for (final value in values)
                Expanded(
                  child: KPressable(
                    onTap: () => onSelect(value),
                    enforceMinTapTarget: false,
                    semanticLabel: value == selected
                        ? '${labelOf(value)}, selected'
                        : labelOf(value),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: duration,
                        curve: curve,
                        style: context.kt.label.copyWith(
                          color: value == selected
                              ? colors.textPrimary
                              : colors.textTertiary,
                        ),
                        child: Text(
                          labelOf(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Shared taste only" as one pressable card with a sliding switch.
class _TasteToggle extends StatelessWidget {
  const _TasteToggle({required this.value, required this.onChanged});

  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final duration = KMotion.duration(context, KDurations.medium);
    final curve = KMotion.curve(context, KCurves.emphasized);

    return Semantics(
      toggled: value,
      child: KPressable(
        onTap: onChanged,
        enforceMinTapTarget: false,
        feedbackEnabled: false,
        semanticLabel: 'Shared taste only',
        child: AnimatedContainer(
          duration: duration,
          curve: curve,
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(
            color: value ? colors.accentSubtle : colors.surface2,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: value ? colors.accentRing : colors.borderSubtle,
              width: Strokes.thin,
            ),
          ),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: duration,
                curve: curve,
                width: Space.s10,
                height: Space.s10,
                decoration: BoxDecoration(
                  color: value ? colors.accentDefault : colors.surface3,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: Space.s5,
                  color: value ? colors.textOnAccent : colors.textSecondary,
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Shared taste only', style: text.bodyStrong),
                    Text(
                      'Only collectors whose taste matches yours',
                      style: text.caption.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s3),
              AnimatedContainer(
                duration: duration,
                curve: curve,
                width: Space.s10,
                height: Space.s6,
                padding: const EdgeInsets.all(Space.s05),
                decoration: BoxDecoration(
                  color: value ? colors.accentDefault : colors.surface4,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
                child: AnimatedAlign(
                  duration: duration,
                  curve: curve,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: Space.s5,
                    height: Space.s5,
                    decoration: BoxDecoration(
                      color: value ? colors.textOnAccent : colors.textSecondary,
                      shape: BoxShape.circle,
                      boxShadow: KlectTheme.shadow(Elevation.low),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One `search_all` post hit — author, excerpt, counts; tap opens the thread.
class _PostHitRow extends ConsumerWidget {
  const _PostHitRow({required this.hit, super.key});

  final PostSearchHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final author = hit.author;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(author?.avatarPath, bucket: StorageBucket.avatars);

    return KPressable(
      onTap: () {
        // Close the sheet first; the router outlives it.
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        unawaited(router.push(KlectLinks.postThreadPath(hit.id)));
      },
      enforceMinTapTarget: false,
      semanticLabel: hit.body ?? 'Post',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s25),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KAvatar(
              imageUrl: avatarUrl,
              name: author?.name,
              size: Space.s8,
              isVerified: author?.isVerified ?? false,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          author?.name ?? 'Someone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.label,
                        ),
                      ),
                      if (hit.createdAt != null) ...<Widget>[
                        const SizedBox(width: Space.s2),
                        Text(
                          timeago.format(hit.createdAt!, locale: 'en_short'),
                          style: text.micro.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (hit.body != null && hit.body!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Space.s05),
                    Text(
                      hit.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.callout.copyWith(color: colors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: Space.s05),
                  Text(
                    '${formatCount(hit.likeCount)} likes · '
                    '${formatCount(hit.commentCount)} comments',
                    style: text.micro.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: Space.s5,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
