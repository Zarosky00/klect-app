import 'package:flutter/material.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// One draggable row.
@immutable
class ReorderEntry {
  /// Creates an entry.
  const ReorderEntry({
    required this.id,
    required this.label,
    this.subtitle,
    this.imageUrl,
    this.blurhash,
  });

  /// Primary key — this is what comes back in the new order.
  final String id;

  /// Row title.
  final String label;

  /// Optional second line.
  final String? subtitle;

  /// Thumbnail URL.
  final String? imageUrl;

  /// Thumbnail placeholder.
  final String? blurhash;
}

/// Drag-to-reorder, persisted to `position` by the caller.
///
/// Deliberately a sheet rather than an in-place drag on the grid: reordering
/// is a deliberate mode, and a long-press drag on a grid tile would collide
/// with the peek gesture.
abstract final class ReorderSheet {
  /// Opens the sheet. Resolves with the new order, or null when cancelled.
  static Future<List<String>?> show(
    BuildContext context, {
    required String title,
    required List<ReorderEntry> entries,
    String hint = 'Drag to change the order. The first one leads.',
  }) =>
      KSheet.show<List<String>>(
        context: context,
        title: title,
        maxHeightFraction: 0.9,
        builder: (sheetContext) => _ReorderBody(entries: entries, hint: hint),
      );
}

class _ReorderBody extends StatefulWidget {
  const _ReorderBody({required this.entries, required this.hint});

  final List<ReorderEntry> entries;
  final String hint;

  @override
  State<_ReorderBody> createState() => _ReorderBodyState();
}

class _ReorderBodyState extends State<_ReorderBody> {
  late final List<ReorderEntry> _entries = widget.entries.toList();
  bool _dirty = false;

  /// [newIndex] already accounts for the removal of the dragged row — that is
  /// the contract of `onReorderItem`.
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final entry = _entries.removeAt(oldIndex);
      _entries.insert(newIndex.clamp(0, _entries.length), entry);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.hint,
          style: context.kt.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: Space.s3),
        Flexible(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            itemCount: _entries.length,
            onReorderItem: _onReorder,
            proxyDecorator: (child, index, animation) => Material(
              type: MaterialType.transparency,
              child: child,
            ),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              return _ReorderRow(
                key: ValueKey<String>(entry.id),
                entry: entry,
                index: index,
              );
            },
          ),
        ),
        const SizedBox(height: Space.s4),
        Row(
          children: <Widget>[
            Expanded(
              child: KButton(
                label: 'Cancel',
                variant: KButtonVariant.secondary,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: KButton(
                label: 'Save order',
                expand: true,
                onPressed: _dirty
                    ? () => Navigator.of(context).pop(
                          <String>[for (final e in _entries) e.id],
                        )
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReorderRow extends StatelessWidget {
  const _ReorderRow({required this.entry, required this.index, super.key});

  final ReorderEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Container(
        padding: const EdgeInsets.all(Space.s2),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: Space.s10,
              height: Space.s10,
              child: entry.imageUrl == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface3,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Icon(
                        Icons.image_rounded,
                        size: Space.s5,
                        color: colors.textTertiary,
                      ),
                    )
                  : KBlurhashImage(
                      url: entry.imageUrl,
                      blurhash: entry.blurhash,
                      aspectRatio: Aspect.cover,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    entry.label,
                    style: context.kt.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.subtitle != null)
                    Text(
                      entry.subtitle!,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (index == 0)
              Padding(
                padding: const EdgeInsets.only(right: Space.s2),
                child: Text(
                  'FIRST',
                  style: context.kt.micro.copyWith(color: colors.accentDefault),
                ),
              ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle_rounded,
                size: Space.s5,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
