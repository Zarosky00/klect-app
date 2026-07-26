import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import 'library_cards.dart';
import 'library_chrome.dart';
import 'quick_actions_sheet.dart';

/// The Library's shelf grid, as a sliver.
///
/// Reusable on purpose: the Create hub shows the signed-in user's shelves and a
/// profile shows anybody's, and both want exactly this layout.
class CollectionsSliverGrid extends StatelessWidget {
  /// Creates the grid.
  const CollectionsSliverGrid({
    required this.collections,
    super.key,
    this.isOwner = false,
    this.ownerActionsFor,
  });

  /// The shelves to render, already in the order they should appear.
  final List<CollectionModel> collections;

  /// Unlocks the owner rows inside each card's peek.
  final bool isOwner;

  /// Builds the owner rows for one shelf.
  final List<QuickOwnerAction> Function(CollectionModel)? ownerActionsFor;

  @override
  Widget build(BuildContext context) => SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: LibraryGrid.collectionExtent,
          crossAxisSpacing: Layout.masonryGutter,
          mainAxisSpacing: Layout.masonryGutter,
          childAspectRatio:
              LibraryGrid.ratioFor(LibraryGrid.collectionExtent),
        ),
        itemCount: collections.length,
        itemBuilder: (context, index) => CollectionCard(
          collection: collections[index],
          isOwner: isOwner,
          ownerActions: ownerActionsFor?.call(collections[index]) ??
              const <QuickOwnerAction>[],
        ),
      );
}
