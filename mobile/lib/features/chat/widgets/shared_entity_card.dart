import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../chat_api.dart';
import '../chat_models.dart';
import '../thread_controller.dart';

/// A collection, subcollection or item shared into a conversation.
///
/// All three levels of the hierarchy are shareable, so all three render the
/// same card — cover, an eyebrow naming the level, the title, and one line of
/// context. Tapping opens the canonical route for that entity, which is the
/// same URL the web app uses.
class SharedEntityCard extends ConsumerWidget {
  /// Creates a shared-entity card.
  const SharedEntityCard({
    required this.entityType,
    required this.entityId,
    super.key,
    this.onDark = false,
  });

  /// Which level of the hierarchy.
  final EntityType entityType;

  /// The entity's id.
  final String entityId;

  /// True inside the viewer's own bubble, whose fill is the oxblood accent.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final preview = ref.watch(
      sharedEntityPreviewProvider((type: entityType, id: entityId)),
    );

    final border = onDark ? colors.borderSubtle : colors.borderDefault;
    final background = onDark ? colors.surface1 : colors.surface2;

    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: border, width: Strokes.thin),
      ),
      clipBehavior: Clip.antiAlias,
      child: preview.when(
        data: (value) => value == null
            ? _Missing(entityType: entityType)
            : _Body(preview: value),
        loading: () => const _Loading(),
        error: (_, _) => _Missing(entityType: entityType),
      ),
    );

    return KPressable(
      enforceMinTapTarget: false,
      semanticLabel: 'Open shared ${_label(entityType)}',
      onTap: preview.value == null
          ? null
          : () => context.push(KlectLinks.pathFor(entityType, entityId)),
      child: card,
    );
  }

  static String _label(EntityType type) => switch (type) {
        EntityType.collection => 'collection',
        EntityType.subcollection => 'subcollection',
        EntityType.item => 'item',
        EntityType.post => 'post',
        EntityType.comment => 'comment',
      };
}

class _Body extends ConsumerWidget {
  const _Body({required this.preview});

  final SharedEntityPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final url = ref.watch(chatApiProvider).publicUrl(preview.coverPath);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: Space.s16,
          height: Space.s16,
          child: KBlurhashImage(
            url: url,
            blurhash: preview.coverBlurhash,
            borderRadius: BorderRadius.zero,
            aspectRatio: Aspect.cover,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s25,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  SharedEntityCard._label(preview.entityType).toUpperCase(),
                  style: text.micro.copyWith(color: colors.accentDefault),
                ),
                const SizedBox(height: Space.s05),
                Text(
                  preview.title,
                  style: text.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (preview.subtitle != null) ...<Widget>[
                  const SizedBox(height: Space.s05),
                  Text(
                    preview.subtitle!,
                    style: text.caption.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: Space.s2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: Space.s5,
            color: colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const KShimmer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: Space.s16,
              height: Space.s16,
              child: KSkeleton(borderRadius: BorderRadius.zero),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(Space.s3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    KSkeleton.text(width: Space.s12),
                    SizedBox(height: Space.s2),
                    KSkeleton.text(width: Space.s20),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _Missing extends StatelessWidget {
  const _Missing({required this.entityType});

  final EntityType entityType;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.visibility_off_outlined,
            size: Space.s5,
            color: colors.textTertiary,
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text(
              'This ${SharedEntityCard._label(entityType)} is no longer '
              'available to you.',
              style: context.kt.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
