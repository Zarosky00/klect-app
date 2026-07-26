import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../media/image_pipeline.dart';
import '../media/upload_controller.dart';
import 'crop_frame.dart';

/// FRAME — the second beat of the create flow.
///
/// One photo at a time: pinch/drag crop with preset chips driven by the grid
/// tokens, quarter rotation, and a live "this is your card on Surf" preview.
/// Edits are held locally while the user works and committed to the
/// [MediaUploadController] (which re-runs the single-decode pipeline) when the
/// photo is switched or the beat is left — see [FrameBeatState.commitAll].
class FrameBeat extends StatefulWidget {
  /// Creates the beat.
  const FrameBeat({required this.controller, super.key});

  /// The draft's upload engine.
  final MediaUploadController controller;

  @override
  State<FrameBeat> createState() => FrameBeatState();
}

/// Public so the owning flow can [commitAll] when the user moves on.
class FrameBeatState extends State<FrameBeat> {
  final Map<String, _FrameEdit> _edits = <String, _FrameEdit>{};
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  final Map<String, (int, int)> _dims = <String, (int, int)>{};
  final Set<String> _loading = <String>{};

  String? _currentId;
  bool _showPreview = true;

  /// Pushes every local edit into the controller so the upload pipeline
  /// re-prepares exactly what the user framed. Fire-and-forget: the save
  /// button downstream is disabled while the controller is busy, so a save
  /// can never race a re-prepare.
  void commitAll() {
    for (final entry in _edits.entries) {
      unawaited(
        widget.controller.applyEdit(
          entry.key,
          cropRect: entry.value.crop,
          quarterTurns: entry.value.turns,
        ),
      );
    }
  }

  void _commit(String taskId) {
    final edit = _edits[taskId];
    if (edit == null) return;
    unawaited(
      widget.controller.applyEdit(
        taskId,
        cropRect: edit.crop,
        quarterTurns: edit.turns,
      ),
    );
  }

  void _ensureLoaded(UploadTask task) {
    if (_bytes.containsKey(task.id) || _loading.contains(task.id)) return;
    _loading.add(task.id);
    unawaited(() async {
      try {
        final raw = await task.source.readAsBytes();
        if (!mounted) return;
        setState(() => _bytes[task.id] = raw);
      } catch (_) {
        // The tray shows the pipeline's own failure state; nothing to add.
      } finally {
        _loading.remove(task.id);
      }
    }());
  }

  _FrameEdit _editFor(UploadTask task) => _edits.putIfAbsent(
        task.id,
        () => _FrameEdit(
          crop: task.cropRect,
          turns: task.quarterTurns,
          preset: _inferPreset(task.cropRect),
        ),
      );

  static CropPreset _inferPreset(Rect? crop) {
    if (crop == null || crop.height <= 0) return CropPreset.original;
    final ratio = crop.width / crop.height;
    for (final preset in CropPreset.values) {
      final aspect = preset.aspect;
      if (aspect != null && (ratio - aspect).abs() / aspect < 0.01) {
        return preset;
      }
    }
    return CropPreset.original;
  }

  void _select(String taskId) {
    if (taskId == _currentId) return;
    final previous = _currentId;
    if (previous != null) _commit(previous);
    setState(() => _currentId = taskId);
  }

  void _applyPreset(UploadTask task, CropPreset preset) {
    final dims = _turnedDims(task);
    if (dims == null) return;
    final edit = _editFor(task);
    setState(() {
      _edits[task.id] = edit.copyWith(
        preset: preset,
        crop: preset.aspect == null
            ? null
            : maxCenteredCrop(dims.$1, dims.$2, preset.aspect!),
        clearCrop: preset.aspect == null,
      );
    });
  }

  void _rotate(UploadTask task) {
    final base = _dims[task.id];
    if (base == null) return;
    final edit = _editFor(task);
    final oldTurnedHeight =
        (edit.turns.isOdd ? base.$1 : base.$2).toDouble();
    final crop = edit.crop == null
        ? null
        : ImagePipeline.rotateCropRect(edit.crop!, height: oldTurnedHeight);
    // Tall becomes wide (and back) when the frame turns with the photo.
    final preset = switch (edit.preset) {
      CropPreset.tall => CropPreset.wide,
      CropPreset.wide => CropPreset.tall,
      final other => other,
    };
    setState(() {
      _edits[task.id] = _FrameEdit(
        crop: crop,
        turns: (edit.turns + 1) % 4,
        preset: preset,
      );
    });
  }

  /// Turned-frame dimensions for the current edit, or null before the first
  /// prepare has reported the source size.
  (double, double)? _turnedDims(UploadTask task) {
    final base = _dims[task.id];
    if (base == null) return null;
    final turns = _editFor(task).turns;
    return turns.isOdd
        ? (base.$2.toDouble(), base.$1.toDouble())
        : (base.$1.toDouble(), base.$2.toDouble());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final colors = context.kc;
    final tasks = widget.controller.tasks;
    if (tasks.isEmpty) {
      return const KEmptyState(
        title: 'Nothing to frame',
        message: 'Go back a step and pick a photo or two first.',
        icon: Icons.crop_rounded,
      );
    }

    var current = _currentId;
    if (current == null || !tasks.any((task) => task.id == current)) {
      current = tasks.first.id;
      _currentId = current;
    }
    final task = tasks.firstWhere((candidate) => candidate.id == current);
    _ensureLoaded(task);

    final prepared = task.prepared;
    if (prepared != null) {
      _dims[task.id] = (prepared.sourceWidth, prepared.sourceHeight);
    }
    final base = _dims[task.id];
    final bytes = _bytes[task.id];
    final edit = _editFor(task);
    final ready = bytes != null && base != null;

    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s2,
            ),
            child: ready
                ? Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CropEditor(
                          bytes: bytes,
                          baseWidth: base.$1,
                          baseHeight: base.$2,
                          quarterTurns: edit.turns,
                          cropRect: edit.crop,
                          lockedAspect: edit.preset.aspect,
                          onCropChanged: (rect) => setState(
                            () => _edits[task.id] = edit.copyWith(crop: rect),
                          ),
                        ),
                      ),
                      if (_showPreview)
                        Positioned(
                          right: Space.s2,
                          bottom: Space.s2,
                          child: _SurfCardPreview(
                            bytes: bytes,
                            baseWidth: base.$1,
                            baseHeight: base.$2,
                            edit: edit,
                            onTap: () =>
                                setState(() => _showPreview = false),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: SizedBox(
                      width: Space.s8,
                      height: Space.s8,
                      child: CircularProgressIndicator(
                        strokeWidth: Strokes.thick,
                        color: colors.accentDefault,
                      ),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final preset in CropPreset.values) ...<Widget>[
                        KChip(
                          label: preset.label,
                          selected: edit.preset == preset,
                          onTap: ready
                              ? () => _applyPreset(task, preset)
                              : null,
                        ),
                        const SizedBox(width: Space.s2),
                      ],
                    ],
                  ),
                ),
              ),
              KIconButton(
                icon: Icons.rotate_90_degrees_cw_rounded,
                semanticLabel: 'Rotate a quarter turn',
                onPressed: ready ? () => _rotate(task) : null,
              ),
              KIconButton(
                icon: _showPreview
                    ? Icons.preview_rounded
                    : Icons.preview_outlined,
                semanticLabel: _showPreview
                    ? 'Hide the Surf card preview'
                    : 'Show the Surf card preview',
                onPressed: () =>
                    setState(() => _showPreview = !_showPreview),
              ),
            ],
          ),
        ),
        if (tasks.length > 1)
          SizedBox(
            height: Space.s16,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              scrollDirection: Axis.horizontal,
              itemCount: tasks.length,
              separatorBuilder: (context, _) =>
                  const SizedBox(width: Space.s2),
              itemBuilder: (context, index) {
                final thumbTask = tasks[index];
                return _FrameThumb(
                  task: thumbTask,
                  bytes: _bytes[thumbTask.id],
                  dims: _dims[thumbTask.id],
                  edit: _edits[thumbTask.id],
                  selected: thumbTask.id == current,
                  onTap: () => _select(thumbTask.id),
                );
              },
            ),
          ),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}

/// One photo's local FRAME state, uncommitted.
@immutable
class _FrameEdit {
  const _FrameEdit({
    required this.crop,
    required this.turns,
    required this.preset,
  });

  final Rect? crop;
  final int turns;
  final CropPreset preset;

  _FrameEdit copyWith({Rect? crop, CropPreset? preset, bool clearCrop = false}) =>
      _FrameEdit(
        crop: clearCrop ? null : (crop ?? this.crop),
        turns: turns,
        preset: preset ?? this.preset,
      );
}

/// The live "this is your card on Surf" tile.
///
/// Proportioned exactly as the masonry will draw it — the aspect is the
/// crop's, clamped to the grid's own [Aspect.gridMin]/[Aspect.gridMax]
/// bounds, so what you frame is what Surf shows.
class _SurfCardPreview extends StatelessWidget {
  const _SurfCardPreview({
    required this.bytes,
    required this.baseWidth,
    required this.baseHeight,
    required this.edit,
    required this.onTap,
  });

  final Uint8List bytes;
  final int baseWidth;
  final int baseHeight;
  final _FrameEdit edit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tw = (edit.turns.isOdd ? baseHeight : baseWidth).toDouble();
    final th = (edit.turns.isOdd ? baseWidth : baseHeight).toDouble();
    final crop = edit.crop;
    final raw = crop == null
        ? (th <= 0 ? Aspect.cover : tw / th)
        : (crop.height <= 0 ? Aspect.cover : crop.width / crop.height);
    final aspect = raw.clamp(Aspect.gridMin, Aspect.gridMax).toDouble();

    return KPressable(
      onTap: onTap,
      semanticLabel: 'Hide the Surf card preview',
      enforceMinTapTarget: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s2,
              vertical: Space.sPx,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceScrim,
              borderRadius: BorderRadius.circular(Radii.full),
            ),
            child: Text(
              'Your card on Surf',
              style: context.kt.micro.copyWith(color: colors.textOnAccent),
            ),
          ),
          const SizedBox(height: Space.s1),
          Container(
            width: Space.s24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: colors.borderStrong,
                width: Strokes.thin,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Elevation.mid.color,
                  blurRadius: Elevation.mid.blur,
                  spreadRadius: Elevation.mid.spread,
                  offset: Offset(0, Elevation.mid.y),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: AspectRatio(
                aspectRatio: aspect,
                child: CroppedPhoto(
                  bytes: bytes,
                  baseWidth: baseWidth,
                  baseHeight: baseHeight,
                  quarterTurns: edit.turns,
                  cropRect: edit.crop,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameThumb extends StatelessWidget {
  const _FrameThumb({
    required this.task,
    required this.bytes,
    required this.dims,
    required this.edit,
    required this.selected,
    required this.onTap,
  });

  final UploadTask task;
  final Uint8List? bytes;
  final (int, int)? dims;
  final _FrameEdit? edit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final localBytes = bytes;
    final localDims = dims;

    return KPressable(
      onTap: onTap,
      semanticLabel: 'Frame ${task.displayName}',
      enforceMinTapTarget: false,
      child: AnimatedContainer(
        duration: KMotion.duration(context, KDurations.fast),
        width: Space.s14,
        height: Space.s14,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.skeletonBase,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: selected ? colors.accentDefault : colors.borderSubtle,
            width: selected ? Strokes.thick : Strokes.thin,
          ),
        ),
        child: localBytes != null && localDims != null
            ? CroppedPhoto(
                bytes: localBytes,
                baseWidth: localDims.$1,
                baseHeight: localDims.$2,
                quarterTurns: edit?.turns ?? task.quarterTurns,
                cropRect: edit?.crop ?? task.cropRect,
              )
            : task.prepared != null
                ? Image.memory(
                    task.prepared!.bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: math.min(
                      kFrameDecodeWidth,
                      task.prepared!.width,
                    ),
                  )
                : const KShimmer(
                    child: KSkeleton(width: Space.s14, height: Space.s14),
                  ),
      ),
    );
  }
}
