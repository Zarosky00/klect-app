import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../library/library_actions.dart';
import '../../library/library_providers.dart';

/// Picks which shelf something is being filed onto.
class CollectionChooser extends ConsumerWidget {
  /// Creates a shelf picker.
  const CollectionChooser({
    required this.selectedId,
    required this.onSelected,
    super.key,
    this.enabled = true,
    this.label = 'Shelf',
  });

  /// Currently chosen shelf.
  final String? selectedId;

  /// Fired with the chosen shelf.
  final ValueChanged<CollectionModel> onSelected;

  /// Disables interaction while a save is in flight.
  final bool enabled;

  /// Field label.
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final collections = ref.watch(myCollectionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: context.kt.label.copyWith(color: colors.textSecondary)),
        const SizedBox(height: Space.s2),
        collections.when(
          loading: () => const KShimmer(
            child: Wrap(
              spacing: Space.s2,
              children: <Widget>[
                KSkeleton(width: Space.s20, height: Space.s8),
                KSkeleton(width: Space.s16, height: Space.s8),
              ],
            ),
          ),
          error: (error, _) => KErrorState(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(myCollectionsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? KEmptyState(
                  title: 'No shelves yet',
                  message: 'Everything has to live on a shelf. Make one first '
                      '— it takes a name and nothing else.',
                  icon: Icons.collections_bookmark_rounded,
                  compact: true,
                  actionLabel: 'New shelf',
                  onAction: () async {
                    final created = await context.push<CollectionModel>(
                      '/create/collection?return=1',
                    );
                    if (created != null) onSelected(created);
                  },
                )
              : Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: <Widget>[
                    for (final shelf in rows)
                      KChip(
                        label: shelf.name,
                        selected: shelf.id == selectedId,
                        onTap: enabled ? () => onSelected(shelf) : null,
                      ),
                    KChip(
                      label: 'New shelf',
                      icon: Icons.add_rounded,
                      onTap: enabled
                          ? () async {
                              // `return=1` makes the shelf form pop back here
                              // with the created row instead of navigating to
                              // it — the filing flow the user was in resumes
                              // with the new shelf already chosen.
                              final created =
                                  await context.push<CollectionModel>(
                                '/create/collection?return=1',
                              );
                              if (created != null) onSelected(created);
                            }
                          : null,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Picks which group something is being filed into, and can create one on the
/// spot.
///
/// An item **must** have a subcollection, so a shelf with no groups would be a
/// dead end — the inline creator is what stops that from happening.
class SubcollectionChooser extends ConsumerStatefulWidget {
  /// Creates a group picker.
  const SubcollectionChooser({
    required this.collectionId,
    required this.selectedId,
    required this.onSelected,
    super.key,
    this.enabled = true,
    this.label = 'Group',
  });

  /// The shelf whose groups are offered.
  final String collectionId;

  /// Currently chosen group.
  final String? selectedId;

  /// Fired with the chosen group.
  final ValueChanged<SubcollectionModel> onSelected;

  /// Disables interaction while a save is in flight.
  final bool enabled;

  /// Field label.
  final String label;

  @override
  ConsumerState<SubcollectionChooser> createState() =>
      _SubcollectionChooserState();
}

class _SubcollectionChooserState extends ConsumerState<SubcollectionChooser> {
  final TextEditingController _quickName = TextEditingController();
  bool _creating = false;
  bool _showQuickCreate = false;
  String? _error;

  @override
  void dispose() {
    _quickName.dispose();
    super.dispose();
  }

  Future<void> _quickCreate() async {
    final name = _quickName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final api = ref.read(klectApiProvider);
      final existing = await api.fetchSubcollections(widget.collectionId);
      final created = await api.createSubcollection(
        collectionId: widget.collectionId,
        name: name,
      );
      await ref.read(libraryActionsProvider).appendPosition(
            table: 'subcollections',
            id: created.id,
            position: existing.length,
          );
      if (!mounted) return;
      ref.refreshLibrary(collectionId: widget.collectionId);
      _quickName.clear();
      setState(() {
        _creating = false;
        _showQuickCreate = false;
      });
      widget.onSelected(created);
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final groups = ref.watch(subcollectionsOfProvider(widget.collectionId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          widget.label,
          style: context.kt.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s2),
        groups.when(
          loading: () => const KShimmer(
            child: Wrap(
              spacing: Space.s2,
              children: <Widget>[
                KSkeleton(width: Space.s16, height: Space.s8),
                KSkeleton(width: Space.s20, height: Space.s8),
              ],
            ),
          ),
          error: (error, _) => KErrorState(
            error: error,
            compact: true,
            onRetry: () =>
                ref.invalidate(subcollectionsOfProvider(widget.collectionId)),
          ),
          data: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (rows.isEmpty && !_showQuickCreate)
                Text(
                  'This shelf has no groups yet. Name the first one and the '
                  'item goes straight into it.',
                  style:
                      context.kt.caption.copyWith(color: colors.textTertiary),
                ),
              Wrap(
                spacing: Space.s2,
                runSpacing: Space.s2,
                children: <Widget>[
                  for (final group in rows)
                    KChip(
                      label: group.name,
                      selected: group.id == widget.selectedId,
                      onTap: widget.enabled
                          ? () => widget.onSelected(group)
                          : null,
                    ),
                  if (!_showQuickCreate)
                    KChip(
                      label: 'New group',
                      icon: Icons.add_rounded,
                      onTap: widget.enabled
                          ? () => setState(() => _showQuickCreate = true)
                          : null,
                    ),
                ],
              ),
              if (_showQuickCreate) ...<Widget>[
                const SizedBox(height: Space.s2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: KTextField(
                        controller: _quickName,
                        hint: 'JJK',
                        autofocus: true,
                        enabled: widget.enabled && !_creating,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _quickCreate(),
                      ),
                    ),
                    const SizedBox(width: Space.s2),
                    KButton(
                      label: 'Add',
                      size: KButtonSize.medium,
                      busy: _creating,
                      onPressed:
                          widget.enabled && !_creating ? _quickCreate : null,
                    ),
                  ],
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: Space.s2),
                KInlineError(message: _error!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
