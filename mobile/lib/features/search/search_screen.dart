import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/onboarding_screen.dart' show suggestedCollectorsProvider;
import '../profile/entity_tile.dart';
import '../profile/fill_viewport.dart';
import '../profile/person_row.dart';
import '../profile/profile_queries.dart';
import 'search_controller.dart';

/// One field, four kinds of answer.
///
/// `search_all` returns people, collections, items and tags in a single round
/// trip, so the segments below are a filter over one payload rather than four
/// separate searches. The zero state is never blank: recent searches, the tags
/// the whole product is using, and collectors worth following.
class SearchScreen extends ConsumerStatefulWidget {
  /// Creates the screen, optionally pre-filled from `?q=`.
  const SearchScreen({this.initialQuery, super.key});

  /// Route parameter.
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    _field = TextEditingController(text: initial);
    if (initial.isNotEmpty) {
      ref.read(searchQueryProvider.notifier).submit(initial).ignore();
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submitTerm(String term) {
    _field
      ..text = term
      ..selection = TextSelection.collapsed(offset: term.length);
    ref.read(searchQueryProvider.notifier).submit(term).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final state = ref.watch(searchQueryProvider);
    final controller = ref.read(searchQueryProvider.notifier);

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Search', showBack: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s2,
              Space.s5,
              Space.s3,
            ),
            child: KTextField(
              controller: _field,
              hint: 'People, collections, items, tags',
              prefixIcon: Icons.search_rounded,
              autofocus: widget.initialQuery == null,
              textInputAction: TextInputAction.search,
              onChanged: controller.setQuery,
              onSubmitted: (value) => controller.submit(value).ignore(),
              suffix: state.query.isEmpty
                  ? null
                  : KIconButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Clear search',
                      onPressed: () {
                        _field.clear();
                        controller.clear();
                      },
                    ),
            ),
          ),
          if (!state.isIdle)
            _SegmentBar(
              selected: state.segment,
              results: state.results,
              onChanged: controller.setSegment,
            ),
          Expanded(
            child: state.isIdle
                ? _ZeroState(onTerm: _submitTerm)
                : _Results(
                    state: state,
                    onTerm: _submitTerm,
                    onSegment: controller.setSegment,
                    onRetry: () => controller.run().ignore(),
                  ),
          ),
          if (state.busy)
            LinearProgressIndicator(
              minHeight: Strokes.thick,
              backgroundColor: colors.surface2,
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── chrome ──

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.selected,
    required this.results,
    required this.onChanged,
  });

  final SearchSegment selected;
  final SearchResults? results;
  final ValueChanged<SearchSegment> onChanged;

  int? _countFor(SearchSegment segment) => switch (segment) {
        SearchSegment.all => null,
        SearchSegment.people => results?.people.length,
        SearchSegment.collections => results?.collections.length,
        SearchSegment.items => results?.items.length,
        SearchSegment.tags => results?.tags.length,
      };

  @override
  Widget build(BuildContext context) => SizedBox(
        height: Space.s10,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.s5),
          itemCount: SearchSegment.values.length,
          separatorBuilder: (context, _) => const SizedBox(width: Space.s2),
          itemBuilder: (context, index) {
            final segment = SearchSegment.values[index];
            final count = _countFor(segment);
            return Center(
              child: KChip(
                label: count == null || count == 0
                    ? segment.label
                    : '${segment.label} ${formatCount(count)}',
                selected: segment == selected,
                onTap: () => onChanged(segment),
              ),
            );
          },
        ),
      );
}

// ────────────────────────────────────────────────────────────── zero state ──

class _ZeroState extends ConsumerWidget {
  const _ZeroState({required this.onTerm});

  final ValueChanged<String> onTerm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final recents = ref.watch(recentSearchesProvider);
    final trending = ref.watch(trendingTagsProvider);
    final collectors = ref.watch(suggestedCollectorsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s2,
        Space.s5,
        Space.s20,
      ),
      children: <Widget>[
        if (recents.isNotEmpty) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'RECENT',
                  style: context.kt.micro
                      .copyWith(color: colors.textTertiary),
                ),
              ),
              KPressable(
                onTap: () =>
                    ref.read(recentSearchesProvider.notifier).clear().ignore(),
                enforceMinTapTarget: false,
                semanticLabel: 'Clear recent searches',
                child: Text(
                  'Clear',
                  style: context.kt.label
                      .copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: <Widget>[
              for (final term in recents)
                KChip(
                  label: term,
                  icon: Icons.history_rounded,
                  onTap: () => onTerm(term),
                  onRemove: () => ref
                      .read(recentSearchesProvider.notifier)
                      .remove(term)
                      .ignore(),
                ),
            ],
          ),
          const SizedBox(height: Space.s8),
        ],
        Text(
          'TRENDING TAGS',
          style: context.kt.micro.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: Space.s3),
        trending.when(
          loading: () => const KShimmer(
            child: Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: <Widget>[
                KSkeleton(width: Space.s20, height: Space.s8),
                KSkeleton(width: Space.s16, height: Space.s8),
                KSkeleton(width: Space.s24, height: Space.s8),
                KSkeleton(width: Space.s20, height: Space.s8),
              ],
            ),
          ),
          error: (error, _) => KInlineError(
            message: 'Could not load tags.',
            onRetry: () => ref.invalidate(trendingTagsProvider),
          ),
          data: (tags) => tags.isEmpty
              ? Text(
                  'No tags yet — you get to invent them.',
                  style: context.kt.body
                      .copyWith(color: colors.textSecondary),
                )
              : Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: <Widget>[
                    for (final tag in tags)
                      KChip(
                        label: '#${tag.name}',
                        onTap: () => onTerm(tag.name),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: Space.s8),
        Text(
          'COLLECTORS TO WATCH',
          style: context.kt.micro.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: Space.s2),
        collectors.when(
          loading: () => const KSkeletonList(rows: 4, showMedia: false),
          error: (error, _) => KInlineError(
            message: 'Could not load collectors.',
            onRetry: () => ref.invalidate(suggestedCollectorsProvider),
          ),
          data: (people) => Column(
            children: <Widget>[
              for (final person in people.take(6))
                PersonRow(profile: person, dense: true),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────── results ──

class _Results extends StatelessWidget {
  const _Results({
    required this.state,
    required this.onTerm,
    required this.onSegment,
    required this.onRetry,
  });

  final SearchQueryState state;
  final ValueChanged<String> onTerm;
  final ValueChanged<SearchSegment> onSegment;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = state.error;
    if (error != null) {
      return FillViewport(
        child: KErrorState(error: error, onRetry: onRetry),
      );
    }
    final results = state.results;
    if (results == null) {
      return const FillViewport(
        child: KSkeletonList(rows: 5, showMedia: false),
      );
    }
    if (results.isEmpty) {
      return FillViewport(
        child: KEmptyState(
          title: 'Nothing matches',
          message: 'No people, collections, items or tags for '
              '"${state.query.trim()}". Try a shorter word.',
          icon: Icons.search_off_rounded,
        ),
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        ...switch (state.segment) {
          SearchSegment.all => _allSections(context, results),
          SearchSegment.people => <Widget>[_peopleSliver(results.people)],
          SearchSegment.collections => <Widget>[
              _cardsSliver(context, <ProfileEntityCard>[
                for (final hit in results.collections)
                  ProfileEntityCard.fromSearchCollection(hit),
              ]),
            ],
          SearchSegment.items => <Widget>[
              _cardsSliver(context, <ProfileEntityCard>[
                for (final hit in results.items)
                  ProfileEntityCard.fromSearchItem(hit),
              ]),
            ],
          SearchSegment.tags => <Widget>[_tagsSliver(results.tags)],
        },
        const SliverToBoxAdapter(child: SizedBox(height: Space.s20)),
      ],
    );
  }

  List<Widget> _allSections(BuildContext context, SearchResults results) =>
      <Widget>[
        if (results.people.isNotEmpty) ...<Widget>[
          _header(context, 'People', () => onSegment(SearchSegment.people)),
          _peopleSliver(results.people.take(3).toList()),
        ],
        if (results.tags.isNotEmpty) ...<Widget>[
          _header(context, 'Tags', () => onSegment(SearchSegment.tags)),
          _tagsSliver(results.tags.take(8).toList()),
        ],
        if (results.collections.isNotEmpty) ...<Widget>[
          _header(
            context,
            'Collections',
            () => onSegment(SearchSegment.collections),
          ),
          _cardsSliver(context, <ProfileEntityCard>[
            for (final hit in results.collections.take(4))
              ProfileEntityCard.fromSearchCollection(hit),
          ]),
        ],
        if (results.items.isNotEmpty) ...<Widget>[
          _header(context, 'Items', () => onSegment(SearchSegment.items)),
          _cardsSliver(context, <ProfileEntityCard>[
            for (final hit in results.items.take(6))
              ProfileEntityCard.fromSearchItem(hit),
          ]),
        ],
      ];

  Widget _header(BuildContext context, String label, VoidCallback onSeeAll) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s5,
            Space.s5,
            Space.s5,
            Space.s2,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: context.kt.micro
                      .copyWith(color: context.kc.textTertiary),
                ),
              ),
              KPressable(
                onTap: onSeeAll,
                enforceMinTapTarget: false,
                semanticLabel: 'See all $label',
                child: Text(
                  'See all',
                  style: context.kt.label
                      .copyWith(color: context.kc.accentDefault),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _peopleSliver(List<Profile> people) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s5),
        sliver: SliverList.builder(
          itemCount: people.length,
          itemBuilder: (context, index) =>
              PersonRow(profile: people[index], dense: true),
        ),
      );

  Widget _tagsSliver(List<TagModel> tags) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s5),
          child: Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: <Widget>[
              for (final tag in tags)
                KChip(
                  label: '#${tag.name}',
                  onTap: () => onTerm(tag.name),
                ),
            ],
          ),
        ),
      );

  Widget _cardsSliver(BuildContext context, List<ProfileEntityCard> cards) =>
      SliverPadding(
        padding: const EdgeInsets.all(Layout.masonryGutter),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                Layout.masonryColumns(MediaQuery.sizeOf(context).width),
            mainAxisSpacing: Layout.masonryGutter,
            crossAxisSpacing: Layout.masonryGutter,
            childAspectRatio: Aspect.cover,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => EntityTile(
              key: ValueKey<String>(cards[index].key),
              card: cards[index],
              index: index,
            ),
            childCount: cards.length,
          ),
        ),
      );
}
