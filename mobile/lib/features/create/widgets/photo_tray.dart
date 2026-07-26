import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../media/upload_controller.dart';

/// The photo strip on the create-item form.
///
/// Reorderable — position 0 is the cover, which is what the database trigger
/// reads — with a per-file stage, a determinate progress bar, remove and retry.
class PhotoTray extends StatelessWidget {
  /// Creates a tray bound to [controller].
  const PhotoTray({
    required this.controller,
    required this.onAdd,
    super.key,
    this.enabled = true,
  });

  /// The upload engine for this draft.
  final MediaUploadController controller;

  /// Opens the camera/library sheet.
  final VoidCallback onAdd;

  /// Disabled once the draft has been committed.
  final bool enabled;

  /// Tile edge, and therefore the strip's height.
  static const double tileSize = Space.s24;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final colors = context.kc;
    final tasks = controller.tasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Photos',
                style: context.kt.label.copyWith(color: colors.textSecondary),
              ),
            ),
            Text(
              '${tasks.length}/${MediaUploadController.maxPhotos}',
              style: context.kt.count.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        if (tasks.isEmpty)
          _EmptyTray(onAdd: enabled ? onAdd : null)
        else
          SizedBox(
            height: tileSize + Space.s6,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: enabled,
              itemCount: tasks.length,
              onReorderItem: controller.reorder,
              proxyDecorator: (child, index, animation) => Material(
                type: MaterialType.transparency,
                child: child,
              ),
              footer: _AddTile(
                onTap:
                    enabled && controller.remainingSlots > 0 ? onAdd : null,
              ),
              itemBuilder: (context, index) {
                final task = tasks[index];
                return _PhotoTile(
                  key: ValueKey<String>(task.id),
                  task: task,
                  isCover: index == 0,
                  enabled: enabled,
                  onMakeCover: () => controller.makeCover(task.id),
                  onRemove: () => unawaited(controller.remove(task.id)),
                  onRetry: () => unawaited(controller.retry(task.id)),
                );
              },
            ),
          ),
        if (tasks.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.s2),
          Text(
            controller.hasFailures
                ? 'Tap a failed photo to try it again.'
                : 'Drag to reorder. The first photo becomes the cover.',
            style: context.kt.caption.copyWith(
              color: controller.hasFailures
                  ? colors.semanticDanger
                  : colors.textTertiary,
            ),
          ),
        ],
        if (controller.isBusy) ...<Widget>[
          const SizedBox(height: Space.s3),
          _QueueProgress(controller: controller),
        ],
      ],
    );
  }
}

class _QueueProgress extends StatelessWidget {
  const _QueueProgress({required this.controller});

  final MediaUploadController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${controller.completedCount} of ${controller.length} '
                'photos uploaded',
                style: context.kt.caption.copyWith(color: colors.textSecondary),
              ),
            ),
            KButton(
              label: 'Cancel',
              variant: KButtonVariant.ghost,
              size: KButtonSize.small,
              onPressed: controller.cancel,
            ),
          ],
        ),
        const SizedBox(height: Space.s15),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.full),
          child: LinearProgressIndicator(
            value: controller.overallProgress,
            minHeight: Space.s1,
            backgroundColor: colors.surface3,
            color: colors.accentDefault,
          ),
        ),
      ],
    );
  }
}

class _EmptyTray extends StatelessWidget {
  const _EmptyTray({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onAdd,
      enabled: onAdd != null,
      semanticLabel: 'Add photos',
      enforceMinTapTarget: false,
      child: Container(
        height: PhotoTray.tileSize,
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: colors.borderDefault, width: Strokes.thin),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.add_a_photo_rounded,
              size: Space.s5,
              color: colors.accentDefault,
            ),
            const SizedBox(width: Space.s2),
            Text(
              'Add photos',
              style: context.kt.bodyStrong.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.only(right: Space.s2, bottom: Space.s6),
      child: KPressable(
        onTap: onTap,
        enabled: onTap != null,
        semanticLabel: 'Add more photos',
        enforceMinTapTarget: false,
        child: Container(
          width: PhotoTray.tileSize,
          height: PhotoTray.tileSize,
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: colors.borderDefault, width: Strokes.thin),
          ),
          child: Icon(
            Icons.add_rounded,
            size: Space.s6,
            color: onTap == null ? colors.textDisabled : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Decode budget for a tray thumbnail — a 2048px payload never needs more.
const int _thumbnailDecodeWidth = 256;

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.task,
    required this.isCover,
    required this.enabled,
    required this.onMakeCover,
    required this.onRemove,
    required this.onRetry,
    super.key,
  });

  final UploadTask task;
  final bool isCover;
  final bool enabled;
  final VoidCallback onMakeCover;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final prepared = task.prepared;
    final failed = task.stage == UploadStage.failed;

    return Padding(
      padding: const EdgeInsets.only(right: Space.s2, bottom: Space.s6),
      child: SizedBox(
        width: PhotoTray.tileSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            KPressable(
              onTap: enabled ? (failed ? onRetry : onMakeCover) : null,
              enabled: enabled,
              enforceMinTapTarget: false,
              semanticLabel: failed
                  ? 'Retry ${task.displayName}'
                  : 'Make ${task.displayName} the cover',
              child: Stack(
                children: <Widget>[
                  Container(
                    width: PhotoTray.tileSize,
                    height: PhotoTray.tileSize,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: colors.skeletonBase,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(
                        color: failed
                            ? colors.semanticDanger
                            : (isCover
                                ? colors.accentDefault
                                : colors.borderSubtle),
                        width: isCover || failed
                            ? Strokes.thick
                            : Strokes.thin,
                      ),
                    ),
                    child: prepared == null
                        ? const KShimmer(
                            child: KSkeleton(
                              width: PhotoTray.tileSize,
                              height: PhotoTray.tileSize,
                            ),
                          )
                        : Image.memory(
                            prepared.bytes,
                            fit: BoxFit.cover,
                            width: PhotoTray.tileSize,
                            height: PhotoTray.tileSize,
                            cacheWidth: _thumbnailDecodeWidth,
                            gaplessPlayback: true,
                          ),
                  ),
                  if (task.stage.isActive)
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
                              value: task.stage == UploadStage.processing
                                  ? null
                                  : task.progress,
                              strokeWidth: Strokes.thick,
                              color: colors.accentDefault,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (failed)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceScrim,
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: Icon(
                          Icons.refresh_rounded,
                          size: Space.s6,
                          color: colors.semanticDanger,
                        ),
                      ),
                    ),
                  if (task.stage == UploadStage.done)
                    Positioned(
                      right: Space.s1,
                      bottom: Space.s1,
                      child: _Badge(
                        icon: Icons.check_rounded,
                        color: colors.semanticSuccess,
                      ),
                    ),
                  if (isCover && task.stage != UploadStage.done)
                    const Positioned(
                      left: Space.s1,
                      bottom: Space.s1,
                      child: _CoverBadge(),
                    ),
                  // A photo that already landed owns a real `item_media` row,
                  // which nothing in the client API can delete — so it is not
                  // offered as removable here.
                  if (enabled && task.stage != UploadStage.done)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: KIconButton(
                        icon: Icons.close_rounded,
                        semanticLabel: 'Remove ${task.displayName}',
                        size: Space.s4,
                        color: colors.textPrimary,
                        background: colors.surfaceScrim,
                        onPressed: onRemove,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.s1),
            Text(
              failed ? (task.error ?? 'Failed') : task.stage.label,
              style: context.kt.micro.copyWith(
                color: failed ? colors.semanticDanger : colors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Space.sPx),
        decoration: BoxDecoration(
          color: context.kc.bgBase,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: Space.s4, color: color),
      );
}

class _CoverBadge extends StatelessWidget {
  const _CoverBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return AnimatedContainer(
      duration: KMotion.duration(context, KDurations.fast),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s15,
        vertical: Space.sPx,
      ),
      decoration: BoxDecoration(
        color: colors.accentDefault,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Text(
        'COVER',
        style: context.kt.micro.copyWith(color: colors.textOnAccent),
      ),
    );
  }
}
