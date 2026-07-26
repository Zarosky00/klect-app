import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../surf/surf.dart';
import '../data/entity_preview_provider.dart';

/// A collection, shelf or thing rendered inline inside a Pulse card.
///
/// It carries the full gesture contract, so a shared collection in the stream
/// behaves exactly like a tile in the Surf grid: tap for the closeup, double
/// tap for fullscreen, long press for the peek.
class EntityAttachmentCard extends ConsumerWidget {
  /// Creates an attachment card.
  const EntityAttachmentCard({required this.entity, super.key});

  /// What is attached.
  final EntityRef entity;

  /// Height of the cover thumbnail.
  static const double thumb = Space.s20;

  IconData get _icon => switch (entity.type) {
        EntityType.collection => Icons.collections_bookmark_rounded,
        EntityType.subcollection => Icons.layers_rounded,
        EntityType.item => Icons.photo_library_rounded,
        EntityType.post => Icons.bolt_rounded,
        EntityType.comment => Icons.mode_comment_rounded,
      };

  String get _typeLabel => switch (entity.type) {
        EntityType.collection => 'Collection',
        EntityType.subcollection => 'Shelf',
        EntityType.item => 'Thing',
        EntityType.post => 'Post',
        EntityType.comment => 'Comment',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final async = ref.watch(entityPreviewProvider(entity));
    final preview = async.value;

    if (preview == null) {
      if (async.hasError) return const SizedBox.shrink();
      return const _AttachmentSkeleton();
    }

    final url = ref.watch(klectApiProvider).publicUrl(preview.coverPath);

    return KEntityGestureCard(
      entity: entity,
      title: preview.title,
      subtitle: _typeLabel,
      imageUrl: url,
      blurhash: preview.blurhash,
      aspectRatio: Aspect.cover,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: colors.borderSubtle,
            width: Strokes.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: thumb,
              height: thumb,
              child: KBlurhashImage(
                url: url,
                blurhash: preview.blurhash,
                semanticLabel: preview.title,
                borderRadius: BorderRadius.zero,
                memCacheWidth: (thumb *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s3,
                  vertical: Space.s3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(_icon, size: Space.s3, color: colors.textTertiary),
                        const SizedBox(width: Space.s1),
                        Text(
                          _typeLabel.toUpperCase(),
                          style:
                              text.micro.copyWith(color: colors.textTertiary),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      preview.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyStrong,
                    ),
                    if (preview.subtitle != null &&
                        preview.subtitle!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Space.s05),
                      Text(
                        preview.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            text.caption.copyWith(color: colors.textSecondary),
                      ),
                    ],
                    if (preview.childCount > 0) ...<Widget>[
                      const SizedBox(height: Space.s1),
                      Text(
                        '${formatCount(preview.childCount)} '
                        '${preview.childLabel}',
                        style: text.micro.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentSkeleton extends StatelessWidget {
  const _AttachmentSkeleton();

  @override
  Widget build(BuildContext context) => const KShimmer(
        child: SizedBox(
          height: EntityAttachmentCard.thumb,
          child: KSkeleton(
            borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
            height: EntityAttachmentCard.thumb,
          ),
        ),
      );
}
