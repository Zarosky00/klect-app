import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// A pure-Dart BlurHash **encoder**.
///
/// `flutter_blurhash` only decodes, and `docs/BACKEND_API.md` §4 requires a
/// `blurhash` on every `item_media` row so the masonry can paint a placeholder
/// before the bytes land. This is the reference algorithm (Wolt/BlurHash),
/// written against the `image` package so it can run inside a background
/// isolate together with the resize step.
abstract final class Blurhash {
  /// The base-83 alphabet the format is defined over.
  static const String alphabet =
      r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~';

  /// Longest edge the source is reduced to before the DCT runs.
  ///
  /// BlurHash only keeps a handful of low-frequency components, so sampling a
  /// full-resolution photo is pure waste — a 32px thumbnail produces a
  /// bit-identical hash for a fraction of the work.
  static const int sampleSize = 32;

  /// Encodes [image] into a BlurHash string.
  ///
  /// [componentX] and [componentY] must each be between 1 and 9. The default
  /// 4×3 grid is what the format's own reference implementation recommends for
  /// landscape-ish photography and is what the seeded demo rows use.
  static String encode(
    img.Image image, {
    int componentX = 4,
    int componentY = 3,
  }) {
    final cx = componentX.clamp(1, 9);
    final cy = componentY.clamp(1, 9);

    final sample = _downsample(image);
    final width = sample.width;
    final height = sample.height;
    if (width == 0 || height == 0) {
      // A zero-pixel image has no hash; callers treat null/empty as "no
      // placeholder", which is a legitimate state.
      return '';
    }

    // Cache the linear-light pixels once: the inner loop reads them cx*cy times.
    final linear = List<double>.filled(width * height * 3, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = sample.getPixel(x, y);
        final offset = (y * width + x) * 3;
        linear[offset] = _srgbToLinear(pixel.rNormalized.toDouble());
        linear[offset + 1] = _srgbToLinear(pixel.gNormalized.toDouble());
        linear[offset + 2] = _srgbToLinear(pixel.bNormalized.toDouble());
      }
    }

    final factors = <List<double>>[];
    for (var j = 0; j < cy; j++) {
      for (var i = 0; i < cx; i++) {
        final normalisation = (i == 0 && j == 0) ? 1.0 : 2.0;
        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        for (var y = 0; y < height; y++) {
          final basisY = math.cos(math.pi * j * y / height);
          for (var x = 0; x < width; x++) {
            final basis =
                basisY * math.cos(math.pi * i * x / width) * normalisation;
            final offset = (y * width + x) * 3;
            r += basis * linear[offset];
            g += basis * linear[offset + 1];
            b += basis * linear[offset + 2];
          }
        }
        final scale = 1.0 / (width * height);
        factors.add(<double>[r * scale, g * scale, b * scale]);
      }
    }

    final dc = factors.first;
    final ac = factors.skip(1).toList(growable: false);

    final buffer = StringBuffer()
      ..write(_encode83((cx - 1) + (cy - 1) * 9, 1));

    var maximumValue = 1.0;
    if (ac.isEmpty) {
      buffer.write(_encode83(0, 1));
    } else {
      var actualMaximum = 0.0;
      for (final component in ac) {
        for (final channel in component) {
          final magnitude = channel.abs();
          if (magnitude > actualMaximum) actualMaximum = magnitude;
        }
      }
      final quantised =
          math.max(0, math.min(82, (actualMaximum * 166 - 0.5).floor()));
      maximumValue = (quantised + 1) / 166;
      buffer.write(_encode83(quantised, 1));
    }

    buffer.write(_encode83(_encodeDc(dc), 4));
    for (final component in ac) {
      buffer.write(_encode83(_encodeAc(component, maximumValue), 2));
    }
    return buffer.toString();
  }

  static img.Image _downsample(img.Image image) {
    final longEdge = math.max(image.width, image.height);
    if (longEdge <= sampleSize) return image;
    final scale = sampleSize / longEdge;
    return img.copyResize(
      image,
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }

  static double _srgbToLinear(double value) {
    final v = value.clamp(0.0, 1.0);
    if (v <= 0.04045) return v / 12.92;
    return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  /// The reference implementation adds 0.5 and then **truncates** (C's
  /// float→int conversion, JavaScript's `Math.trunc`). Rounding instead would
  /// push pure black to 1 and produce a hash that does not match any other
  /// encoder, so the truncation is deliberate.
  static int _linearToSrgb(double value) {
    final v = value.clamp(0.0, 1.0);
    if (v <= 0.0031308) return (v * 12.92 * 255 + 0.5).floor();
    return ((1.055 * math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5).floor();
  }

  static int _encodeDc(List<double> dc) =>
      (_linearToSrgb(dc[0]) << 16) +
      (_linearToSrgb(dc[1]) << 8) +
      _linearToSrgb(dc[2]);

  static int _encodeAc(List<double> ac, double maximumValue) {
    int quantise(double value) => math.max(
          0,
          math.min(18, (_signedPow(value / maximumValue, 0.5) * 9 + 9.5).floor()),
        );
    return quantise(ac[0]) * 19 * 19 + quantise(ac[1]) * 19 + quantise(ac[2]);
  }

  static double _signedPow(double value, double exponent) => value < 0
      ? -math.pow(-value, exponent).toDouble()
      : math.pow(value, exponent).toDouble();

  static String _encode83(int value, int length) {
    final out = StringBuffer();
    for (var i = 1; i <= length; i++) {
      final digit = (value ~/ math.pow(83, length - i).toInt()) % 83;
      out.write(alphabet[digit]);
    }
    return out.toString();
  }
}
