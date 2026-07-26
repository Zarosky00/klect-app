import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../design/motion.dart';
import '../design/theme.dart';

/// The only image widget in the product.
///
/// Three rules from `docs/DESIGN_SYSTEM.md` §5, all enforced here:
///  1. **reserve the tile before the image loads** — pass [width]/[height] (the
///     intrinsic pixels the feed gave you) and the box is laid out immediately,
///     so the masonry never reflows;
///  2. **paint the blurhash** while the bytes are in flight;
///  3. **cross-fade the photo in** over `fast`.
class KBlurhashImage extends StatelessWidget {
  /// Creates an image box.
  const KBlurhashImage({
    required this.url,
    super.key,
    this.blurhash,
    this.width,
    this.height,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.semanticLabel,
    this.heroTag,
    this.memCacheWidth,
  });

  /// Absolute URL. Null renders the placeholder forever, which is the correct
  /// look for an entity with no cover yet.
  final String? url;

  /// Blurhash placeholder.
  final String? blurhash;

  /// Intrinsic pixel width of the source.
  final int? width;

  /// Intrinsic pixel height of the source.
  final int? height;

  /// Overrides the ratio derived from [width]/[height].
  final double? aspectRatio;

  /// How the photo fills the box.
  final BoxFit fit;

  /// Corner rounding. Defaults to [Radii.md].
  final BorderRadius? borderRadius;

  /// `alt_text` from `item_media`. Screen readers read this.
  final String? semanticLabel;

  /// Shared-element tag for the card → closeup hero.
  final Object? heroTag;

  /// Decode width cap, so a long scroll keeps memory flat.
  final int? memCacheWidth;

  /// The ratio this box will occupy, or null when it should fill its parent.
  double? get _ratio {
    if (aspectRatio != null) return aspectRatio;
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius ?? const BorderRadius.all(Radius.circular(Radii.md));

    Widget content = ClipRRect(
      borderRadius: radius,
      child: _buildImage(context),
    );

    final ratio = _ratio;
    if (ratio != null) {
      content = AspectRatio(aspectRatio: ratio, child: content);
    }

    if (heroTag != null) {
      content = Hero(tag: heroTag!, child: content);
    }

    return Semantics(
      image: true,
      label: semanticLabel,
      child: content,
    );
  }

  Widget _buildImage(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) {
      return _Placeholder(blurhash: blurhash, fit: fit);
    }
    return CachedNetworkImage(
      imageUrl: source,
      fit: fit,
      fadeInDuration: KDurations.fast,
      fadeOutDuration: KDurations.instant,
      fadeInCurve: Curves_.decelerate,
      memCacheWidth: memCacheWidth,
      placeholder: (context, _) => _Placeholder(blurhash: blurhash, fit: fit),
      errorWidget: (context, _, _) =>
          _Placeholder(blurhash: blurhash, fit: fit, failed: true),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.blurhash,
    required this.fit,
    this.failed = false,
  });

  final String? blurhash;
  final BoxFit fit;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final hash = blurhash;
    if (hash != null && hash.length >= 6) {
      return Image(
        image: BlurHashImage(hash),
        fit: fit,
        errorBuilder: (context, _, _) => ColoredBox(color: colors.skeletonBase),
      );
    }
    return ColoredBox(
      color: colors.skeletonBase,
      child: failed
          ? Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: Space.s6,
                color: colors.textTertiary,
              ),
            )
          : null,
    );
  }
}
