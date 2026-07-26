import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../create/media/photo_source_sheet.dart';
import '../../create/media/upload_controller.dart';
import '../../create/media/upload_journal.dart';
import '../../create/widgets/photo_tray.dart';

/// Adds photos to an item that already exists.
///
/// Uses the same queue, the same journal and the same ordering rules as the
/// create form — the only difference is that new photos are *appended*, so the
/// cover the owner already chose is left alone.
abstract final class AddPhotosSheet {
  /// Opens the sheet. Resolves with how many photos actually landed.
  static Future<int> show(
    BuildContext context, {
    required String itemId,
    required int existingCount,
  }) async =>
      await KSheet.show<int>(
        context: context,
        title: 'Add photos',
        maxHeightFraction: 0.75,
        isDismissible: false,
        builder: (sheetContext) =>
            _AddPhotosBody(itemId: itemId, existingCount: existingCount),
      ) ??
      0;
}

class _AddPhotosBody extends ConsumerStatefulWidget {
  const _AddPhotosBody({required this.itemId, required this.existingCount});

  final String itemId;
  final int existingCount;

  @override
  ConsumerState<_AddPhotosBody> createState() => _AddPhotosBodyState();
}

class _AddPhotosBodyState extends ConsumerState<_AddPhotosBody> {
  late final MediaUploadController _uploads = MediaUploadController(
    ref.read(klectApiProvider),
    ref.read(uploadJournalProvider),
  );

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_pick());
    });
  }

  @override
  void dispose() {
    _uploads.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await PhotoSourceSheet.pick(
      context,
      limit: _uploads.remainingSlots,
    );
    if (files.isEmpty || !mounted) return;
    await _uploads.addFiles(files);
  }

  Future<void> _save() async {
    if (_uploads.isEmpty) return;
    setState(() => _busy = true);

    final api = ref.read(klectApiProvider);
    final journal = ref.read(uploadJournalProvider);
    await journal.begin(itemId: widget.itemId, userId: api.requireUserId);

    final outcome = await _uploads.uploadAll(
      itemId: widget.itemId,
      positionOffset: widget.existingCount,
    );
    if (!mounted) return;

    if (outcome.isComplete) {
      Navigator.of(context).pop(outcome.uploaded);
      return;
    }
    setState(() => _busy = false);
    KToast.error(
      context,
      outcome.cancelled
          ? 'Stopped. ${outcome.uploaded} of ${_uploads.length} uploaded.'
          : '${outcome.failed} photo(s) failed — tap one to retry.',
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _uploads,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PhotoTray(
              controller: _uploads,
              enabled: !_busy,
              onAdd: () => unawaited(_pick()),
            ),
            const SizedBox(height: Space.s5),
            Row(
              children: <Widget>[
                Expanded(
                  child: KButton(
                    label: 'Cancel',
                    variant: KButtonVariant.secondary,
                    expand: true,
                    onPressed: _busy
                        ? null
                        : () async {
                            await _uploads.discard(itemId: widget.itemId);
                            if (context.mounted) {
                              Navigator.of(context).pop(0);
                            }
                          },
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: KButton(
                    label: 'Add ${_uploads.length} photo'
                        '${_uploads.length == 1 ? '' : 's'}',
                    expand: true,
                    busy: _busy,
                    onPressed:
                        _uploads.isEmpty || _busy || _uploads.isBusy ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
