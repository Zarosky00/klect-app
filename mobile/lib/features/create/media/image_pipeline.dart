import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'blurhash.dart';

/// A photo that has been decoded, oriented, optionally cropped and rotated,
/// downscaled, re-encoded and hashed, and is ready to be handed to Storage.
///
/// Everything `item_media` needs is on this object — nothing downstream has to
/// touch pixels again.
@immutable
class PreparedImage {
  /// Creates a prepared image.
  const PreparedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.blurhash,
    required this.mimeType,
    required this.extension,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  /// The re-encoded payload that actually gets uploaded.
  final Uint8List bytes;

  /// Intrinsic width of [bytes] — goes straight into `item_media.width`.
  final int width;

  /// Intrinsic height of [bytes] — goes straight into `item_media.height`.
  final int height;

  /// BlurHash placeholder for [bytes].
  final String blurhash;

  /// Content type to upload with.
  final String mimeType;

  /// File extension, without the dot.
  final String extension;

  /// Width of the source after EXIF orientation was baked, **before** any
  /// rotate/crop/resize. This is the pixel space a [ImagePipeline.prepare]
  /// `cropRect` is expressed against (after the quarter turns are applied).
  final int sourceWidth;

  /// Height of the oriented source. See [sourceWidth].
  final int sourceHeight;

  /// Payload size in bytes — `item_media.bytes`.
  int get byteLength => bytes.length;

  /// Aspect ratio (width / height).
  double get aspect => height <= 0 ? 1 : width / height;
}

/// Client-side image preparation.
///
/// `docs/CHECKLIST.md` §A: *"Client-side downscale + re-encode before upload
/// (never ship a 12 MP original over cellular)"* and *"Blurhash + intrinsic
/// width/height computed at upload"*. Both happen here, on a background
/// isolate, so a 12 MP capture never janks the create screen.
///
/// The FRAME beat of the create flow adds two edits, both applied in the same
/// single decode:
///  * `quarterTurns` — clockwise 90° rotations, applied after the EXIF bake;
///  * `cropRect` — a rectangle in **oriented pixel space** (after the bake and
///    after the quarter turns), applied before the downscale so the blurhash
///    and intrinsic dimensions always describe exactly what was uploaded.
abstract final class ImagePipeline {
  /// Long edge every upload is reduced to.
  ///
  /// 2048 is the point where a full-bleed photo on a 3x phone screen is still
  /// oversampled, and is roughly a 12× byte reduction from a modern 12 MP
  /// sensor.
  static const int maxLongEdge = 2048;

  /// Encoder quality. 82 is the knee of the quality/size curve for photography.
  static const int quality = 82;

  /// MIME type of the produced payload.
  ///
  /// The `image` package's WebP encoder is lossless-only (VP8L), which for
  /// photographs is *larger* than the original JPEG — so the pipeline emits
  /// JPEG at [quality], which is the other half of the brief's
  /// "WebP/JPEG q~82".
  static const String mimeType = 'image/jpeg';

  /// File extension matching [mimeType].
  static const String extension = 'jpg';

  /// Largest input we will even attempt to decode, as a guard against a
  /// pathological file picked from a file manager.
  static const int maxInputBytes = 60 * 1024 * 1024;

  /// Smallest crop edge the pipeline will apply, in source pixels — a guard
  /// against a degenerate sliver, not an ergonomic floor (the FRAME editor
  /// enforces its own finger-sized minimum on top).
  static const int minCropEdge = 8;

  /// Decodes, orients, rotates, crops, downscales, re-encodes and hashes
  /// [raw] — one decode for the whole chain.
  ///
  /// [cropRect] is in oriented pixel space (post-EXIF-bake, post
  /// [quarterTurns]); it is clamped to the frame, so a rect nudged past an
  /// edge by gesture math never throws. Runs on a background isolate. Throws
  /// [ImagePreparationException] when the bytes are not a decodable image.
  static Future<PreparedImage> prepare(
    Uint8List raw, {
    Rect? cropRect,
    int quarterTurns = 0,
  }) {
    if (raw.isEmpty) {
      throw const ImagePreparationException('That file is empty.');
    }
    if (raw.length > maxInputBytes) {
      throw const ImagePreparationException(
        'That image is too large to process.',
      );
    }
    return compute(
      _prepareSync,
      _PrepareRequest(
        raw: raw,
        quarterTurns: quarterTurns,
        cropLeft: cropRect?.left,
        cropTop: cropRect?.top,
        cropWidth: cropRect?.width,
        cropHeight: cropRect?.height,
      ),
      debugLabel: 'klect.prepareImage',
    );
  }

  /// Prepares a batch, one at a time.
  ///
  /// Sequential on purpose: three concurrent 12 MP decodes will out-allocate a
  /// mid-range phone. [onDone] fires after each file so a tray can fill in
  /// progressively.
  static Future<List<PreparedImage>> prepareAll(
    List<Uint8List> sources, {
    void Function(int index, PreparedImage image)? onDone,
  }) async {
    final out = <PreparedImage>[];
    for (var i = 0; i < sources.length; i++) {
      final prepared = await prepare(sources[i]);
      out.add(prepared);
      onDone?.call(i, prepared);
    }
    return out;
  }

  /// Rotates a crop rect a quarter turn clockwise inside a frame whose
  /// pre-turn height was [height].
  ///
  /// The FRAME editor uses this so an existing crop follows the photo when the
  /// rotate button is tapped, instead of snapping back to full frame.
  static Rect rotateCropRect(Rect rect, {required double height}) =>
      Rect.fromLTWH(
        height - rect.top - rect.height,
        rect.left,
        rect.height,
        rect.width,
      );
}

/// Thrown when bytes cannot be turned into an uploadable image.
class ImagePreparationException implements Exception {
  /// Creates a preparation failure with a user-facing [message].
  const ImagePreparationException(this.message);

  /// Message safe to show a user.
  final String message;

  @override
  String toString() => 'ImagePreparationException($message)';
}

/// The isolate payload — plain numbers only, so nothing platform-bound
/// crosses the boundary.
@immutable
class _PrepareRequest {
  const _PrepareRequest({
    required this.raw,
    required this.quarterTurns,
    this.cropLeft,
    this.cropTop,
    this.cropWidth,
    this.cropHeight,
  });

  final Uint8List raw;
  final int quarterTurns;
  final double? cropLeft;
  final double? cropTop;
  final double? cropWidth;
  final double? cropHeight;

  bool get hasCrop => cropLeft != null;
}

/// Isolate entry point. Must stay top-level.
PreparedImage _prepareSync(_PrepareRequest request) {
  final decoded = img.decodeImage(request.raw);
  if (decoded == null) {
    throw const ImagePreparationException(
      'That file is not an image we can read.',
    );
  }

  // One decode, four ordered steps: bake EXIF orientation first so every
  // later coordinate is in the pixels the user actually saw, then the quarter
  // turns, then the crop (expressed in that turned space), then the downscale
  // — so the blurhash and dimensions always describe the final payload.
  final oriented = img.bakeOrientation(decoded);

  final turns = ((request.quarterTurns % 4) + 4) % 4;
  final turned =
      turns == 0 ? oriented : img.copyRotate(oriented, angle: 90 * turns);

  var framed = turned;
  if (request.hasCrop) {
    // Clamp: gesture math on the UI thread may overshoot an edge by a
    // fraction of a pixel, and copyCrop must never receive an out-of-bounds
    // rectangle.
    final x = request.cropLeft!.round().clamp(0, turned.width - 1).toInt();
    final y = request.cropTop!.round().clamp(0, turned.height - 1).toInt();
    final w = request.cropWidth!.round().clamp(1, turned.width - x).toInt();
    final h = request.cropHeight!.round().clamp(1, turned.height - y).toInt();
    final coversEverything =
        x == 0 && y == 0 && w == turned.width && h == turned.height;
    if (!coversEverything &&
        w >= ImagePipeline.minCropEdge &&
        h >= ImagePipeline.minCropEdge) {
      framed = img.copyCrop(turned, x: x, y: y, width: w, height: h);
    }
  }

  final longEdge = math.max(framed.width, framed.height);
  final img.Image sized;
  if (longEdge > ImagePipeline.maxLongEdge) {
    final scale = ImagePipeline.maxLongEdge / longEdge;
    sized = img.copyResize(
      framed,
      width: math.max(1, (framed.width * scale).round()),
      height: math.max(1, (framed.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    sized = framed;
  }

  final blurhash = Blurhash.encode(sized);
  final bytes = img.encodeJpg(sized, quality: ImagePipeline.quality);

  return PreparedImage(
    bytes: bytes,
    width: sized.width,
    height: sized.height,
    blurhash: blurhash,
    mimeType: ImagePipeline.mimeType,
    extension: ImagePipeline.extension,
    sourceWidth: oriented.width,
    sourceHeight: oriented.height,
  );
}
