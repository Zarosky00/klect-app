import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../core/images/k_image_cache.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import 'k_pressable.dart';

/// The only image widget in the product.
///
/// Three rules from `docs/DESIGN_SYSTEM.md` §5, all enforced here:
///  1. **reserve the tile before the image loads** — pass [width]/[height] (the
///     intrinsic pixels the feed gave you) and the box is laid out immediately,
///     so the masonry never reflows;
///  2. **paint the blurhash** while the bytes are in flight;
///  3. **cross-fade the photo in** over `fast`.
///
/// Loading is honest about failure: fetches time out and retry a bounded
/// number of times (see [KImageCache]), and when they still fail a visible
/// chip appears over the blurhash — tapping it evicts the broken cache entry
/// and tries again. A failed image never masquerades as a loading one.
class KBlurhashImage extends StatefulWidget {
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

  @override
  State<KBlurhashImage> createState() => _KBlurhashImageState();
}

class _KBlurhashImageState extends State<KBlurhashImage> {
  /// Bumped after an evict so the provider is rebuilt from scratch instead of
  /// replaying the cached failure.
  int _retryGeneration = 0;
  bool _evicting = false;

  /// The ratio this box will occupy, or null when it should fill its parent.
  double? get _ratio {
    if (widget.aspectRatio != null) return widget.aspectRatio;
    final w = widget.width;
    final h = widget.height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  Future<void> _retry(String source) async {
    if (_evicting) return;
    setState(() => _evicting = true);
    // Drops both the disk entry and the in-memory decoded bitmap, so the
    // generation bump below forces a genuine re-download.
    await CachedNetworkImage.evictFromCache(
      source,
      cacheManager: KImageCache.instance,
    );
    if (!mounted) return;
    setState(() {
      _evicting = false;
      _retryGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ??
        const BorderRadius.all(Radius.circular(Radii.md));

    Widget content = ClipRRect(
      borderRadius: radius,
      child: _buildImage(context),
    );

    final ratio = _ratio;
    if (ratio != null) {
      content = AspectRatio(aspectRatio: ratio, child: content);
    }

    if (widget.heroTag != null) {
      content = Hero(tag: widget.heroTag!, child: content);
    }

    return Semantics(image: true, label: widget.semanticLabel, child: content);
  }

  Widget _buildImage(BuildContext context) {
    final source = widget.url;
    if (source == null || source.isEmpty) {
      return _Placeholder(blurhash: widget.blurhash, fit: widget.fit);
    }
    return CachedNetworkImage(
      key: ValueKey<String>('$source#$_retryGeneration'),
      imageUrl: source,
      cacheManager: KImageCache.instance,
      fit: widget.fit,
      fadeInDuration: KDurations.fast,
      fadeOutDuration: KDurations.instant,
      fadeInCurve: Curves_.decelerate,
      memCacheWidth: widget.memCacheWidth,
      placeholder: (context, _) =>
          _Placeholder(blurhash: widget.blurhash, fit: widget.fit),
      errorWidget: (context, _, _) => _evicting
          ? _Placeholder(blurhash: widget.blurhash, fit: widget.fit)
          : _FailedImage(
              blurhash: widget.blurhash,
              fit: widget.fit,
              onRetry: () => unawaited(_retry(source)),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.blurhash, required this.fit});

  final String? blurhash;
  final BoxFit fit;

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
    return ColoredBox(color: colors.skeletonBase);
  }
}

/// The failed state: the blurhash stays as context, and an unmissable chip
/// says so — a failure that looks identical to loading is the bug this fixes.
class _FailedImage extends StatelessWidget {
  const _FailedImage({
    required this.blurhash,
    required this.fit,
    required this.onRetry,
  });

  final String? blurhash;
  final BoxFit fit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Image failed to load. Tap to retry.',
      excludeSemantics: true,
      child: KPressable(
        enforceMinTapTarget: false,
        onTap: onRetry,
        child: Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            _Placeholder(blurhash: blurhash, fit: fit),
            const Positioned.fill(
              child: Center(
                // Scales the chip down instead of overflowing a tiny tile.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: EdgeInsets.all(Space.s2),
                    child: _RetryChip(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryChip extends StatelessWidget {
  const _RetryChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s15,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: colors.borderDefault, width: Strokes.thin),
        boxShadow: KlectTheme.shadow(Elevation.low),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.refresh_rounded,
            size: Space.s4,
            color: colors.textSecondary,
          ),
          const SizedBox(width: Space.s1),
          Text(
            'Tap to retry',
            style: context.kt.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
