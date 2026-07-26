import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../library/library_actions.dart';
import '../library/library_providers.dart';
import '../library/widgets/library_chrome.dart';
import 'create_providers.dart';
import 'media/image_pipeline.dart';
import 'media/photo_source_sheet.dart';
import 'media/upload_controller.dart';
import 'media/upload_journal.dart';
import 'widgets/destination_picker.dart';
import 'widgets/item_metadata_fields.dart';
import 'widgets/photo_tray.dart';
import 'widgets/save_bar.dart';
import 'widgets/visibility_field.dart';

/// Creates an item — a thing, with photos, at the bottom of the hierarchy.
///
/// The order of operations matters and is deliberate:
///  1. the `items` row is created first, because the Storage path is
///     `{user_id}/{item_id}/{uuid}` and the policy checks the first segment;
///  2. the upload journal records the item **before** a single byte is written;
///  3. photos upload one at a time, each registered as an `item_media` row the
///     moment its object lands;
///  4. the journal is closed only when everything has landed.
///
/// A kill at any point therefore leaves a record the next launch reconciles —
/// no orphan blobs, no photoless shell items.
class CreateItemScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreateItemScreen({this.collectionId, this.subcollectionId, super.key});

  /// Route parameter — pre-selects the shelf.
  final String? collectionId;

  /// Route parameter — pre-selects the group.
  final String? subcollectionId;

  @override
  ConsumerState<CreateItemScreen> createState() => _CreateItemScreenState();
}

class _CreateItemScreenState extends ConsumerState<CreateItemScreen> {
  late final ItemDraft _draft = ItemDraft();
  late final MediaUploadController _uploads = MediaUploadController(
    ref.read(klectApiProvider),
    ref.read(uploadJournalProvider),
  );

  String? _collectionId;
  String? _subcollectionId;
  String? _subcollectionName;
  String? _templateId;

  /// Set once the row exists, so a retry after a partial failure re-uses it
  /// instead of creating a second item.
  String? _createdItemId;

  bool _busy = false;
  bool _showDetails = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(mediaRecoveryProvider);
    final defaults = ref.read(createDefaultsProvider);
    _collectionId = widget.collectionId ?? defaults.collectionId;
    _subcollectionId = widget.subcollectionId ??
        (widget.collectionId == null || widget.collectionId == _collectionId
            ? defaults.subcollectionId
            : null);
  }

  @override
  void dispose() {
    _draft.dispose();
    _uploads.dispose();
    super.dispose();
  }

  bool get _isDirty => _draft.isDirty || !_uploads.isEmpty;

  bool get _canSave =>
      _collectionId != null &&
      _subcollectionId != null &&
      _draft.title.text.trim().isNotEmpty &&
      !_uploads.isEmpty &&
      !_uploads.isBusy;

  List<String> get _suggestedTags {
    final templates = ref.read(createTemplatesProvider).value;
    if (templates == null || _templateId == null) return const <String>[];
    for (final template in templates) {
      if (template.id == _templateId) return template.suggestedTags;
    }
    return const <String>[];
  }

  Future<void> _pickPhotos() async {
    if (_uploads.remainingSlots <= 0) {
      KToast.show(
        context,
        'That is ${MediaUploadController.maxPhotos} photos — the ceiling for '
        'one item.',
      );
      return;
    }
    final files = await PhotoSourceSheet.pick(
      context,
      limit: _uploads.remainingSlots,
    );
    if (files.isEmpty || !mounted) return;
    await _uploads.addFiles(files);
    if (mounted) setState(() {});
  }

  Future<void> _confirmLeave(bool didPop, Object? result) async {
    if (didPop || _busy) return;
    if (!_isDirty && _createdItemId == null) return;

    // The row already exists and some photos may have landed: the honest
    // choice is between keeping what is there and throwing all of it away.
    if (_createdItemId != null) {
      final discard = await KConfirmDialog.show(
        context,
        title: _uploads.completedCount == 0
            ? 'Delete this draft?'
            : 'Leave with ${plural(_uploads.completedCount, 'photo')} saved?',
        message: _uploads.completedCount == 0
            ? 'Nothing uploaded, so the item goes with it.'
            : 'The item stays with the photos that made it. You can add the '
                'rest later.',
        confirmLabel: _uploads.completedCount == 0 ? 'Delete draft' : 'Leave',
        cancelLabel: 'Keep editing',
        destructive: _uploads.completedCount == 0,
      );
      if (!discard || !mounted) return;
      if (_uploads.completedCount == 0) {
        await _discardCreatedItem();
      } else {
        await ref.read(uploadJournalProvider).finish(_createdItemId!);
      }
      if (!mounted) return;
      if (context.canPop()) context.pop();
      return;
    }

    final discard = await KConfirmDialog.show(
      context,
      title: 'Discard this item?',
      message: 'Nothing has been saved yet.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!discard || !mounted) return;
    if (context.canPop()) context.pop();
  }

  Future<void> _discardCreatedItem() async {
    final itemId = _createdItemId;
    if (itemId == null) return;
    await _uploads.discard(itemId: itemId, includeCommitted: true);
    try {
      await ref.read(libraryActionsProvider).deleteItem(itemId);
    } on KlectError {
      // The journal sweep will finish the job on the next launch.
    }
    _createdItemId = null;
  }

  void _back() {
    if (_isDirty || _createdItemId != null) {
      unawaited(_confirmLeave(false, null));
    } else if (context.canPop()) {
      context.pop();
    }
  }

  Future<void> _save() async {
    final collectionId = _collectionId;
    final subcollectionId = _subcollectionId;
    final title = _draft.title.text.trim();

    if (collectionId == null || subcollectionId == null) {
      setState(() => _error = 'Choose a shelf and a group first.');
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = 'Give the item a title.');
      return;
    }
    if (_uploads.isEmpty) {
      setState(() => _error = 'Add at least one photo.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final api = ref.read(klectApiProvider);
    final journal = ref.read(uploadJournalProvider);

    try {
      var itemId = _createdItemId;
      if (itemId == null) {
        final existing = await api.fetchItems(
          subcollectionId: subcollectionId,
          limit: 200,
        );
        final item = await api.createItem(
          collectionId: collectionId,
          subcollectionId: subcollectionId,
          title: title,
          description: _draft.description.text.trim().isEmpty
              ? null
              : _draft.description.text.trim(),
          brand: _blank(_draft.brand.text),
          model: _blank(_draft.model.text),
          year: _draft.yearValue,
          condition: _draft.condition,
          rarity: _draft.rarity,
          purchasePrice: _draft.priceValue,
          currency: _draft.priceValue == null ? null : _draft.currency,
          attributes: _draft.attributes(const <String, dynamic>{}),
          visibility: _draft.visibility,
        );
        itemId = item.id;
        _createdItemId = itemId;

        // Columns `create_item` does not take, plus the tail position.
        await ref.read(libraryActionsProvider).editItem(
              itemId,
              acquisitionDate: _draft.acquisitionDate,
              acquisitionPlace: _draft.acquisitionPlace.text,
              isFavorite: _draft.isFavorite,
            );
        await ref.read(libraryActionsProvider).appendPosition(
              table: 'items',
              id: itemId,
              position: existing.length,
            );

        await journal.begin(
          itemId: itemId,
          userId: api.requireUserId,
          newItem: true,
        );
      }

      final outcome = await _uploads.uploadAll(itemId: itemId);
      if (!mounted) return;

      await ref.read(createDefaultsProvider).remember(
            collectionId: collectionId,
            subcollectionId: subcollectionId,
          );
      if (!mounted) return;

      ref.refreshLibrary(
        collectionId: collectionId,
        subcollectionId: subcollectionId,
        itemId: itemId,
      );

      if (outcome.isComplete) {
        KToast.success(context, '$title added.');
        context.pushReplacement('/i/$itemId');
        return;
      }

      setState(() {
        _busy = false;
        _error = outcome.cancelled
            ? 'Stopped after ${outcome.uploaded} of ${_uploads.length} '
                'photos. Save again to finish.'
            : '${outcome.failed} photo(s) did not upload. Tap one to retry, '
                'or save again.';
      });
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  static String? _blank(String value) =>
      value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final collectionId = _collectionId;

    return KScaffold(
      canPop: !_isDirty && _createdItemId == null,
      onPopInvoked: _confirmLeave,
      appBar: KFixedAppBar(
        title: 'New item',
        showBack: true,
        onBack: _back,
      ),
      bottomBar: ListenableBuilder(
        listenable: _uploads,
        builder: (context, _) => CreateSaveBar(
          label: _createdItemId == null ? 'Add item' : 'Finish uploading',
          busy: _busy,
          enabled: _canSave,
          progress: _busy ? _uploads.overallProgress : null,
          note: _uploads.isEmpty
              ? 'An item needs at least one photo.'
              : (_busy
                  ? '${_uploads.completedCount} of ${_uploads.length} uploaded'
                  : null),
          onSave: _save,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s4,
          Space.s8,
        ),
        children: <Widget>[
          PhotoTray(
            controller: _uploads,
            enabled: !_busy,
            onAdd: () => unawaited(_pickPhotos()),
          ),
          const SizedBox(height: Space.s5),
          KTextField(
            controller: _draft.title,
            label: 'Title',
            hint: 'Gojo — Vol. 11 cover',
            enabled: !_busy,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: _draft.description,
            label: 'Description',
            hint: 'Condition is honest — some shelf wear, no cracks.',
            maxLines: 5,
            minLines: 2,
            maxLength: 1000,
            enabled: !_busy,
          ),
          const SizedBox(height: Space.s5),
          CollectionChooser(
            selectedId: collectionId,
            enabled: !_busy,
            onSelected: (shelf) => setState(() {
              _collectionId = shelf.id;
              _templateId = shelf.templateId;
              _subcollectionId = null;
              _subcollectionName = null;
            }),
          ),
          if (collectionId != null) ...<Widget>[
            const SizedBox(height: Space.s5),
            SubcollectionChooser(
              collectionId: collectionId,
              selectedId: _subcollectionId,
              enabled: !_busy,
              onSelected: (group) => setState(() {
                _subcollectionId = group.id;
                _subcollectionName = group.name;
              }),
            ),
          ],
          const SizedBox(height: Space.s5),
          VisibilityField(
            value: _draft.visibility,
            allowInherit: true,
            inheritLabel: _subcollectionName == null
                ? 'Same as the group'
                : 'Same as $_subcollectionName',
            enabled: !_busy,
            onChanged: (value) => setState(() => _draft.visibility = value),
          ),
          const SizedBox(height: Space.s5),
          _DetailsToggle(
            expanded: _showDetails,
            onTap: () => setState(() => _showDetails = !_showDetails),
          ),
          AnimatedSize(
            duration: KMotion.duration(context, KDurations.base),
            curve: KCurves.emphasized,
            alignment: Alignment.topCenter,
            child: _showDetails
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.s4),
                    child: ItemMetadataFields(
                      draft: _draft,
                      enabled: !_busy,
                      suggestedTags: _suggestedTags,
                      onChanged: () => setState(() {}),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: Space.s4),
            KInlineError(message: _error!),
          ],
          const SizedBox(height: Space.s4),
          Text(
            'Photos are shrunk to ${ImagePipeline.maxLongEdge}px on the long '
            'edge and re-encoded at quality ${ImagePipeline.quality} before '
            'they leave the phone, so a 12 MP capture never becomes a 12 MP '
            'upload.',
            style: context.kt.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      semanticLabel: expanded ? 'Hide details' : 'Add details',
      enforceMinTapTarget: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.tune_rounded,
              size: Space.s5,
              color: colors.textSecondary,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                expanded ? 'Details' : 'Add details',
                style: context.kt.bodyStrong,
              ),
            ),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: KMotion.duration(context, KDurations.fast),
              child: Icon(
                Icons.expand_more_rounded,
                size: Space.s5,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
