import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// What the picker hands back: one entity, at any level of the hierarchy.
typedef SharedEntitySelection = ({EntityType type, String id, String title});

/// Pick a collection, subcollection or item to drop into a conversation.
///
/// The picker is the hierarchy: your collections, drill into subcollections,
/// drill into items — and **every level is shareable**, because every level is
/// a first-class object in KLECT. Typing switches to `search_all`, so you can
/// also share something you do not own.
abstract final class EntityShareSheet {
  /// Opens the picker and resolves with the chosen entity, or null.
  static Future<SharedEntitySelection?> show(BuildContext context) =>
      KSheet.show<SharedEntitySelection>(
        context: context,
        title: 'Share a collection',
        maxHeightFraction: 0.85,
        builder: (_) => const _ShareBody(),
      );
}

class _Crumb {
  const _Crumb({required this.title, this.collectionId, this.subcollectionId});

  final String title;
  final String? collectionId;
  final String? subcollectionId;
}

class _ShareBody extends ConsumerStatefulWidget {
  const _ShareBody();

  @override
  ConsumerState<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends ConsumerState<_ShareBody> {
  final TextEditingController _query = TextEditingController();
  final List<_Crumb> _trail = <_Crumb>[const _Crumb(title: 'Your collections')];

  Timer? _debounce;
  bool _loading = true;
  Object? _error;
  String _search = '';

  List<CollectionModel> _collections = const <CollectionModel>[];
  List<SubcollectionModel> _subcollections = const <SubcollectionModel>[];
  List<ItemModel> _items = const <ItemModel>[];
  SearchResults? _results;

  KlectApi get _api => ref.read(klectApiProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLevel());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadLevel() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crumb = _trail.last;
      if (crumb.subcollectionId != null) {
        final items = await _api.fetchItems(
          subcollectionId: crumb.subcollectionId,
        );
        if (!mounted) return;
        setState(() {
          _items = items;
          _loading = false;
        });
      } else if (crumb.collectionId != null) {
        final subs = await _api.fetchSubcollections(crumb.collectionId!);
        final items = await _api.fetchItems(collectionId: crumb.collectionId);
        if (!mounted) return;
        setState(() {
          _subcollections = subs;
          _items = items;
          _loading = false;
        });
      } else {
        final userId = ref.read(currentUserIdProvider);
        final collections = userId == null
            ? const <CollectionModel>[]
            : await _api.fetchCollections(userId);
        if (!mounted) return;
        setState(() {
          _collections = collections;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = KlectError.from(error);
        _loading = false;
      });
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(KDurations.medium, () => unawaited(_runSearch(value)));
  }

  Future<void> _runSearch(String value) async {
    final trimmed = value.trim();
    setState(() => _search = trimmed);
    if (trimmed.isEmpty) {
      setState(() => _results = null);
      await _loadLevel();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _api.searchAll(trimmed);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = KlectError.from(error);
        _loading = false;
      });
    }
  }

  void _pick(EntityType type, String id, String title) =>
      Navigator.of(context).pop((type: type, id: id, title: title));

  void _push(_Crumb crumb) {
    setState(() {
      _trail.add(crumb);
      _subcollections = const <SubcollectionModel>[];
      _items = const <ItemModel>[];
    });
    unawaited(_loadLevel());
  }

  void _popTo(int index) {
    if (index >= _trail.length - 1) return;
    setState(() {
      _trail.removeRange(index + 1, _trail.length);
      _subcollections = const <SubcollectionModel>[];
      _items = const <ItemModel>[];
    });
    unawaited(_loadLevel());
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.isNotEmpty;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KTextField(
            controller: _query,
            hint: 'Search collections and items',
            prefixIcon: Icons.search_rounded,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
          ),
          if (!searching) ...<Widget>[
            const SizedBox(height: Space.s3),
            _Breadcrumbs(trail: _trail, onTap: _popTo),
          ],
          const SizedBox(height: Space.s3),
          Expanded(child: _buildBody(searching: searching)),
        ],
      ),
    );
  }

  Widget _buildBody({required bool searching}) {
    if (_loading) return const KSkeletonList(rows: 4, showMedia: false);
    final error = _error;
    if (error != null) {
      return KErrorState(
        error: error,
        compact: true,
        onRetry: () => unawaited(searching ? _runSearch(_search) : _loadLevel()),
      );
    }
    if (searching) return _buildSearchResults();
    return _buildLevel();
  }

  Widget _buildSearchResults() {
    final results = _results;
    if (results == null ||
        (results.collections.isEmpty && results.items.isEmpty)) {
      return const KEmptyState(
        title: 'Nothing matched',
        message: 'Try a different word.',
        compact: true,
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        if (results.collections.isNotEmpty) ...<Widget>[
          const _SectionLabel(label: 'COLLECTIONS'),
          for (final hit in results.collections)
            _Row(
              title: hit.name,
              subtitle: '${hit.itemCount} items',
              coverPath: hit.coverPath,
              blurhash: hit.coverBlurhash,
              onTap: () =>
                  _pick(EntityType.collection, hit.id, hit.name),
            ),
        ],
        if (results.items.isNotEmpty) ...<Widget>[
          const _SectionLabel(label: 'ITEMS'),
          for (final hit in results.items)
            _Row(
              title: hit.title,
              subtitle: hit.brand,
              coverPath: hit.coverPath,
              blurhash: hit.coverBlurhash,
              onTap: () => _pick(EntityType.item, hit.id, hit.title),
            ),
        ],
      ],
    );
  }

  Widget _buildLevel() {
    final crumb = _trail.last;

    if (crumb.subcollectionId != null) {
      if (_items.isEmpty) {
        return const KEmptyState(
          title: 'Nothing in here yet',
          message: 'Add an item and it will show up.',
          compact: true,
        );
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          for (final item in _items)
            _Row(
              title: item.title,
              subtitle: item.brand,
              coverPath: item.coverPath,
              blurhash: item.coverBlurhash,
              onTap: () => _pick(EntityType.item, item.id, item.title),
            ),
        ],
      );
    }

    if (crumb.collectionId != null) {
      if (_subcollections.isEmpty && _items.isEmpty) {
        return const KEmptyState(
          title: 'Nothing in here yet',
          message: 'Add a subcollection and it will show up.',
          compact: true,
        );
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          if (_subcollections.isNotEmpty) ...<Widget>[
            const _SectionLabel(label: 'SUBCOLLECTIONS'),
            for (final sub in _subcollections)
              _Row(
                title: sub.name,
                subtitle: '${sub.itemCount} items',
                coverPath: sub.coverPath,
                blurhash: sub.coverBlurhash,
                onTap: () =>
                    _pick(EntityType.subcollection, sub.id, sub.name),
                onDrill: () => _push(
                  _Crumb(
                    title: sub.name,
                    collectionId: crumb.collectionId,
                    subcollectionId: sub.id,
                  ),
                ),
              ),
          ],
          if (_items.isNotEmpty) ...<Widget>[
            const _SectionLabel(label: 'ITEMS'),
            for (final item in _items)
              _Row(
                title: item.title,
                subtitle: item.brand,
                coverPath: item.coverPath,
                blurhash: item.coverBlurhash,
                onTap: () => _pick(EntityType.item, item.id, item.title),
              ),
          ],
        ],
      );
    }

    if (_collections.isEmpty) {
      return const KEmptyState(
        title: 'No collections yet',
        message: 'Start one and it becomes shareable everywhere.',
        compact: true,
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (final collection in _collections)
          _Row(
            title: collection.name,
            subtitle: '${collection.subcollectionCount} subcollections · '
                '${collection.itemCount} items',
            coverPath: collection.coverPath,
            blurhash: collection.coverBlurhash,
            onTap: () =>
                _pick(EntityType.collection, collection.id, collection.name),
            onDrill: () => _push(
              _Crumb(title: collection.name, collectionId: collection.id),
            ),
          ),
      ],
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.trail, required this.onTap});

  final List<_Crumb> trail;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (var index = 0; index < trail.length; index++) ...<Widget>[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s1),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: Space.s4,
                  color: colors.textTertiary,
                ),
              ),
            KPressable(
              enforceMinTapTarget: false,
              onTap: index == trail.length - 1 ? null : () => onTap(index),
              semanticLabel: trail[index].title,
              child: Text(
                trail[index].title,
                style: context.kt.label.copyWith(
                  color: index == trail.length - 1
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.s3, bottom: Space.s2),
        child: Text(
          label,
          style: context.kt.micro.copyWith(color: context.kc.textTertiary),
        ),
      );
}

class _Row extends ConsumerWidget {
  const _Row({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.coverPath,
    this.blurhash,
    this.onDrill,
  });

  final String title;
  final String? subtitle;
  final String? coverPath;
  final String? blurhash;
  final VoidCallback onTap;
  final VoidCallback? onDrill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final url = ref.watch(klectApiProvider).publicUrl(coverPath);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: KPressable(
              onTap: onTap,
              enforceMinTapTarget: false,
              semanticLabel: 'Share $title',
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: Space.s12,
                    height: Space.s12,
                    child: KBlurhashImage(
                      url: url,
                      blurhash: blurhash,
                      aspectRatio: Aspect.cover,
                      borderRadius:
                          BorderRadius.circular(Radii.sm),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: context.kt.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: context.kt.caption
                                .copyWith(color: colors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onDrill != null)
            KIconButton(
              icon: Icons.chevron_right_rounded,
              semanticLabel: 'Open $title',
              onPressed: onDrill,
            ),
        ],
      ),
    );
  }
}
