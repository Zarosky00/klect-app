import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../media/photo_source_sheet.dart';
import '../media/upload_controller.dart';

/// The cover picker for a collection or a subcollection.
///
/// Those two levels have no `item_media` rows of their own, so their cover is a
/// single object in the `media` bucket — prepared through exactly the same
/// downscale + blurhash pipeline as an item photo.
class CoverField extends ConsumerStatefulWidget {
  /// Creates a cover picker.
  const CoverField({
    required this.folder,
    required this.onPicked,
    super.key,
    this.coverPath,
    this.coverBlurhash,
    this.label = 'Cover',
    this.helper,
    this.enabled = true,
  });

  /// Second path segment for the upload, e.g. the collection id. The user id
  /// is prepended by [KlectApi.upload].
  final String folder;

  /// Fired with the uploaded cover, or null when the cover is removed.
  final ValueChanged<UploadedCover?> onPicked;

  /// Current `cover_path`, if the entity already has one.
  final String? coverPath;

  /// Current `cover_blurhash`.
  final String? coverBlurhash;

  /// Field label.
  final String label;

  /// Optional helper line under the field.
  final String? helper;

  /// Disables interaction while a save is in flight.
  final bool enabled;

  @override
  ConsumerState<CoverField> createState() => _CoverFieldState();
}

class _CoverFieldState extends ConsumerState<CoverField> {
  bool _busy = false;
  String? _error;
  UploadedCover? _uploaded;
  bool _removed = false;

  String? get _effectivePath =>
      _removed ? null : (_uploaded?.storagePath ?? widget.coverPath);

  String? get _effectiveBlurhash =>
      _removed ? null : (_uploaded?.blurhash ?? widget.coverBlurhash);

  Future<void> _pick() async {
    final files = await PhotoSourceSheet.pick(context, limit: 1);
    if (files.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cover = await CoverUploader.upload(
        ref.read(klectApiProvider),
        file: files.first,
        folder: widget.folder,
      );
      if (!mounted) return;
      setState(() {
        _uploaded = cover;
        _removed = false;
      });
      widget.onPicked(cover);
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'That photo could not be prepared.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove() {
    setState(() {
      _removed = true;
      _uploaded = null;
    });
    widget.onPicked(null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final path = _effectivePath;
    final url = ref.watch(klectApiProvider).publicUrl(path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          widget.label,
          style: context.kt.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: Space.s20,
              child: KPressable(
                onTap: widget.enabled && !_busy ? _pick : null,
                enabled: widget.enabled && !_busy,
                enforceMinTapTarget: false,
                semanticLabel: 'Choose a cover photo',
                child: Stack(
                  children: <Widget>[
                    AspectRatio(
                      aspectRatio: Aspect.cover,
                      child: url == null
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surface2,
                                borderRadius: BorderRadius.circular(Radii.md),
                                border: Border.all(
                                  color: colors.borderDefault,
                                  width: Strokes.thin,
                                ),
                              ),
                              child: Icon(
                                Icons.add_photo_alternate_rounded,
                                size: Space.s6,
                                color: colors.textTertiary,
                              ),
                            )
                          : KBlurhashImage(
                              url: url,
                              blurhash: _effectiveBlurhash,
                              aspectRatio: Aspect.cover,
                              semanticLabel: 'Current cover',
                            ),
                    ),
                    if (_busy)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceScrim,
                            borderRadius: BorderRadius.circular(Radii.md),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: Space.s6,
                              height: Space.s6,
                              child: CircularProgressIndicator(
                                strokeWidth: Strokes.thick,
                                color: colors.accentDefault,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  KButton(
                    label: url == null ? 'Choose photo' : 'Replace',
                    icon: Icons.image_rounded,
                    size: KButtonSize.small,
                    variant: KButtonVariant.secondary,
                    busy: _busy,
                    onPressed: widget.enabled && !_busy ? _pick : null,
                  ),
                  if (url != null) ...<Widget>[
                    const SizedBox(height: Space.s2),
                    KButton(
                      label: 'Remove',
                      size: KButtonSize.small,
                      variant: KButtonVariant.ghost,
                      onPressed: widget.enabled && !_busy ? _remove : null,
                    ),
                  ],
                  if (widget.helper != null) ...<Widget>[
                    const SizedBox(height: Space.s2),
                    Text(
                      widget.helper!,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: Space.s2),
          KInlineError(message: _error!),
        ],
      ],
    );
  }
}
