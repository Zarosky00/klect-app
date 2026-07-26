import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';

/// The outcome of moving an item between subcollections.
///
/// `docs/CHECKLIST.md` §A asks for the structural counters to be *verified*
/// after a move, not assumed — the trigger decrements one side and increments
/// the other, and this re-reads both so the UI can say so out loud.
@immutable
class ItemMoveResult {
  /// Creates a move result.
  const ItemMoveResult({
    required this.fromName,
    required this.toName,
    required this.fromCount,
    required this.toCount,
  });

  /// Name of the subcollection the item left.
  final String fromName;

  /// Name of the subcollection the item joined.
  final String toName;

  /// `item_count` of the source, re-read after the move.
  final int fromCount;

  /// `item_count` of the destination, re-read after the move.
  final int toCount;

  /// A one-line confirmation for a toast.
  String get summary => 'Moved to $toName — $fromName $fromCount, $toName $toCount.';
}

/// Every owner-only write in the Library.
///
/// Keeping them in one object means the screens stay declarative and the
/// invalidation contract (which caches a mutation dirties) lives next to the
/// mutation itself.
class LibraryActions {
  /// Wraps the API.
  const LibraryActions(this._api);

  final KlectApi _api;

  // ─────────────────────────────────────────────────────────── collections ──

  /// Renames / re-describes / re-scopes a collection.
  ///
  /// Only the keys the caller actually passes are sent, so an edit sheet can
  /// never blank a field it did not show. **An empty string clears the
  /// column** — that is how a cleared text box reaches the database as `null`
  /// rather than `''`.
  Future<void> editCollection(
    String id, {
    String? name,
    String? description,
    EntityVisibility? visibility,
    String? coverPath,
    String? coverBlurhash,
    bool clearCover = false,
    String? accentColor,
    bool? isPinned,
  }) =>
      _api.updateCollection(id, <String, dynamic>{
        'name': ?name,
        if (description != null) 'description': _blankToNull(description),
        if (visibility != null) 'visibility': visibility.wire,
        if (clearCover) ...<String, dynamic>{
          'cover_path': null,
          'cover_blurhash': null,
        } else ...<String, dynamic>{
          'cover_path': ?coverPath,
          'cover_blurhash': ?coverBlurhash,
        },
        if (accentColor != null) 'accent_color': _blankToNull(accentColor),
        'is_pinned': ?isPinned,
      });

  /// Deletes a collection. The database cascade purges its polymorphic rows.
  Future<void> deleteCollection(String id) => _api.deleteCollection(id);

  /// Persists a drag-reorder of a user's collections.
  Future<void> reorderCollections(List<String> orderedIds) =>
      _api.reorder(table: 'collections', orderedIds: orderedIds);

  // ──────────────────────────────────────────────────────── subcollections ──

  /// Edits a subcollection. A null [visibility] means "inherit the parent".
  Future<void> editSubcollection(
    String id, {
    String? name,
    String? description,
    EntityVisibility? visibility,
    bool clearVisibility = false,
    String? coverPath,
    String? coverBlurhash,
    bool clearCover = false,
  }) =>
      _api.updateSubcollection(id, <String, dynamic>{
        'name': ?name,
        if (description != null) 'description': _blankToNull(description),
        if (clearVisibility)
          'visibility': null
        else if (visibility != null)
          'visibility': visibility.wire,
        if (clearCover) ...<String, dynamic>{
          'cover_path': null,
          'cover_blurhash': null,
        } else ...<String, dynamic>{
          'cover_path': ?coverPath,
          'cover_blurhash': ?coverBlurhash,
        },
      });

  /// Deletes a subcollection and everything under it.
  Future<void> deleteSubcollection(String id) => _api.deleteSubcollection(id);

  /// Persists a drag-reorder of the subcollections inside one collection.
  Future<void> reorderSubcollections(List<String> orderedIds) =>
      _api.reorder(table: 'subcollections', orderedIds: orderedIds);

  // ───────────────────────────────────────────────────────────────── items ──

  /// Edits an item's metadata.
  ///
  /// Same contract as [editCollection]: an omitted argument is left alone, an
  /// empty string clears the column. The `clear*` flags exist for the fields
  /// that are not strings and therefore have no empty form.
  Future<void> editItem(
    String id, {
    String? title,
    String? description,
    String? brand,
    String? model,
    int? year,
    bool clearYear = false,
    String? condition,
    String? rarity,
    DateTime? acquisitionDate,
    bool clearAcquisitionDate = false,
    String? acquisitionPlace,
    double? purchasePrice,
    bool clearPurchasePrice = false,
    String? currency,
    bool? isFavorite,
    EntityVisibility? visibility,
    bool clearVisibility = false,
    Map<String, dynamic>? attributes,
  }) =>
      _api.updateItem(id, <String, dynamic>{
        'title': ?title,
        if (description != null) 'description': _blankToNull(description),
        if (brand != null) 'brand': _blankToNull(brand),
        if (model != null) 'model': _blankToNull(model),
        if (clearYear) 'year': null else 'year': ?year,
        if (condition != null) 'condition': _blankToNull(condition),
        if (rarity != null) 'rarity': _blankToNull(rarity),
        if (clearAcquisitionDate)
          'acquisition_date': null
        else if (acquisitionDate != null)
          'acquisition_date': _dateOnly(acquisitionDate),
        if (acquisitionPlace != null)
          'acquisition_place': _blankToNull(acquisitionPlace),
        if (clearPurchasePrice)
          'purchase_price': null
        else
          'purchase_price': ?purchasePrice,
        if (currency != null) 'currency': _blankToNull(currency),
        'is_favorite': ?isFavorite,
        if (clearVisibility)
          'visibility': null
        else if (visibility != null)
          'visibility': visibility.wire,
        'attributes': ?attributes,
      });

  /// Deletes an item and its photos.
  Future<void> deleteItem(String id) => _api.deleteItem(id);

  /// Persists a drag-reorder of the items in a subcollection.
  Future<void> reorderItems(List<String> orderedIds) =>
      _api.reorder(table: 'items', orderedIds: orderedIds);

  /// Puts a new row at the end of its list.
  ///
  /// Inserts default `position` to 0, which would drop every new row on top of
  /// the previous one; stamping the real tail keeps drag-reorder meaningful
  /// from the very first item.
  Future<void> appendPosition({
    required String table,
    required String id,
    required int position,
  }) async {
    switch (table) {
      case 'collections':
        await _api.updateCollection(id, <String, dynamic>{'position': position});
      case 'subcollections':
        await _api
            .updateSubcollection(id, <String, dynamic>{'position': position});
      case 'items':
        await _api.updateItem(id, <String, dynamic>{'position': position});
    }
  }

  /// Moves an item into another subcollection, then **verifies both counters**.
  ///
  /// [toCollectionId] is sent alongside so the denormalised `collection_id`
  /// never drifts when the destination lives on a different shelf.
  Future<ItemMoveResult> moveItem({
    required String itemId,
    required String fromSubcollectionId,
    required String toSubcollectionId,
    required String toCollectionId,
  }) async {
    await _api.updateItem(itemId, <String, dynamic>{
      'subcollection_id': toSubcollectionId,
      'collection_id': toCollectionId,
    });

    final from = await _api.fetchSubcollection(fromSubcollectionId);
    final to = await _api.fetchSubcollection(toSubcollectionId);

    return ItemMoveResult(
      fromName: from?.name ?? 'the old group',
      toName: to?.name ?? 'the new group',
      fromCount: from?.itemCount ?? 0,
      toCount: to?.itemCount ?? 0,
    );
  }

  // ───────────────────────────────────────────────────────────────── media ──

  /// Makes one photo the item's cover.
  ///
  /// A trigger derives `items.cover_*` from the media row at position 0, so the
  /// operation is "move it to the front"; the explicit patch afterwards means
  /// the screen shows the new cover immediately rather than after a round trip
  /// through the trigger.
  Future<void> setItemCover({
    required String itemId,
    required List<ItemMedia> media,
    required String mediaId,
  }) async {
    final target = media.where((m) => m.id == mediaId).firstOrNull;
    if (target == null) return;
    final ordered = <String>[
      mediaId,
      for (final m in media)
        if (m.id != mediaId) m.id,
    ];
    await _api.reorder(table: 'item_media', orderedIds: ordered);
    await _api.updateItem(itemId, <String, dynamic>{
      'cover_path': target.storagePath,
      'cover_blurhash': target.blurhash,
      'cover_width': target.width,
      'cover_height': target.height,
    });
  }

  /// Persists a drag-reorder of an item's photos.
  Future<void> reorderMedia({
    required String itemId,
    required List<ItemMedia> ordered,
  }) async {
    await _api.reorder(
      table: 'item_media',
      orderedIds: <String>[for (final m in ordered) m.id],
    );
    final cover = ordered.firstOrNull;
    if (cover == null) return;
    await _api.updateItem(itemId, <String, dynamic>{
      'cover_path': cover.storagePath,
      'cover_blurhash': cover.blurhash,
      'cover_width': cover.width,
      'cover_height': cover.height,
    });
  }

  /// An empty text box means "remove this value", not "store an empty string".
  static String? _blankToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// The Library's write surface.
final libraryActionsProvider = Provider<LibraryActions>(
  (ref) => LibraryActions(ref.watch(klectApiProvider)),
  name: 'libraryActions',
);
