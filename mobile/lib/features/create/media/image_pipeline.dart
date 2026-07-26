import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'blurhash.dart';

/// A photo that has been decoded, downscaled, re-encoded and hashed, and is
/// ready to be handed to Storage.
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

  /// Decodes, orients, downscales, re-encodes and hashes [raw].
  ///
  /// Runs on a background isolate. Throws [ImagePreparationException] when the
  /// bytes are not a decodable image.
  static Future<PreparedImage> prepare(Uint8List raw) {
    if (raw.isEmpty) {
      throw const ImagePreparationException('That file is empty.');
    }
    if (raw.length > maxInputBytes) {
      throw const ImagePreparationException(
        'That image is too large to process.',
      );
    }
    return compute(_prepareSync, raw, debugLabel: 'klect.prepareImage');
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

/// Isolate entry point. Must stay top-level.
PreparedImage _prepareSync(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw const ImagePreparationException(
      'That file is not an image we can read.',
    );
  }

  // `copyResize` bakes EXIF orientation for us, but only when it actually
  // resizes — so an already-small photo has to be oriented explicitly or it
  // uploads sideways.
  final longEdge = math.max(decoded.width, decoded.height);
  final img.Image sized;
  if (longEdge > ImagePipeline.maxLongEdge) {
    final scale = ImagePipeline.maxLongEdge / longEdge;
    sized = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    sized = img.bakeOrientation(decoded);
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
  );
}
