import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'k_blurhash_image.dart';
import 'k_pressable.dart';

/// Circular avatar with a verified badge and an initials fallback.
class KAvatar extends StatelessWidget {
  /// Creates an avatar.
  const KAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.size = Space.s10,
    this.isVerified = false,
    this.showRing = false,
    this.onTap,
    this.heroTag,
  });

  /// Absolute URL of the avatar.
  final String? imageUrl;

  /// Display name, used for the initials fallback and the semantic label.
  final String? name;

  /// Diameter.
  final double size;

  /// Draws the verified badge.
  final bool isVerified;

  /// Draws an oxblood accent ring — used for "has something new".
  final bool showRing;

  /// Tap handler; usually routes to `/u/:username`.
  final VoidCallback? onTap;

  /// Shared-element tag.
  final Object? heroTag;

  String get _initials {
    final source = (name ?? '').trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final badgeSize = size / 3;

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surface3,
        border: showRing
            ? Border.all(color: colors.accentDefault, width: Strokes.thick)
            : Border.all(color: colors.borderSubtle, width: Strokes.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.isEmpty
          ? Center(
              child: Text(
                _initials,
                style: context.kt.label.copyWith(color: colors.textSecondary),
              ),
            )
          : KBlurhashImage(
              url: imageUrl,
              borderRadius: BorderRadius.circular(size),
              memCacheWidth: (size * 3).round(),
            ),
    );

    if (heroTag != null) {
      avatar = Hero(tag: heroTag!, child: avatar);
    }

    if (isVerified) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          avatar,
          Positioned(
            right: -Space.s05,
            bottom: -Space.s05,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.bgBase,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.verified_rounded,
                size: badgeSize,
                color: colors.accentDefault,
              ),
            ),
          ),
        ],
      );
    }

    final labelled = Semantics(
      label: name == null
          ? null
          : isVerified
          ? '$name, verified'
          : name,
      image: true,
      child: avatar,
    );

    if (onTap == null) return labelled;
    return KPressable(
      enforceMinTapTarget: false,
      semanticLabel: name,
      onTap: onTap,
      child: labelled,
    );
  }
}
