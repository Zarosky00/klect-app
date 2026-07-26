import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import 'image_pipeline.dart';
import 'upload_journal.dart';

const Uuid _uuid = Uuid();

/// Where one photo is in the capture → upload → register pipeline.
enum UploadStage {
  /// Accepted, nothing has happened yet.
  queued,

  /// Decoding, downscaling, re-encoding and hashing on a background isolate.
  processing,

  /// Prepared and waiting for the item row to exist.
  ready,

  /// Bytes are in flight to the `media` bucket.
  uploading,

  /// Object written; filing the photo against its item.
  registering,

  /// Fully landed.
  done,

  /// Something went wrong. [UploadTask.error] says what; retry is offered.
  failed,

  /// The user pulled the handbrake before this one started.
  cancelled;

  /// Human label for the tile overlay.
  String get label => switch (this) {
        UploadStage.queued => 'Waiting',
        UploadStage.processing => 'Preparing',
        UploadStage.ready => 'Ready',
        UploadStage.uploading => 'Uploading',
        UploadStage.registering => 'Saving',
        UploadStage.done => 'Done',
        UploadStage.failed => 'Failed',
        UploadStage.cancelled => 'Cancelled',
      };

  /// Whether the stage represents work still to do.
  bool get isPending =>
      this == UploadStage.queued ||
      this == UploadStage.processing ||
      this == UploadStage.ready;

  /// Whether the pipeline is actively working on this file.
  bool get isActive =>
      this == UploadStage.processing ||
      this == UploadStage.uploading ||
      this == UploadStage.registering;
}

/// One photo moving through the pipeline.
class UploadTask {
  /// Creates a task.
  UploadTask({
    required this.id,
    required this.source,
    required this.displayName,
    this.prepared,
    this.stage = UploadStage.queued,
    this.objectPath,
    this.mediaId,
    this.error,
    this.cropRect,
    this.quarterTurns = 0,
  });

  /// Stable local id — the tray's widget key and the retry handle.
  final String id;

  /// The picked file. Kept so a retry never has to re-open the picker.
  final XFile source;

  /// File name, shown in the failure row.
  final String displayName;

  /// The downscaled payload, once [UploadStage.processing] has finished.
  PreparedImage? prepared;

  /// Crop chosen in the FRAME beat, in oriented pixel space (post-EXIF-bake,
  /// post-[quarterTurns]). Null uploads the full frame.
  Rect? cropRect;

  /// Clockwise 90° rotations chosen in the FRAME beat.
  int quarterTurns;

  /// Current stage.
  UploadStage stage;

  /// Object key inside the `media` bucket, once chosen.
  String? objectPath;

  /// `item_media.id`, once registered.
  String? mediaId;

  /// User-facing failure text.
  String? error;

  /// Fraction of this file's work that is provably complete.
  ///
  /// Each step is a real, observed transition — nothing here advances on a
  /// timer. `supabase_flutter` exposes no byte-level upload callback, so the
  /// bar holds at the start of [UploadStage.uploading] until the SDK's future
  /// resolves, rather than pretending to know.
  double get progress => switch (stage) {
        UploadStage.queued => 0,
        UploadStage.processing => 0,
        UploadStage.ready => _prepareWeight,
        UploadStage.uploading => _prepareWeight,
        UploadStage.registering => _prepareWeight + _uploadWeight,
        UploadStage.done => 1,
        UploadStage.failed => 0,
        UploadStage.cancelled => 0,
      };

  /// How much of the queue's total byte budget this file represents.
  int get weight => prepared?.byteLength ?? _assumedBytes;

  static const double _prepareWeight = 0.4;
  static const double _uploadWeight = 0.5;
  static const int _assumedBytes = 400 * 1024;
}

/// The result of pushing a whole tray to the server.
@immutable
class UploadOutcome {
  /// Creates an outcome.
  const UploadOutcome({
    required this.uploaded,
    required this.failed,
    required this.cancelled,
  });

  /// How many `item_media` rows were created.
  final int uploaded;

  /// How many files failed and are retryable.
  final int failed;

  /// True when the user cancelled part-way.
  final bool cancelled;

  /// Nothing left to do.
  bool get isComplete => failed == 0 && !cancelled;
}

/// A cover photo that has been uploaded but does not belong to an item.
@immutable
class UploadedCover {
  /// Creates an uploaded cover.
  const UploadedCover({
    required this.storagePath,
    required this.blurhash,
    required this.width,
    required this.height,
  });

  /// Object key inside the `media` bucket.
  final String storagePath;

  /// BlurHash placeholder.
  final String blurhash;

  /// Intrinsic width.
  final int width;

  /// Intrinsic height.
  final int height;
}

/// The capture → upload engine for one item draft.
///
/// The create flow obtains one through [mediaUploadControllerProvider], keyed
/// by draft id, so an in-flight upload keeps running when the user navigates
/// away — the flow invalidates the provider when the draft ends. Short-lived
/// surfaces (the add-photos sheet) may still own one directly.
///
/// Ordering is the contract: `item_media.position` follows tray order, and a
/// database trigger derives the item cover from position 0 — so "make cover"
/// is simply "move to the front".
class MediaUploadController extends ChangeNotifier {
  /// Creates a controller over the API and the durable upload journal.
  MediaUploadController(this._api, this._journal);

  /// Most photos one item is allowed to carry.
  static const int maxPhotos = 20;

  final KlectApi _api;
  final UploadJournal _journal;
  final List<UploadTask> _tasks = <UploadTask>[];

  bool _cancelled = false;
  bool _running = false;
  bool _disposed = false;

  /// The tray, in cover-first order.
  List<UploadTask> get tasks => List<UploadTask>.unmodifiable(_tasks);

  /// How many photos are in the tray.
  int get length => _tasks.length;

  /// Whether the tray is empty.
  bool get isEmpty => _tasks.isEmpty;

  /// True while anything is being prepared or uploaded.
  bool get isBusy => _running || _tasks.any((task) => task.stage.isActive);

  /// True when every photo has been prepared and none is still failing.
  bool get isReady =>
      _tasks.isNotEmpty &&
      _tasks.every(
        (task) => task.stage == UploadStage.ready || task.stage == UploadStage.done,
      );

  /// Whether at least one file needs a retry.
  bool get hasFailures => _tasks.any((task) => task.stage == UploadStage.failed);

  /// How many photos have fully landed.
  int get completedCount =>
      _tasks.where((task) => task.stage == UploadStage.done).length;

  /// Queue progress, weighted by each file's real payload size so a 4 MB photo
  /// does not count the same as a 200 KB one.
  double get overallProgress {
    if (_tasks.isEmpty) return 0;
    var total = 0.0;
    var done = 0.0;
    for (final task in _tasks) {
      final weight = task.weight.toDouble();
      total += weight;
      done += weight * task.progress;
    }
    return total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
  }

  /// How many more photos this tray will accept.
  int get remainingSlots => maxPhotos - _tasks.length;

  /// Adds picked files and prepares them immediately.
  ///
  /// Preparation happens up front, not at save time, so the tray can show a
  /// real thumbnail with the right aspect ratio and the Save tap is only ever
  /// waiting on the network.
  Future<void> addFiles(List<XFile> files) async {
    if (files.isEmpty) return;
    final accepted = files.take(remainingSlots).toList(growable: false);
    final added = <UploadTask>[];
    for (final file in accepted) {
      final task = UploadTask(
        id: _uuid.v4(),
        source: file,
        displayName: file.name.isEmpty ? 'photo' : file.name,
      );
      _tasks.add(task);
      added.add(task);
    }
    _notify();
    for (final task in added) {
      await _prepare(task);
    }
  }

  Future<void> _prepare(UploadTask task) async {
    if (_disposed) return;
    task
      ..stage = UploadStage.processing
      ..error = null;
    _notify();
    try {
      final raw = await task.source.readAsBytes();
      final prepared = await ImagePipeline.prepare(
        raw,
        cropRect: task.cropRect,
        quarterTurns: task.quarterTurns,
      );
      if (_disposed) return;
      task
        ..prepared = prepared
        ..stage = UploadStage.ready;
    } on ImagePreparationException catch (error) {
      if (_disposed) return;
      task
        ..stage = UploadStage.failed
        ..error = error.message;
    } catch (error) {
      if (_disposed) return;
      task
        ..stage = UploadStage.failed
        ..error = 'Could not read that photo.';
    }
    _notify();
  }

  /// Removes a photo from the tray, deleting its blob when one exists.
  ///
  /// A photo that already reached [UploadStage.done] is **not** removable here:
  /// it owns a real `item_media` row, and the client API contract has no
  /// method that deletes one. Deleting the whole item is the only path, and
  /// that is offered explicitly.
  Future<void> remove(String taskId) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) return;
    if (_tasks[index].stage == UploadStage.done) return;
    final task = _tasks.removeAt(index);
    _notify();
    final path = task.objectPath;
    if (path != null) await _deleteBlob(task, path);
  }

  /// Reorders the tray. Index 0 is the cover.
  ///
  /// [newIndex] is the destination **after** the dragged entry has been
  /// removed, which is what `ReorderableListView.onReorderItem` hands us.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tasks.length) return;
    final task = _tasks.removeAt(oldIndex);
    _tasks.insert(newIndex.clamp(0, _tasks.length), task);
    _notify();
  }

  /// Promotes a photo to the cover slot.
  void makeCover(String taskId) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index <= 0) return;
    reorder(index, 0);
  }

  /// Applies a FRAME edit — crop and/or quarter turns — and re-prepares.
  ///
  /// Re-cropping before save is free: the source file is still on disk, so
  /// this is just one more single-decode pass on the isolate. A photo that has
  /// already landed is immutable — its `item_media` row is the truth.
  Future<void> applyEdit(
    String taskId, {
    required Rect? cropRect,
    required int quarterTurns,
  }) async {
    final task = _tasks.firstWhereOrNullById(taskId);
    if (task == null || task.stage == UploadStage.done) return;
    final unchanged =
        task.cropRect == cropRect && task.quarterTurns == quarterTurns;
    if (unchanged && task.prepared != null) return;
    task
      ..cropRect = cropRect
      ..quarterTurns = quarterTurns
      ..prepared = null;
    await _prepare(task);
  }

  /// Re-runs one failed photo.
  Future<void> retry(String taskId, {String? itemId}) async {
    final task = _tasks.firstWhereOrNullById(taskId);
    if (task == null) return;
    _cancelled = false;
    if (task.prepared == null) {
      await _prepare(task);
      if (task.stage != UploadStage.ready) return;
    } else {
      task
        ..stage = UploadStage.ready
        ..error = null;
      _notify();
    }
    if (itemId == null) return;
    await _uploadOne(task, itemId: itemId, position: _tasks.indexOf(task));
  }

  /// Asks the running upload loop to stop after the current file.
  void cancel() {
    if (!isBusy) return;
    _cancelled = true;
    for (final task in _tasks) {
      if (task.stage.isPending) {
        task
          ..stage = UploadStage.cancelled
          ..error = null;
      }
    }
    _notify();
  }

  /// Pushes the whole tray to Storage and registers each photo.
  ///
  /// The journal is written *before* each object key is used and cleared only
  /// once its `item_media` row exists, so a kill at any point leaves a record
  /// the next launch can reconcile.
  ///
  /// [positionOffset] is how many photos the item already has — adding to an
  /// existing item must append rather than reset the cover.
  Future<UploadOutcome> uploadAll({
    required String itemId,
    int positionOffset = 0,
  }) async {
    _cancelled = false;
    _running = true;
    _notify();
    try {
      for (var index = 0; index < _tasks.length; index++) {
        if (_cancelled) break;
        final task = _tasks[index];
        if (task.stage == UploadStage.done) continue;
        if (task.stage == UploadStage.cancelled) {
          task.stage = UploadStage.ready;
        }
        if (task.prepared == null) {
          await _prepare(task);
          if (task.stage != UploadStage.ready) continue;
        }
        await _uploadOne(
          task,
          itemId: itemId,
          position: index + positionOffset,
        );
      }
    } finally {
      _running = false;
      _notify();
    }

    final failed = _tasks.where((t) => t.stage == UploadStage.failed).length;
    if (failed == 0 && !_cancelled) {
      await _journal.finish(itemId);
    }
    return UploadOutcome(
      uploaded: completedCount,
      failed: failed,
      cancelled: _cancelled,
    );
  }

  Future<void> _uploadOne(
    UploadTask task, {
    required String itemId,
    required int position,
  }) async {
    final prepared = task.prepared;
    if (prepared == null) return;

    final objectPath = task.objectPath ??
        '${_api.requireUserId}/$itemId/${_uuid.v4()}.${prepared.extension}';
    task
      ..objectPath = objectPath
      ..stage = UploadStage.uploading
      ..error = null;
    _notify();

    try {
      await _journal.markPending(itemId, objectPath);
      final key = await _api.upload(
        bucket: StorageBucket.media,
        objectPath: objectPath,
        bytes: prepared.bytes,
        contentType: prepared.mimeType,
        upsert: true,
      );
      if (_disposed) return;

      task.stage = UploadStage.registering;
      _notify();

      final media = await _api.createItemMedia(
        itemId: itemId,
        storagePath: key,
        width: prepared.width,
        height: prepared.height,
        blurhash: prepared.blurhash.isEmpty ? null : prepared.blurhash,
        mimeType: prepared.mimeType,
        bytes: prepared.byteLength,
        position: position,
      );
      if (_disposed) return;

      await _journal.markCommitted(itemId, key);
      task
        ..mediaId = media.id
        ..stage = UploadStage.done;
    } on KlectError catch (error) {
      if (_disposed) return;
      task
        ..stage = UploadStage.failed
        ..error = error.message;
    }
    _notify();
  }

  /// Throws the draft away: every blob this controller wrote is deleted and
  /// the journal entry is closed, so nothing is left behind.
  ///
  /// [includeCommitted] must stay false unless the caller is also deleting the
  /// item — a committed blob has an `item_media` row pointing at it, and
  /// removing the object without the row would leave a broken photo.
  Future<void> discard({String? itemId, bool includeCommitted = false}) async {
    _cancelled = true;
    for (final task in _tasks) {
      final path = task.objectPath;
      if (path == null) continue;
      if (task.stage == UploadStage.done && !includeCommitted) continue;
      await _deleteBlob(task, path);
    }
    _tasks.clear();
    if (itemId != null) await _journal.finish(itemId);
    _notify();
  }

  Future<void> _deleteBlob(UploadTask task, String path) async {
    try {
      await _api.removeUpload(StorageBucket.media, path);
    } on KlectError {
      // Best effort — the journal sweep will get it on the next launch.
    }
    task.objectPath = null;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

extension on List<UploadTask> {
  UploadTask? firstWhereOrNullById(String id) {
    for (final task in this) {
      if (task.id == id) return task;
    }
    return null;
  }
}

/// One upload engine per draft, held **outside** any screen.
///
/// Keyed by a caller-minted draft id and deliberately non-autodispose, so the
/// queue — and any upload already in flight — survives every navigation the
/// user makes while it runs. Whoever ends the draft (save landed, or the user
/// discarded) must `ref.invalidate(mediaUploadControllerProvider(draftId))`,
/// which disposes the controller and frees the prepared bytes.
final mediaUploadControllerProvider =
    Provider.family<MediaUploadController, String>(
  (ref, draftId) {
    final controller = MediaUploadController(
      ref.watch(klectApiProvider),
      ref.watch(uploadJournalProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  name: 'mediaUploadController',
);

/// A cover photo prepared on-device and previewable, but **not yet uploaded**.
///
/// Deliberately deferred: item photos have the upload journal to reconcile a
/// blob whose row never landed, but covers have no journal — so a cover
/// uploaded at pick time became an orphan every time the form was abandoned.
/// The bytes stay in memory until the owning form actually saves.
@immutable
class PendingCover {
  /// Creates a pending cover.
  const PendingCover({required this.prepared, required this.folder});

  /// The downscaled + hashed payload, ready for preview and upload.
  final PreparedImage prepared;

  /// Second path segment for the eventual object key.
  final String folder;

  /// BlurHash of the prepared payload.
  String get blurhash => prepared.blurhash;

  /// Pushes the bytes to the `media` bucket under
  /// `{user_id}/{folder}/{uuid}.jpg` and returns the landed descriptor.
  ///
  /// Call this from the save path, after the user has committed — never from
  /// the picker.
  Future<UploadedCover> upload(KlectApi api) async {
    final key = await api.upload(
      bucket: StorageBucket.media,
      objectPath: '${api.requireUserId}/$folder/'
          '${_uuid.v4()}.${prepared.extension}',
      bytes: prepared.bytes,
      contentType: prepared.mimeType,
    );
    return UploadedCover(
      storagePath: key,
      blurhash: prepared.blurhash,
      width: prepared.width,
      height: prepared.height,
    );
  }
}

/// Local preparation for a cover image that is not part of an item.
///
/// Collections and subcollections carry their own `cover_path`; they have no
/// `item_media` rows, so they do not need the queue — but they do need the same
/// downscale + blurhash treatment.
abstract final class CoverUploader {
  /// Decodes, downscales and hashes [file] on a background isolate.
  ///
  /// Nothing touches the network here — the caller holds the returned
  /// [PendingCover] and runs [PendingCover.upload] at save time, so an
  /// abandoned form never leaves a blob behind in Storage.
  static Future<PendingCover> prepare({
    required XFile file,
    required String folder,
  }) async {
    final raw = await file.readAsBytes();
    final prepared = await ImagePipeline.prepare(raw);
    return PendingCover(prepared: prepared, folder: folder);
  }
}
