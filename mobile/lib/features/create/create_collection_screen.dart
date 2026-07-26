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
import 'widgets/save_bar.dart';
import 'widgets/template_picker.dart';
import 'widgets/visibility_field.dart';

/// Creates a shelf — the top level of the hierarchy.
class CreateCollectionScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreateCollectionScreen({super.key});

  @override
  ConsumerState<CreateCollectionScreen> createState() =>
      _CreateCollectionScreenState();
}

class _CreateCollectionScreenState
    extends ConsumerState<CreateCollectionScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  CollectionTemplate? _template;
  EntityVisibility _visibility = EntityVisibility.public;
  UploadedCover? _cover;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _name.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _template != null ||
      _cover != null;

  Future<void> _confirmLeave(bool didPop, Object? result) async {
    if (didPop || !_isDirty || _busy) return;
    final discard = await KConfirmDialog.show(
      context,
      title: 'Discard this shelf?',
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
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the shelf a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(klectApiProvider);
      final existing = await api.fetchCollections(api.requireUserId);
      final collection = await api.createCollection(
        name: name,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        templateId: _template?.id,
        coverPath: _cover?.storagePath,
        coverBlurhash: _cover?.blurhash,
        accentColor: _template?.accentColor,
        visibility: _visibility,
      );
      // New rows default to `position = 0`, which would stack every shelf on
      // top of the last one — stamp the real tail so drag-reorder means
      // something from the very first shelf.
      await ref.read(libraryActionsProvider).appendPosition(
            table: 'collections',
            id: collection.id,
            position: existing.length,
          );
      await ref
          .read(createDefaultsProvider)
          .remember(collectionId: collection.id);
      if (!mounted) return;

      ref.refreshLibrary(collectionId: collection.id);
      KToast.success(context, '${collection.name} is on the shelf.');
      context.pushReplacement('/c/${collection.id}');
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
    final templates = ref.watch(createTemplatesProvider);

    return KScaffold(
      canPop: !_isDirty,
      onPopInvoked: _confirmLeave,
      appBar: KFixedAppBar(
        title: 'New shelf',
        showBack: true,
        onBack: _back,
      ),
      bottomBar: CreateSaveBar(
        label: 'Create shelf',
        busy: _busy,
        enabled: _name.text.trim().isNotEmpty,
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
          Text('What do you collect?', style: context.kt.display3),
          const SizedBox(height: Space.s2),
          Text(
            'A shelf is the widest bucket. Groups live inside it, and the '
            'things themselves live inside those.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.s6),
          KTextField(
            controller: _name,
            label: 'Name',
            hint: 'Anime',
            autofocus: true,
            enabled: !_busy,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s5),
          templates.when(
            loading: () => const KShimmer(
              child: Wrap(
                spacing: Space.s2,
                runSpacing: Space.s2,
                children: <Widget>[
                  KSkeleton(width: Space.s20, height: Space.s8),
                  KSkeleton(width: Space.s24, height: Space.s8),
                  KSkeleton(width: Space.s16, height: Space.s8),
                ],
              ),
            ),
            error: (error, _) => KErrorState(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(createTemplatesProvider),
            ),
            data: (rows) => TemplatePicker(
              templates: rows,
              selectedId: _template?.id,
              enabled: !_busy,
              onSelected: (template) => setState(() {
                _template = template;
                if (template != null && _name.text.trim().isEmpty) {
                  _name.text = template.name;
                }
              }),
            ),
          ),
          const SizedBox(height: Space.s5),
          KTextField(
            controller: _description,
            label: 'Description',
            hint: 'Series, arcs and the moments that hit.',
            maxLines: 4,
            minLines: 2,
            maxLength: 400,
            enabled: !_busy,
          ),
          const SizedBox(height: Space.s5),
          CoverField(
            folder: 'covers',
            enabled: !_busy,
            helper: 'Optional — a shelf with no cover shows its accent.',
            onPicked: (cover) => setState(() => _cover = cover),
          ),
          const SizedBox(height: Space.s5),
          VisibilityField(
            value: _visibility,
            enabled: !_busy,
            onChanged: (value) => setState(
              () => _visibility = value ?? EntityVisibility.public,
            ),
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
