import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../data/pulse_filters.dart';

/// The Pulse filter drawer — collapses out from under the For-you|Following
/// tabs.
///
/// Three chip rows tune what the stream shows (Type, Time, shared taste; all
/// client-side over the fetched pages, so every tap is instant), and a
/// search field queries `search_all`'s 0021 posts section, showing hits
/// right here in the drawer — each one deep-links to its thread.
class PulseFilterDrawer extends ConsumerStatefulWidget {
  /// Creates the drawer.
  const PulseFilterDrawer({super.key});

  @override
  ConsumerState<PulseFilterDrawer> createState() => _PulseFilterDrawerState();
}

class _PulseFilterDrawerState extends ConsumerState<PulseFilterDrawer> {
  final TextEditingController _query = TextEditingController();

  List<PostSearchHit>? _hits;
  bool _searching = false;
  String? _searchError;
  String _lastQuery = '';

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
      final results =
          await ref.read(klectApiProvider).searchAll(query, limit: 8);
      if (!mounted || _lastQuery != query) return;
      setState(() => _hits = results.posts);
    } on KlectError catch (error) {
      if (!mounted || _lastQuery != query) return;
      setState(() => _searchError = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final filters = ref.watch(pulseFiltersProvider);
    final controller = ref.read(pulseFiltersProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          bottom: BorderSide(
            color: colors.borderSubtle,
            width: Strokes.hairline,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ChipRow(
            label: 'TYPE',
            children: <Widget>[
              for (final type in PulseTypeFilter.values)
                KChip(
                  label: type.label,
                  selected: type == filters.type,
                  dense: true,
                  onTap: () => controller.setType(type),
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          _ChipRow(
            label: 'TIME',
            children: <Widget>[
              for (final time in PulseTimeFilter.values)
                KChip(
                  label: time.label,
                  selected: time == filters.time,
                  dense: true,
                  onTap: () => controller.setTime(time),
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_outlined,
                size: Space.s4,
                color: filters.sharedTaste
                    ? colors.accentDefault
                    : colors.textTertiary,
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Shared taste only', style: text.label),
                    Text(
                      'Rows from collectors whose taste matches yours.',
                      style:
                          text.caption.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: filters.sharedTaste,
                onChanged: (_) => controller.toggleSharedTaste(),
              ),
            ],
          ),
          if (filters.isActive) ...<Widget>[
            const SizedBox(height: Space.s1),
            Align(
              alignment: Alignment.centerLeft,
              child: KButton(
                label: 'Clear filters',
                variant: KButtonVariant.ghost,
                size: KButtonSize.small,
                icon: Icons.filter_alt_off_outlined,
                onPressed: controller.clear,
              ),
            ),
          ],
          const SizedBox(height: Space.s3),
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
                : (_hits == null && _searchError == null)
                    ? null
                    : KIconButton(
                        icon: Icons.close_rounded,
                        semanticLabel: 'Clear search',
                        size: Space.s4,
                        onPressed: () {
                          _query.clear();
                          unawaited(_search(''));
                        },
                      ),
          ),
          ..._searchSection(),
        ],
      ),
    );
  }

  List<Widget> _searchSection() {
    final colors = context.kc;
    final text = context.kt;
    final error = _searchError;
    if (error != null) {
      return <Widget>[
        const SizedBox(height: Space.s2),
        KInlineError(
          message: error,
          onRetry: () => unawaited(_search(_lastQuery)),
        ),
      ];
    }
    final hits = _hits;
    if (hits == null) return const <Widget>[];
    if (hits.isEmpty) {
      return <Widget>[
        const SizedBox(height: Space.s2),
        Text(
          'No posts match “$_lastQuery”.',
          style: text.caption.copyWith(color: colors.textTertiary),
        ),
      ];
    }
    return <Widget>[
      const SizedBox(height: Space.s2),
      for (final hit in hits)
        _PostHitRow(key: ValueKey<String>(hit.id), hit: hit),
    ];
  }
}

/// One labelled chip row.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: Space.s12,
          child: Text(
            label,
            style: context.kt.micro.copyWith(color: colors.textTertiary),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final chip in children) ...<Widget>[
                  chip,
                  const SizedBox(width: Space.s2),
                ],
              ],
            ),
          ),
        ),
      ],
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
    final avatarUrl = ref.watch(klectApiProvider).publicUrl(
          author?.avatarPath,
          bucket: StorageBucket.avatars,
        );

    return KPressable(
      onTap: () => context.push(KlectLinks.postThreadPath(hit.id)),
      enforceMinTapTarget: false,
      semanticLabel: hit.body ?? 'Post',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s2),
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
                          style: text.micro
                              .copyWith(color: colors.textTertiary),
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
                      style: text.callout
                          .copyWith(color: colors.textSecondary),
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
