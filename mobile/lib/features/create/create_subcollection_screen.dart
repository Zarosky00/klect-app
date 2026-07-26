import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../library/library_actions.dart';
import '../library/library_providers.dart';
import 'create_providers.dart';
import 'media/upload_controller.dart';
import 'widgets/cover_field.dart';
import 'widgets/destination_picker.dart';
import 'widgets/save_bar.dart';
import 'widgets/visibility_field.dart';

/// Creates a group inside a shelf — the middle level of the hierarchy.
class CreateSubcollectionScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreateSubcollectionScreen({
    this.collectionId,
    this.popOnCreate = false,
    super.key,
  });

  /// Route parameter — pre-selects the shelf when the flow was started from
  /// inside one.
  final String? collectionId;

  /// When true the screen pops with the created [SubcollectionModel] instead
  /// of navigating to the new group, so the flow that needed it resumes.
  final bool popOnCreate;

  @override
  ConsumerState<CreateSubcollectionScreen> createState() =>
      _CreateSubcollectionScreenState();
}

class _CreateSubcollectionScreenState
    extends ConsumerState<CreateSubcollectionScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  String? _collectionId;
  String? _collectionName;
  EntityVisibility? _visibility;
  PendingCover? _cover;

  /// The cover blob, once it has actually landed. Kept so a save that fails
  /// *after* the upload does not upload the same bytes twice on retry.
  UploadedCover? _uploadedCover;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _collectionId =
        widget.collectionId ?? ref.read(createDefaultsProvider).collectionId;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _name.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _cover != null;

  Future<void> _confirmLeave(bool didPop, Object? result) async {
    if (didPop || !_isDirty || _busy) return;
    final discard = await KConfirmDialog.show(
      context,
      title: 'Discard this group?',
      message: 'Nothing has been saved yet.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!discard || !mounted) return;
    if (context.canPop()) context.pop();
  }

  void _back() {
    if (_isDirty) {
      unawaited(_confirmLeave(false, null));
    } else if (context.canPop()) {
      context.pop();
    }
  }

  Future<void> _save() async {
    final collectionId = _collectionId;
    final name = _name.text.trim();
    if (collectionId == null) {
      setState(() => _error = 'Choose which shelf this group belongs to.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(klectApiProvider);
      // Deferred from pick time on purpose: uploading only inside the save
      // path means an abandoned form never orphans a blob in Storage.
      final cover = _cover;
      if (cover != null) {
        _uploadedCover ??= await cover.upload(api);
      }
      final existing = await api.fetchSubcollections(collectionId);
      final created = await api.createSubcollection(
        collectionId: collectionId,
        name: name,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        coverPath: cover == null ? null : _uploadedCover?.storagePath,
        coverBlurhash: cover == null ? null : _uploadedCover?.blurhash,
        visibility: _visibility,
      );
      await ref.read(libraryActionsProvider).appendPosition(
            table: 'subcollections',
            id: created.id,
            position: existing.length,
          );
      await ref.read(createDefaultsProvider).remember(
            collectionId: collectionId,
            subcollectionId: created.id,
          );
      if (!mounted) return;

      ref.refreshLibrary(
        collectionId: collectionId,
        subcollectionId: created.id,
      );
      KToast.success(context, '${created.name} added.');
      if (widget.popOnCreate && context.canPop()) {
        context.pop(created);
      } else {
        context.pushReplacement('/s/${created.id}');
      }
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;

    return KScaffold(
      canPop: !_isDirty,
      onPopInvoked: _confirmLeave,
      appBar: KFixedAppBar(
        title: 'New group',
        showBack: true,
        onBack: _back,
      ),
      bottomBar: CreateSaveBar(
        label: 'Create group',
        busy: _busy,
        enabled: _collectionId != null && _name.text.trim().isNotEmpty,
        onSave: _save,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s4,
          Space.s8,
        ),
        children: <Widget>[
          Text('Group things together', style: context.kt.display3),
          const SizedBox(height: Space.s2),
          Text(
            'A group is a theme inside a shelf — "JJK" inside "Anime". Items '
            'always live in one.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.s6),
          CollectionChooser(
            selectedId: _collectionId,
            enabled: !_busy,
            onSelected: (shelf) => setState(() {
              _collectionId = shelf.id;
              _collectionName = shelf.name;
            }),
          ),
          const SizedBox(height: Space.s5),
          KTextField(
            controller: _name,
            label: 'Name',
            hint: 'JJK',
            enabled: !_busy,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s5),
          KTextField(
            controller: _description,
            label: 'Description',
            hint: 'What ties this group together?',
            maxLines: 4,
            minLines: 2,
            maxLength: 400,
            enabled: !_busy,
          ),
          const SizedBox(height: Space.s5),
          CoverField(
            folder: 'covers',
            enabled: !_busy,
            helper: 'Optional — otherwise the first item stands in.',
            onPicked: (cover) => setState(() {
              _cover = cover;
              _uploadedCover = null;
            }),
          ),
          const SizedBox(height: Space.s5),
          VisibilityField(
            value: _visibility,
            allowInherit: true,
            inheritLabel: _collectionName == null
                ? 'Same as the shelf'
                : 'Same as $_collectionName',
            enabled: !_busy,
            onChanged: (value) => setState(() => _visibility = value),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: Space.s4),
            KInlineError(message: _error!),
          ],
        ],
      ),
    );
  }
}
