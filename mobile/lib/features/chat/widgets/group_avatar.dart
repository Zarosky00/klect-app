import 'package:flutter/material.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// A group conversation's avatar.
///
/// Renders the uploaded image when `avatar_path` is set (the plumbing stays
/// intact end to end) and the default group glyph otherwise — deliberately a
/// glyph rather than initials, so a group never masquerades as a person.
class GroupAvatar extends StatelessWidget {
  /// Creates a group avatar.
  const GroupAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.size = Space.s10,
  });

  /// Resolved URL of the group's avatar, when one was uploaded.
  final String? imageUrl;

  /// Group title, for the semantic label.
  final String? name;

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return KAvatar(imageUrl: imageUrl, name: name, size: size);
    }
    final colors = context.kc;
    return Semantics(
      label: name,
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface3,
          border: Border.all(
            color: colors.borderSubtle,
            width: Strokes.hairline,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.groups_rounded,
          size: size / 2,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
