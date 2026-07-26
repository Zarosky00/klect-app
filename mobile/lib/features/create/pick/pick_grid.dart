import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../media/photo_source_sheet.dart';
import '../media/upload_controller.dart';

/// PICK — the full-bleed photo grid that opens the create flow.
///
/// A camera tile, a library tile, then everything picked so far with its
/// selection order badged on the tile. Preparation starts the moment a photo
/// lands (the controller decodes on a background isolate), so by the time the
/// user reaches FRAME the thumbs are already real. Tapping a picked tile
/// removes it — the standard picker gesture.
///
/// Both entry points share this widget: the Create tab and the flow's own
/// first beat, so the two can never drift apart.
class PickGrid extends StatelessWidget {
  /// Creates the grid over the draft's upload engine.
  const PickGrid({required this.controller, super.key, this.enabled = true});

  /// The draft's upload engine.
  final MediaUploadController controller;

  /// Disables interaction while something downstream is busy.
  final bool enabled;

  /// Grid columns — dense enough to feel like a gallery, big enough to judge
  /// a photo.
  static const int columns = 3;

  Future<void> _capture(BuildContext context, PhotoSource source) async {
    if (controller.remainingSlots <= 0) {
      KToast.show(
        context,
        'That is ${MediaUploadController.maxPhotos} photos — the ceiling for '
        'one item.',
      );
      return;
    }
    final files = await PhotoSourceSheet.capture(
      context,
      source,
      limit: controller.remainingSlots,
    );
    if (files.isEmpty) return;
    await controller.addFiles(files);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final tasks = controller.tasks;
          return GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Space.s05,
              crossAxisSpacing: Space.s05,
            ),
            itemCount: tasks.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _SourceTile(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  emphasised: true,
                  enabled: enabled && PhotoSourceSheet.cameraAvailable,
                  onTap: () =>
                      unawaited(_capture(context, PhotoSource.camera)),
                );
              }
              if (index == 1) {
                return _SourceTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Photos',
                  enabled: enabled,
                  onTap: () =>
                      unawaited(_capture(context, PhotoSource.library)),
                );
              }
              final task = tasks[index - 2];
              return _PickedTile(
                key: ValueKey<String>(task.id),
                task: task,
                order: index - 1,
                enabled: enabled,
                onRemove: () => unawaited(controller.remove(task.id)),
              );
            },
          );
        },
      );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel: label,
      enforceMinTapTarget: false,
      child: ColoredBox(
        color: emphasised ? colors.accentSubtle : colors.surface2,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: Space.s8,
              color: enabled
                  ? (emphasised ? colors.accentDefault : colors.textSecondary)
                  : colors.textDisabled,
            ),
            const SizedBox(height: Space.s2),
            Text(
              label,
              style: context.kt.label.copyWith(
                color: enabled ? colors.textPrimary : colors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decode budget for a pick tile — a third of a phone screen.
const int _pickDecodeWidth = 360;

class _PickedTile extends StatelessWidget {
  const _PickedTile({
    required this.task,
    required this.order,
    required this.enabled,
    required this.onRemove,
    super.key,
  });

  final UploadTask task;
  final int order;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final prepared = task.prepared;
    final failed = task.stage == UploadStage.failed;

    return KPressable(
      onTap: enabled ? onRemove : null,
      enabled: enabled,
      semanticLabel: 'Remove ${task.displayName}',
      enforceMinTapTarget: false,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (prepared != null)
            Image.memory(
              prepared.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: math.min(_pickDecodeWidth, prepared.width),
            )
          else
            const KShimmer(
              child: KSkeleton(
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              ),
            ),
          if (failed)
            ColoredBox(
              color: colors.surfaceScrim,
              child: Icon(
                Icons.broken_image_rounded,
                size: Space.s6,
                color: colors.semanticDanger,
              ),
            ),
          Positioned(
            top: Space.s1,
            right: Space.s1,
            child: Container(
              width: Space.s6,
              height: Space.s6,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentDefault,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.textOnAccent,
                  width: Strokes.thin,
                ),
              ),
              child: Text(
                '$order',
                style: context.kt.micro.copyWith(color: colors.textOnAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
