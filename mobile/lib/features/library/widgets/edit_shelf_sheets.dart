import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../create/media/upload_controller.dart';
import '../../create/widgets/cover_field.dart';
import '../../create/widgets/visibility_field.dart';
import '../library_actions.dart';

/// Edits a collection in place: name, description, visibility, cover, pin.
abstract final class EditCollectionSheet {
  /// Opens the sheet. Resolves true when something was saved.
  static Future<bool> show(
    BuildContext context, {
    required CollectionModel collection,
  }) async =>
      await KSheet.show<bool>(
        context: context,
        title: 'Edit shelf',
        maxHeightFraction: 0.92,
        builder: (sheetContext) => _EditCollectionBody(collection: collection),
      ) ??
      false;
}

class _EditCollectionBody extends ConsumerStatefulWidget {
  const _EditCollectionBody({required this.collection});

  final CollectionModel collection;

  @override
  ConsumerState<_EditCollectionBody> createState() =>
      _EditCollectionBodyState();
}

class _EditCollectionBodyState extends ConsumerState<_EditCollectionBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.collection.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.collection.description ?? '');

  late EntityVisibility _visibility =
      widget.collection.visibility ?? EntityVisibility.public;
  late bool _pinned = widget.collection.isPinned;

  PendingCover? _cover;

  /// The cover blob, once it has actually landed. Kept so a save that fails
  /// *after* the upload does not upload the same bytes twice on retry.
  UploadedCover? _uploadedCover;
  bool _coverRemoved = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A shelf needs a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Deferred from pick time on purpose: uploading only inside the save
      // path means a cancelled sheet never orphans a blob in Storage.
      final cover = _cover;
      if (cover != null) {
        _uploadedCover ??= await cover.upload(ref.read(klectApiProvider));
      }
      await ref.read(libraryActionsProvider).editCollection(
            widget.collection.id,
            name: name,
            description: _description.text,
            visibility: _visibility,
            coverPath: cover == null ? null : _uploadedCover?.storagePath,
            coverBlurhash: cover == null ? null : _uploadedCover?.blurhash,
            clearCover: _coverRemoved && cover == null,
            isPinned: _pinned,
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
  Widget build(BuildContext context) => _SheetForm(
        busy: _busy,
        error: _error,
        saveLabel: 'Save shelf',
        onSave: _save,
        children: <Widget>[
          KTextField(
            controller: _name,
            label: 'Name',
            hint: 'Anime',
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            enabled: !_busy,
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: _description,
            label: 'Description',
            hint: 'What lives on this shelf?',
            maxLines: 4,
            minLines: 2,
            maxLength: 400,
            enabled: !_busy,
          ),
          const SizedBox(height: Space.s5),
          CoverField(
            folder: widget.collection.id,
            coverPath: widget.collection.coverPath,
            coverBlurhash: widget.collection.coverBlurhash,
            enabled: !_busy,
            helper: 'Shown wherever this shelf appears.',
            onPicked: (cover) => setState(() {
              _cover = cover;
              _uploadedCover = null;
              _coverRemoved = cover == null;
            }),
          ),
          const SizedBox(height: Space.s5),
          VisibilityField(
            value: _visibility,
            enabled: !_busy,
            onChanged: (value) => setState(
              () => _visibility = value ?? EntityVisibility.public,
            ),
          ),
          const SizedBox(height: Space.s4),
          _SwitchRow(
            label: 'Pin to the top of my profile',
            value: _pinned,
            enabled: !_busy,
            onChanged: (value) => setState(() => _pinned = value),
          ),
        ],
      );
}

/// Edits a subcollection: name, description, inherited-or-explicit visibility,
/// cover.
abstract final class EditSubcollectionSheet {
  /// Opens the sheet. Resolves true when something was saved.
  static Future<bool> show(
    BuildContext context, {
    required SubcollectionModel subcollection,
    String? parentName,
  }) async =>
      await KSheet.show<bool>(
        context: context,
        title: 'Edit group',
        maxHeightFraction: 0.92,
        builder: (sheetContext) => _EditSubcollectionBody(
          subcollection: subcollection,
          parentName: parentName,
        ),
      ) ??
      false;
}

class _EditSubcollectionBody extends ConsumerStatefulWidget {
  const _EditSubcollectionBody({
    required this.subcollection,
    required this.parentName,
  });

  final SubcollectionModel subcollection;
  final String? parentName;

  @override
  ConsumerState<_EditSubcollectionBody> createState() =>
      _EditSubcollectionBodyState();
}

class _EditSubcollectionBodyState
    extends ConsumerState<_EditSubcollectionBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.subcollection.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.subcollection.description ?? '');

  late EntityVisibility? _visibility = widget.subcollection.visibility;
  PendingCover? _cover;

  /// The cover blob, once it has actually landed. Kept so a save that fails
  /// *after* the upload does not upload the same bytes twice on retry.
  UploadedCover? _uploadedCover;
  bool _coverRemoved = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A group needs a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Deferred from pick time on purpose: uploading only inside the save
      // path means a cancelled sheet never orphans a blob in Storage.
      final cover = _cover;
      if (cover != null) {
        _uploadedCover ??= await cover.upload(ref.read(klectApiProvider));
      }
      await ref.read(libraryActionsProvider).editSubcollection(
            widget.subcollection.id,
            name: name,
            description: _description.text,
            visibility: _visibility,
            clearVisibility: _visibility == null,
            coverPath: cover == null ? null : _uploadedCover?.storagePath,
            coverBlurhash: cover == null ? null : _uploadedCover?.blurhash,
            clearCover: _coverRemoved && cover == null,
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
  Widget build(BuildContext context) => _SheetForm(
        busy: _busy,
        error: _error,
        saveLabel: 'Save group',
        onSave: _save,
        children: <Widget>[
          KTextField(
            controller: _name,
            label: 'Name',
            hint: 'JJK',
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            enabled: !_busy,
          ),
          const SizedBox(height: Space.s4),
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
            folder: widget.subcollection.id,
            coverPath: widget.subcollection.coverPath,
            coverBlurhash: widget.subcollection.coverBlurhash,
            enabled: !_busy,
            onPicked: (cover) => setState(() {
              _cover = cover;
              _uploadedCover = null;
              _coverRemoved = cover == null;
            }),
          ),
          const SizedBox(height: Space.s5),
          VisibilityField(
            value: _visibility,
            allowInherit: true,
            inheritLabel: widget.parentName == null
                ? 'Same as the shelf'
                : 'Same as ${widget.parentName}',
            enabled: !_busy,
            onChanged: (value) => setState(() => _visibility = value),
          ),
        ],
      );
}

/// Shared chrome for the edit sheets: scrollable body, keyboard inset, error
/// line, cancel/save row.
class _SheetForm extends StatelessWidget {
  const _SheetForm({
    required this.children,
    required this.busy,
    required this.error,
    required this.saveLabel,
    required this.onSave,
  });

  final List<Widget> children;
  final bool busy;
  final String? error;
  final String saveLabel;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: Space.s3),
              KInlineError(message: error!),
            ],
            const SizedBox(height: Space.s5),
            Row(
              children: <Widget>[
                Expanded(
                  child: KButton(
                    label: 'Cancel',
                    variant: KButtonVariant.secondary,
                    expand: true,
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: KButton(
                    label: saveLabel,
                    expand: true,
                    busy: busy,
                    onPressed: busy ? null : onSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(child: Text(label, style: context.kt.body)),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      );
}
