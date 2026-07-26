import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../library/library_actions.dart';
import '../library/library_providers.dart';
import '../library/widgets/library_chrome.dart';
import 'create_providers.dart';
import 'frame/frame_beat.dart';
import 'media/photo_source_sheet.dart';
import 'media/upload_controller.dart';
import 'media/upload_journal.dart';
import 'pick/pick_grid.dart';
import 'widgets/destination_picker.dart';
import 'widgets/item_metadata_fields.dart';
import 'widgets/photo_tray.dart';
import 'widgets/save_bar.dart';
import 'widgets/visibility_field.dart';

const Uuid _uuid = Uuid();

/// What the flow reports to whoever pushed it.
abstract final class CreateFlowResult {
  /// The draft is still alive — the caller may keep showing its photos.
  static const String kept = 'kept';

  /// The draft ended here (saved, discarded, or handed to the background) —
  /// the caller should start a fresh one.
  static const String consumed = 'consumed';
}

/// The three beats of the flow.
enum _Beat { pick, frame, file }

/// The media-first item creator: **PICK → FRAME → FILE**.
///
/// The old form asked for a title before it would even show a photo. This
/// flow inverts it: photos first (they start preparing the moment they land),
/// then the crop/rotate pass, and only then one compact filing step.
///
/// The order of operations at save is deliberate and unchanged:
///  1. the `items` row is created first, because the Storage path is
///     `{user_id}/{item_id}/{uuid}` and the policy checks the first segment;
///  2. the upload journal records the item **before** a single byte is
///     written;
///  3. photos upload one at a time, each registered as an `item_media` row
///     the moment its object lands;
///  4. the journal is closed only when everything has landed.
///
/// The upload engine lives in [mediaUploadControllerProvider] keyed by draft
/// id, so leaving mid-upload no longer kills the upload — it finishes in the
/// background and the library refreshes through the container.
class CreateItemFlowScreen extends ConsumerStatefulWidget {
  /// Creates the flow.
  const CreateItemFlowScreen({
    this.draftId,
    this.collectionId,
    this.subcollectionId,
    super.key,
  });

  /// Draft handed over by the Create tab, photos already picked. Null when a
  /// library surface opened the flow cold — it starts on PICK instead.
  final String? draftId;

  /// Route parameter — pre-selects the shelf.
  final String? collectionId;

  /// Route parameter — pre-selects the group.
  final String? subcollectionId;

  @override
  ConsumerState<CreateItemFlowScreen> createState() =>
      _CreateItemFlowScreenState();
}

class _CreateItemFlowScreenState extends ConsumerState<CreateItemFlowScreen> {
  late final String _draftId = widget.draftId ?? _uuid.v4();
  late final ItemDraft _draft = ItemDraft();
  late final PageController _page;
  final GlobalKey<FrameBeatState> _frameKey = GlobalKey<FrameBeatState>();

  late _Beat _beat;

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

  /// True when the Create tab handed the draft over — its PICK grid is one
  /// step behind us, so back from FRAME returns there instead of duplicating
  /// the beat.
  bool get _fromTab => widget.draftId != null;

  /// Cached instance, not a live read: after the draft is invalidated a
  /// rebuild must not resurrect a fresh provider state under the dead key.
  late final MediaUploadController _uploads =
      ref.read(mediaUploadControllerProvider(_draftId));

  @override
  void initState() {
    super.initState();
    ref.read(mediaRecoveryProvider);
    _beat = _fromTab && !_uploads.isEmpty ? _Beat.frame : _Beat.pick;
    _page = PageController(initialPage: _beat.index);
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
    _page.dispose();
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

  // ─────────────────────────────────────────────────────────── navigation ──

  void _go(_Beat beat) {
    if (beat == _Beat.file) _frameKey.currentState?.commitAll();
    setState(() => _beat = beat);
    unawaited(
      _page.animateToPage(
        beat.index,
        duration: KMotion.duration(context, KDurations.base),
        curve: KMotion.curve(context, KCurves.emphasized),
      ),
    );
  }

  void _back() {
    switch (_beat) {
      case _Beat.file:
        _go(_Beat.frame);
      case _Beat.frame:
        if (_fromTab) {
          // The tab's grid still owns these photos; commit the frames so its
          // thumbs show them and hand the draft back untouched.
          _frameKey.currentState?.commitAll();
          _popWith(CreateFlowResult.kept, invalidateDraft: false);
        } else {
          _go(_Beat.pick);
        }
      case _Beat.pick:
        unawaited(_exit());
    }
  }

  void _popWith(String result, {required bool invalidateDraft}) {
    if (invalidateDraft) {
      ref.invalidate(mediaUploadControllerProvider(_draftId));
    }
    if (context.canPop()) context.pop(result);
  }

  Future<void> _confirmLeave(bool didPop, Object? result) async {
    if (didPop) return;
    _back();
  }

  /// The end-of-the-line exit: everything here leaves the route.
  Future<void> _exit() async {
    if (_busy) {
      final leave = await KConfirmDialog.show(
        context,
        title: 'Keep uploading?',
        message: 'The upload keeps running while you do other things — the '
            'item appears on its shelf as soon as everything lands.',
        confirmLabel: 'Leave',
        cancelLabel: 'Stay',
      );
      if (!leave || !mounted) return;
      // The draft is the background upload's now; _save cleans it up.
      _popWith(CreateFlowResult.consumed, invalidateDraft: false);
      return;
    }

    // The row already exists and some photos may have landed: the honest
    // choice is between keeping what is there and throwing all of it away.
    if (_createdItemId != null) {
      final uploads = _uploads;
      final discard = await KConfirmDialog.show(
        context,
        title: uploads.completedCount == 0
            ? 'Delete this draft?'
            : 'Leave with ${plural(uploads.completedCount, 'photo')} saved?',
        message: uploads.completedCount == 0
            ? 'Nothing uploaded, so the item goes with it.'
            : 'The item stays with the photos that made it. You can add the '
                'rest later.',
        confirmLabel: uploads.completedCount == 0 ? 'Delete draft' : 'Leave',
        cancelLabel: 'Keep editing',
        destructive: uploads.completedCount == 0,
      );
      if (!discard || !mounted) return;
      if (uploads.completedCount == 0) {
        await _discardCreatedItem();
      } else {
        await ref.read(uploadJournalProvider).finish(_createdItemId!);
      }
      if (!mounted) return;
      _popWith(CreateFlowResult.consumed, invalidateDraft: true);
      return;
    }

    if (_isDirty) {
      final discard = await KConfirmDialog.show(
        context,
        title: 'Discard this item?',
        message: 'Nothing has been saved yet.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard || !mounted) return;
      await _uploads.discard();
      if (!mounted) return;
    }
    _popWith(CreateFlowResult.consumed, invalidateDraft: true);
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

  // ─────────────────────────────────────────────────────────────── saving ──

  Future<void> _pickMore() async {
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
    final defaults = ref.read(createDefaultsProvider);
    final uploads = _uploads;
    // The container outlives this screen — the whole point: if the user walks
    // away mid-upload, the finish work below still lands.
    final container = ProviderScope.containerOf(context, listen: false);
    final draftKey = mediaUploadControllerProvider(_draftId);

    try {
      var itemId = _createdItemId;
      if (itemId == null) {
        // Two round-trips in flight together: the tail-position probe does
        // not depend on the insert, so it rides alongside it.
        final existingFuture = api.fetchItems(
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
        final existing = await existingFuture;

        // One patch for everything `create_item` cannot take **and** the tail
        // position — this used to be two sequential round-trips. The local
        // journal write rides alongside; it must exist before any byte moves.
        final acquisitionPlace = _draft.acquisitionPlace.text.trim();
        final patch = <String, dynamic>{
          'position': existing.where((row) => row.id != itemId).length,
          if (_draft.acquisitionDate != null)
            'acquisition_date':
                _draft.acquisitionDate!.toIso8601String().substring(0, 10),
          if (acquisitionPlace.isNotEmpty)
            'acquisition_place': acquisitionPlace,
          if (_draft.isFavorite) 'is_favorite': true,
        };
        await Future.wait(<Future<void>>[
          api.updateItem(itemId, patch),
          journal.begin(
            itemId: itemId,
            userId: api.requireUserId,
            newItem: true,
          ),
        ]);
      }

      final outcome = await uploads.uploadAll(itemId: itemId);
      await defaults.remember(
        collectionId: collectionId,
        subcollectionId: subcollectionId,
      );

      // Refresh through the container, not `ref` — this runs to completion
      // even when the user has long since navigated away.
      container.invalidate(myCollectionsProvider);
      container.invalidate(collectionDetailProvider(collectionId));
      container.invalidate(subcollectionsOfProvider(collectionId));
      container.invalidate(subcollectionDetailProvider(subcollectionId));
      container.invalidate(itemDetailProvider(itemId));

      if (outcome.isComplete) {
        container.invalidate(draftKey);
        if (!mounted) return;
        KToast.success(context, '$title added.');
        context.pushReplacement('/i/$itemId');
        return;
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = outcome.cancelled
            ? 'Stopped after ${outcome.uploaded} of ${uploads.length} '
                'photos. Save again to finish.'
            : '${outcome.failed} photo(s) did not upload. Tap one to retry, '
                'or save again.';
      });
    } on KlectError catch (error) {
      if (!mounted) {
        // Failed in the background with nobody watching: release the draft;
        // the journal sweep reclaims any pending blobs on the next launch.
        container.invalidate(draftKey);
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  static String? _blank(String value) =>
      value.trim().isEmpty ? null : value.trim();

  // ──────────────────────────────────────────────────────────────── build ──

  @override
  Widget build(BuildContext context) {
    final title = switch (_beat) {
      _Beat.pick => 'Pick photos',
      _Beat.frame => 'Frame your shots',
      _Beat.file => 'File it away',
    };

    return KScaffold(
      canPop: false,
      onPopInvoked: _confirmLeave,
      appBar: KFixedAppBar(
        title: title,
        showBack: true,
        onBack: _back,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: Space.s4),
            child: Text(
              '${_beat.index + 1} / 3',
              style: context.kt.count.copyWith(
                color: context.kc.textTertiary,
              ),
            ),
          ),
        ],
      ),
      bottomBar: ListenableBuilder(
        listenable: _uploads,
        builder: (context, _) => _buildSaveBar(context),
      ),
      body: PageView(
        controller: _page,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          _buildPick(context),
          FrameBeat(key: _frameKey, controller: _uploads),
          _buildFile(context),
        ],
      ),
    );
  }

  Widget _buildSaveBar(BuildContext context) {
    final uploads = _uploads;
    return switch (_beat) {
      _Beat.pick => CreateSaveBar(
          label: uploads.isEmpty
              ? 'Pick a photo to start'
              : 'Frame ${plural(uploads.length, 'photo')}',
          enabled: !uploads.isEmpty,
          note: uploads.isEmpty ? 'An item needs at least one photo.' : null,
          onSave: () async => _go(_Beat.frame),
        ),
      _Beat.frame => CreateSaveBar(
          label: 'Next: file it',
          enabled: !uploads.isEmpty,
          onSave: () async => _go(_Beat.file),
        ),
      _Beat.file => CreateSaveBar(
          label: _createdItemId == null ? 'Add item' : 'Finish uploading',
          busy: _busy,
          enabled: _canSave,
          progress: _busy ? uploads.overallProgress : null,
          note: uploads.isEmpty
              ? 'An item needs at least one photo.'
              : (_busy
                  ? '${uploads.completedCount} of ${uploads.length} uploaded'
                  : null),
          onSave: _save,
        ),
    };
  }

  Widget _buildPick(BuildContext context) {
    final colors = context.kc;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s4,
            Space.s2,
            Space.s4,
            Space.s3,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Photos first. Filing comes last.',
                  style:
                      context.kt.caption.copyWith(color: colors.textTertiary),
                ),
              ),
              ListenableBuilder(
                listenable: _uploads,
                builder: (context, _) => Text(
                  '${_uploads.length}/${MediaUploadController.maxPhotos}',
                  style: context.kt.count.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: PickGrid(controller: _uploads, enabled: !_busy)),
      ],
    );
  }

  Widget _buildFile(BuildContext context) {
    final colors = context.kc;
    final collectionId = _collectionId;

    return ListView(
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
          onAdd: () => unawaited(_pickMore()),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      KTextField(
                        controller: _draft.description,
                        label: 'Description',
                        hint: 'Condition is honest — some shelf wear, no '
                            'cracks.',
                        maxLines: 5,
                        minLines: 2,
                        maxLength: 1000,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: Space.s4),
                      ItemMetadataFields(
                        draft: _draft,
                        enabled: !_busy,
                        suggestedTags: _suggestedTags,
                        onChanged: () => setState(() {}),
                      ),
                    ],
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
          'Photos are slimmed down on your phone before they upload, so '
          'saving stays quick even on cellular.',
          style: context.kt.caption.copyWith(color: colors.textTertiary),
        ),
      ],
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
