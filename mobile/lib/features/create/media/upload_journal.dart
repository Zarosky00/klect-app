import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../core/storage/key_value_store.dart';

/// One item whose photos were still being uploaded when the app last stopped.
@immutable
class UploadDraft {
  /// Creates a draft record.
  const UploadDraft({
    required this.itemId,
    required this.userId,
    required this.createdAt,
    this.newItem = false,
    this.pending = const <String>[],
    this.committed = const <String>[],
  });

  /// Parses a persisted record.
  factory UploadDraft.fromJson(Map<String, dynamic> json) => UploadDraft(
        itemId: asString(json['item_id']),
        userId: asString(json['user_id']),
        createdAt: asDateOrNull(json['created_at']) ?? DateTime.now().toUtc(),
        newItem: asBool(json['new_item']),
        pending: asStringList(json['pending']),
        committed: asStringList(json['committed']),
      );

  /// The `items` row the photos belong to.
  final String itemId;

  /// Who was uploading — a draft from another account is never swept.
  final String userId;

  /// When the draft was opened.
  final DateTime createdAt;

  /// True when the `items` row was created *for* this upload.
  ///
  /// Only a brand-new item may be deleted by the sweeper for having no photos:
  /// adding photos to an existing item must never be able to remove it.
  final bool newItem;

  /// Object keys written to Storage that have **no** `item_media` row yet.
  /// These are exactly the blobs a mid-upload kill would orphan.
  final List<String> pending;

  /// Object keys that made it all the way to an `item_media` row.
  final List<String> committed;

  /// Serialises for [KeyValueStore].
  Map<String, dynamic> toJson() => <String, dynamic>{
        'item_id': itemId,
        'user_id': userId,
        'created_at': createdAt.toIso8601String(),
        'new_item': newItem,
        'pending': pending,
        'committed': committed,
      };

  /// Copy with overrides.
  UploadDraft copyWith({List<String>? pending, List<String>? committed}) =>
      UploadDraft(
        itemId: itemId,
        userId: userId,
        createdAt: createdAt,
        newItem: newItem,
        pending: pending ?? this.pending,
        committed: committed ?? this.committed,
      );
}

/// A durable write-ahead log for photo uploads.
///
/// `docs/CHECKLIST.md` §A: *"app kill mid-upload doesn't orphan rows"*. The
/// only way to guarantee that without a server-side janitor is to record the
/// exact object key **before** writing it, and clear the record only once the
/// matching `item_media` row exists. Whatever is still marked pending at the
/// next launch is, by definition, garbage.
class UploadJournal {
  /// Wraps a key/value store.
  UploadJournal(this._store);

  static const String _key = 'klect.uploads.drafts.v1';

  final KeyValueStore _store;
  final Map<String, UploadDraft> _drafts = <String, UploadDraft>{};
  bool _loaded = false;

  /// Every draft currently on record.
  List<UploadDraft> get drafts {
    _load();
    return _drafts.values.toList(growable: false);
  }

  /// Opens a draft for [itemId].
  ///
  /// Pass [newItem] when the `items` row was created specifically to hold
  /// these photos — that is the only case in which the sweeper may delete it.
  Future<void> begin({
    required String itemId,
    required String userId,
    bool newItem = false,
  }) {
    _load();
    // A second attempt after a partial failure must not forget the object keys
    // the first attempt already wrote, or they leak.
    final existing = _drafts[itemId];
    _drafts[itemId] = UploadDraft(
      itemId: itemId,
      userId: userId,
      createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
      newItem: newItem || (existing?.newItem ?? false),
      pending: existing?.pending ?? const <String>[],
      committed: existing?.committed ?? const <String>[],
    );
    return _flush();
  }

  /// Records that [objectPath] is about to be written to Storage.
  Future<void> markPending(String itemId, String objectPath) {
    _load();
    final draft = _drafts[itemId];
    if (draft == null) return Future<void>.value();
    if (draft.pending.contains(objectPath)) return Future<void>.value();
    _drafts[itemId] = draft.copyWith(
      pending: <String>[...draft.pending, objectPath],
    );
    return _flush();
  }

  /// Records that [objectPath] now has an `item_media` row.
  Future<void> markCommitted(String itemId, String objectPath) {
    _load();
    final draft = _drafts[itemId];
    if (draft == null) return Future<void>.value();
    _drafts[itemId] = draft.copyWith(
      pending: <String>[
        for (final path in draft.pending)
          if (path != objectPath) path,
      ],
      committed: <String>[...draft.committed, objectPath],
    );
    return _flush();
  }

  /// Drops [objectPath] from the draft entirely — used when an upload is
  /// cancelled and the blob has already been deleted.
  Future<void> forget(String itemId, String objectPath) {
    _load();
    final draft = _drafts[itemId];
    if (draft == null) return Future<void>.value();
    _drafts[itemId] = draft.copyWith(
      pending: <String>[
        for (final path in draft.pending)
          if (path != objectPath) path,
      ],
      committed: <String>[
        for (final path in draft.committed)
          if (path != objectPath) path,
      ],
    );
    return _flush();
  }

  /// Closes the draft for [itemId]. Everything reached its destination.
  Future<void> finish(String itemId) {
    _load();
    if (_drafts.remove(itemId) == null) return Future<void>.value();
    return _flush();
  }

  /// Reads one draft.
  UploadDraft? draftFor(String itemId) {
    _load();
    return _drafts[itemId];
  }

  void _load() {
    if (_loaded) return;
    _loaded = true;
    final raw = _store.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      for (final entry in asMapList(decoded)) {
        final draft = UploadDraft.fromJson(entry);
        if (draft.itemId.isEmpty) continue;
        _drafts[draft.itemId] = draft;
      }
    } on FormatException {
      // A corrupt journal must never wedge the app; the worst case of dropping
      // it is a blob that survives one upload cycle longer than it should.
      _drafts.clear();
    }
  }

  Future<void> _flush() {
    final payload = jsonEncode(
      <Map<String, dynamic>>[
        for (final draft in _drafts.values) draft.toJson(),
      ],
    );
    return _store.setString(_key, payload);
  }
}

/// The app's upload journal.
final uploadJournalProvider = Provider<UploadJournal>(
  (ref) => UploadJournal(ref.watch(keyValueStoreProvider)),
  name: 'uploadJournal',
);

/// What one sweep of the journal cleaned up.
@immutable
class MediaSweepResult {
  /// Creates a sweep result.
  const MediaSweepResult({
    this.blobsRemoved = 0,
    this.itemsRemoved = 0,
    this.draftsClosed = 0,
  });

  /// Orphaned Storage objects deleted.
  final int blobsRemoved;

  /// Shell items (created, but never given a single photo) deleted.
  final int itemsRemoved;

  /// Journal entries closed.
  final int draftsClosed;

  /// True when the previous run really did leave something behind.
  bool get didWork => blobsRemoved > 0 || itemsRemoved > 0;
}

/// Reconciles the journal against the server.
///
/// Runs once per app session, the first time any Library or Create screen is
/// mounted:
///  * every **pending** object key is deleted from Storage — it was written but
///    never registered, so nothing will ever reference it;
///  * an item that was created *for* this upload and ended up with zero
///    `item_media` rows is deleted, because a photoless new item is the shell
///    of an abandoned upload, not content — an item that already existed is
///    never touched;
///  * the draft is then closed.
class MediaRecovery {
  /// Creates a sweeper.
  const MediaRecovery(this._api, this._journal);

  final KlectApi _api;
  final UploadJournal _journal;

  /// Performs the sweep. Never throws — recovery must not break a cold start.
  Future<MediaSweepResult> sweep() async {
    final me = _api.currentUserId;
    if (me == null) return const MediaSweepResult();

    var blobs = 0;
    var items = 0;
    var closed = 0;

    for (final draft in _journal.drafts) {
      if (draft.userId != me) {
        // Another account's leftovers: we cannot delete them under this JWT,
        // and keeping them would leak an item id. Drop the record only.
        await _journal.finish(draft.itemId);
        closed++;
        continue;
      }

      for (final path in draft.pending) {
        try {
          await _api.removeUpload(StorageBucket.media, path);
          blobs++;
        } on KlectError {
          // Already gone, or offline — either way the record is about to be
          // dropped and a stray public blob is not worth blocking a launch.
        }
      }

      try {
        final media = await _api.fetchItemMedia(draft.itemId);
        if (media.isEmpty && draft.newItem) {
          await _api.deleteItem(draft.itemId);
          items++;
        }
      } on KlectError {
        // Offline: leave the draft in place so the next launch retries.
        continue;
      }

      await _journal.finish(draft.itemId);
      closed++;
    }

    return MediaSweepResult(
      blobsRemoved: blobs,
      itemsRemoved: items,
      draftsClosed: closed,
    );
  }
}

/// Runs [MediaRecovery.sweep] exactly once per session.
///
/// Every screen in `features/library/` and `features/create/` watches this, so
/// the reconciliation has always happened before a user can look at the shelf
/// an interrupted upload would have polluted.
final mediaRecoveryProvider = FutureProvider<MediaSweepResult>(
  (ref) => MediaRecovery(
    ref.watch(klectApiProvider),
    ref.watch(uploadJournalProvider),
  ).sweep(),
  name: 'mediaRecovery',
);
