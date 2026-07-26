import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../design/theme.dart';

/// Presentation helpers shared by the Create flow and the Library.
///
/// Nothing in here invents a design value: the only colours it produces come
/// from **data** (`collection_templates.accent_color`, `collections.accent_color`),
/// and every fallback is a token.
abstract final class EntityVisual {
  /// Maps `collection_templates.icon` slugs onto Material glyphs.
  ///
  /// The 18 seeded slugs are covered; anything unknown falls back to the
  /// generic shelf glyph rather than rendering an empty box.
  static const Map<String, IconData> _templateIcons = <String, IconData>{
    'sparkles': Icons.auto_awesome_rounded,
    'book-open': Icons.menu_book_rounded,
    'puzzle': Icons.extension_rounded,
    'layers': Icons.layers_rounded,
    'footprints': Icons.directions_walk_rounded,
    'disc': Icons.album_rounded,
    'library': Icons.local_library_rounded,
    'camera': Icons.photo_camera_rounded,
    'watch': Icons.watch_rounded,
    'palette': Icons.palette_rounded,
    'gamepad': Icons.sports_esports_rounded,
    'leaf': Icons.eco_rounded,
    'shirt': Icons.checkroom_rounded,
    'car': Icons.directions_car_rounded,
    'coffee': Icons.local_cafe_rounded,
    'cpu': Icons.memory_rounded,
    'map-pin': Icons.place_rounded,
    'shapes': Icons.category_rounded,
  };

  /// The glyph for a template icon slug.
  static IconData templateIcon(String? slug) =>
      _templateIcons[slug] ?? Icons.collections_bookmark_rounded;

  /// Parses a `#RRGGBB` / `#AARRGGBB` value that came from the database.
  ///
  /// Returns null for anything unparseable so callers fall back to a token.
  static Color? parseHex(String? value) {
    if (value == null) return null;
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  /// A data-driven accent, or the brass token when the row has none.
  static Color accent(BuildContext context, String? hex) =>
      parseHex(hex) ?? context.kc.accentDefault;

  /// The glyph for a visibility level. Null means "inherits from the parent".
  static IconData visibilityIcon(EntityVisibility? visibility) =>
      switch (visibility) {
        EntityVisibility.public => Icons.public_rounded,
        EntityVisibility.followers => Icons.group_rounded,
        EntityVisibility.private => Icons.lock_rounded,
        null => Icons.subdirectory_arrow_right_rounded,
      };

  /// The label for a visibility level, including the inherit case.
  static String visibilityLabel(
    EntityVisibility? visibility, {
    String inheritLabel = 'Same as parent',
  }) =>
      visibility?.label ?? inheritLabel;

  /// One line describing what a visibility choice actually means.
  static String visibilityHint(EntityVisibility? visibility) =>
      switch (visibility) {
        EntityVisibility.public =>
          'Anyone can see it, including people who are not signed in.',
        EntityVisibility.followers => 'Only accounts that follow you.',
        EntityVisibility.private => 'Only you.',
        null => 'Inherits whatever the level above it is set to.',
      };
}
