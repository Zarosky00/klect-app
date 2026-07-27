import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../create/frame/crop_frame.dart';
import '../../create/media/image_pipeline.dart';
import '../../create/media/photo_source_sheet.dart';

/// Picks, square-crops and rotates a group display photo.
abstract final class GroupAvatarEditor {
  /// Opens the system picker followed by KLECT's existing crop surface.
  static Future<PreparedImage?> pick(BuildContext context) async {
    final files = await PhotoSourceSheet.pick(context, limit: 1);
    if (files.isEmpty || !context.mounted) return null;
    try {
      final bytes = await files.first.readAsBytes();
      final initial = await ImagePipeline.prepare(bytes);
      if (!context.mounted) return null;
      return Navigator.of(context).push<PreparedImage>(
        MaterialPageRoute<PreparedImage>(
          fullscreenDialog: true,
          builder: (_) => _SquareCropScreen(bytes: bytes, initial: initial),
        ),
      );
    } on ImagePreparationException catch (error) {
      if (context.mounted) KToast.error(context, error.message);
      return null;
    } on Object {
      if (context.mounted) {
        KToast.error(context, 'Could not prepare that group photo.');
      }
      return null;
    }
  }
}

class _SquareCropScreen extends StatefulWidget {
  const _SquareCropScreen({required this.bytes, required this.initial});

  final Uint8List bytes;
  final PreparedImage initial;

  @override
  State<_SquareCropScreen> createState() => _SquareCropScreenState();
}

class _SquareCropScreenState extends State<_SquareCropScreen> {
  Rect? _cropRect;
  int _quarterTurns = 0;
  bool _saving = false;

  void _rotate() {
    final currentHeight =
        (_quarterTurns.isOdd
                ? widget.initial.sourceWidth
                : widget.initial.sourceHeight)
            .toDouble();
    setState(() {
      if (_cropRect != null) {
        _cropRect = ImagePipeline.rotateCropRect(
          _cropRect!,
          height: currentHeight,
        );
      }
      _quarterTurns = (_quarterTurns + 1) % 4;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prepared = await ImagePipeline.prepare(
        widget.bytes,
        cropRect: _cropRect,
        quarterTurns: _quarterTurns,
      );
      if (mounted) Navigator.of(context).pop(prepared);
    } on ImagePreparationException catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        KToast.error(context, error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.kc.surface1,
    body: SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s2,
            ),
            child: Row(
              children: <Widget>[
                KButton(
                  label: 'Cancel',
                  variant: KButtonVariant.ghost,
                  size: KButtonSize.small,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Text('Group photo', style: context.kt.title3),
                const Spacer(),
                KButton(
                  label: 'Done',
                  size: KButtonSize.small,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
          Divider(height: Strokes.hairline, color: context.kc.borderSubtle),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Space.s4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.lg),
                child: CropEditor(
                  bytes: widget.bytes,
                  baseWidth: widget.initial.sourceWidth,
                  baseHeight: widget.initial.sourceHeight,
                  quarterTurns: _quarterTurns,
                  cropRect: _cropRect,
                  lockedAspect: 1,
                  onCropChanged: (rect) => setState(() => _cropRect = rect),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(Space.s3),
            decoration: BoxDecoration(
              color: context.kc.surface1,
              border: Border(top: BorderSide(color: context.kc.borderSubtle)),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text('Pinch or drag to frame a square group photo.'),
                ),
                KIconButton(
                  icon: Icons.rotate_90_degrees_cw_rounded,
                  semanticLabel: 'Rotate photo',
                  onPressed: _saving ? null : _rotate,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
