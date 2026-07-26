import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../create/widgets/item_metadata_fields.dart';
import '../../create/widgets/visibility_field.dart';
import '../library_actions.dart';
import '../library_providers.dart';

/// Where an item is being moved to.
@immutable
class MoveTarget {
  /// Creates a move target.
  const MoveTarget({
    required this.collectionId,
    required this.subcollectionId,
    required this.subcollectionName,
  });

  /// Destination shelf.
  final String collectionId;

  /// Destination group.
  final String subcollectionId;

  /// Destination group's name, for the confirmation toast.
  final String subcollectionName;
}

/// The full item metadata editor.
abstract final class EditItemSheet {
  /// Opens the sheet. Resolves true when something was saved.
  static Future<bool> show(
    BuildContext context, {
    required ItemModel item,
    String? parentName,
    List<String> suggestedTags = const <String>[],
  }) async =>
      await KSheet.show<bool>(
        context: context,
        title: 'Edit item',
        maxHeightFraction: 0.94,
        builder: (sheetContext) => _EditItemBody(
          item: item,
          parentName: parentName,
          suggestedTags: suggestedTags,
        ),
      ) ??
      false;
}

class _EditItemBody extends ConsumerStatefulWidget {
  const _EditItemBody({
    required this.item,
    required this.parentName,
    required this.suggestedTags,
  });

  final ItemModel item;
  final String? parentName;
  final List<String> suggestedTags;

  @override
  ConsumerState<_EditItemBody> createState() => _EditItemBodyState();
}

class _EditItemBodyState extends ConsumerState<_EditItemBody> {
  late final ItemDraft _draft = ItemDraft(from: widget.item);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _draft.title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'An item needs a title.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(libraryActionsProvider).editItem(
            widget.item.id,
            title: title,
            description: _draft.description.text,
            brand: _draft.brand.text,
            model: _draft.model.text,
            year: _draft.yearValue,
            clearYear: _draft.year.text.trim().isEmpty,
            condition: _draft.condition ?? '',
            rarity: _draft.rarity ?? '',
            acquisitionDate: _draft.acquisitionDate,
            clearAcquisitionDate: _draft.acquisitionDate == null,
            acquisitionPlace: _draft.acquisitionPlace.text,
            purchasePrice: _draft.priceValue,
            clearPurchasePrice: _draft.price.text.trim().isEmpty,
            currency: _draft.priceValue == null ? '' : _draft.currency,
            isFavorite: _draft.isFavorite,
            visibility: _draft.visibility,
            clearVisibility: _draft.visibility == null,
            attributes: _draft.attributes(widget.item.attributes),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    KTextField(
                      controller: _draft.title,
                      label: 'Title',
                      enabled: !_busy,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: Space.s4),
                    KTextField(
                      controller: _draft.description,
                      label: 'Description',
                      maxLines: 5,
                      minLines: 2,
                      maxLength: 1000,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: Space.s5),
                    ItemMetadataFields(
                      draft: _draft,
                      enabled: !_busy,
                      suggestedTags: widget.suggestedTags,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: Space.s5),
                    VisibilityField(
                      value: _draft.visibility,
                      allowInherit: true,
                      inheritLabel: widget.parentName == null
                          ? 'Same as the group'
                          : 'Same as ${widget.parentName}',
                      enabled: !_busy,
                      onChanged: (value) =>
                          setState(() => _draft.visibility = value),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: Space.s3),
              KInlineError(message: _error!),
            ],
            const SizedBox(height: Space.s5),
            Row(
              children: <Widget>[
                Expanded(
                  child: KButton(
                    label: 'Cancel',
                    variant: KButtonVariant.secondary,
                    expand: true,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: KButton(
                    label: 'Save item',
                    expand: true,
                    busy: _busy,
                    onPressed: _busy ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// Moves an item to another group — on this shelf or a different one.
abstract final class MoveItemSheet {
  /// Opens the sheet. Resolves with the destination, or null when cancelled.
  static Future<MoveTarget?> show(
    BuildContext context, {
    required String currentCollectionId,
    required String currentSubcollectionId,
  }) =>
      KSheet.show<MoveTarget>(
        context: context,
        title: 'Move to…',
        maxHeightFraction: 0.85,
        builder: (sheetContext) => _MoveBody(
          currentCollectionId: currentCollectionId,
          currentSubcollectionId: currentSubcollectionId,
        ),
      );
}

class _MoveBody extends ConsumerStatefulWidget {
  const _MoveBody({
    required this.currentCollectionId,
    required this.currentSubcollectionId,
  });

  final String currentCollectionId;
  final String currentSubcollectionId;

  @override
  ConsumerState<_MoveBody> createState() => _MoveBodyState();
}

class _MoveBodyState extends ConsumerState<_MoveBody> {
  late String _collectionId = widget.currentCollectionId;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final collections = ref.watch(myCollectionsProvider);
    final groups = ref.watch(subcollectionsOfProvider(_collectionId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        collections.when(
          loading: () => const KSkeletonList(rows: 1, showMedia: false),
          error: (error, _) => KErrorState(error: error, compact: true),
          data: (shelves) => Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: <Widget>[
              for (final shelf in shelves)
                KChip(
                  label: shelf.name,
                  selected: shelf.id == _collectionId,
                  dense: true,
                  onTap: () => setState(() => _collectionId = shelf.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        Flexible(
          child: groups.when(
            loading: () => const KSkeletonList(rows: 3, showMedia: false),
            error: (error, _) => KErrorState(
              error: error,
              compact: true,
              onRetry: () =>
                  ref.invalidate(subcollectionsOfProvider(_collectionId)),
            ),
            data: (rows) => rows.isEmpty
                ? const KEmptyState(
                    title: 'No groups here yet',
                    message: 'Create one on that shelf first, then move the '
                        'item into it.',
                    compact: true,
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final group = rows[index];
                      final isCurrent =
                          group.id == widget.currentSubcollectionId;
                      return KPressable(
                        enabled: !isCurrent,
                        semanticLabel: 'Move to ${group.name}',
                        onTap: () => Navigator.of(context).pop(
                          MoveTarget(
                            collectionId: _collectionId,
                            subcollectionId: group.id,
                            subcollectionName: group.name,
                          ),
                        ),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: Space.s3),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                isCurrent
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.folder_rounded,
                                size: Space.s5,
                                color: isCurrent
                                    ? colors.accentDefault
                                    : colors.textSecondary,
                              ),
                              const SizedBox(width: Space.s3),
                              Expanded(
                                child: Text(
                                  group.name,
                                  style: context.kt.body.copyWith(
                                    color: isCurrent
                                        ? colors.textTertiary
                                        : colors.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '${group.itemCount}',
                                style: context.kt.count
                                    .copyWith(color: colors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
