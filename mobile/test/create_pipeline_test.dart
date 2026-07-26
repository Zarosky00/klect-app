import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:klect/features/create/media/image_pipeline.dart';

/// A 40×20 test card: left half red, right half blue, so a crop or a turn is
/// verifiable from the pixels that come back out.
img.Image _testCard() {
  final canvas = img.Image(width: 40, height: 20);
  img.fill(canvas, color: img.ColorRgb8(255, 0, 0));
  img.fillRect(
    canvas,
    x1: 20,
    y1: 0,
    x2: 39,
    y2: 19,
    color: img.ColorRgb8(0, 0, 255),
  );
  return canvas;
}

void main() {
  final png = img.encodePng(_testCard());

  group('ImagePipeline.prepare', () {
    test('no edits: full frame, source dims reported', () async {
      final prepared = await ImagePipeline.prepare(png);
      expect(prepared.width, 40);
      expect(prepared.height, 20);
      expect(prepared.sourceWidth, 40);
      expect(prepared.sourceHeight, 20);
      expect(prepared.blurhash, isNotEmpty);
    });

    test('crop happens in oriented space, dims follow', () async {
      final prepared = await ImagePipeline.prepare(
        png,
        cropRect: const Rect.fromLTWH(0, 0, 32, 20),
      );
      expect(prepared.width, 32);
      expect(prepared.height, 20);
      // Source dims still describe the uncropped frame — the FRAME editor
      // maps its gestures against these.
      expect(prepared.sourceWidth, 40);
      expect(prepared.sourceHeight, 20);
    });

    test('crop keeps the pixels it says it keeps', () async {
      // The right (blue) half only.
      final prepared = await ImagePipeline.prepare(
        png,
        cropRect: const Rect.fromLTWH(20, 0, 20, 20),
      );
      final out = img.decodeImage(prepared.bytes)!;
      final centre = out.getPixel(out.width ~/ 2, out.height ~/ 2);
      expect(centre.b, greaterThan(centre.r),
          reason: 'cropping the blue half must return blue pixels',);
    });

    test('quarter turn swaps dimensions clockwise', () async {
      final prepared = await ImagePipeline.prepare(png, quarterTurns: 1);
      expect(prepared.width, 20);
      expect(prepared.height, 40);
      // Clockwise: the left (red) half ends up as the TOP half.
      final out = img.decodeImage(prepared.bytes)!;
      final top = out.getPixel(out.width ~/ 2, 2);
      final bottom = out.getPixel(out.width ~/ 2, out.height - 3);
      expect(top.r, greaterThan(top.b));
      expect(bottom.b, greaterThan(bottom.r));
    });

    test('crop rect is interpreted post-turn', () async {
      // After one clockwise turn the frame is 20×40; the top 20×12 strip is
      // pure red (the old left half).
      final prepared = await ImagePipeline.prepare(
        png,
        quarterTurns: 1,
        cropRect: const Rect.fromLTWH(0, 0, 20, 12),
      );
      expect(prepared.width, 20);
      expect(prepared.height, 12);
      final out = img.decodeImage(prepared.bytes)!;
      final centre = out.getPixel(out.width ~/ 2, out.height ~/ 2);
      expect(centre.r, greaterThan(centre.b));
    });

    test('out-of-bounds crop is clamped, never thrown', () async {
      final prepared = await ImagePipeline.prepare(
        png,
        cropRect: const Rect.fromLTWH(-10, -10, 300, 300),
      );
      // Clamped to the full frame → treated as no crop at all.
      expect(prepared.width, 40);
      expect(prepared.height, 20);
    });
  });

  group('ImagePipeline.rotateCropRect', () {
    test('follows a clockwise quarter turn', () {
      // Frame 10×20, rect (2,3, 4×5). After a clockwise turn the frame is
      // 20×10 and the rect lands at (20-3-5, 2) with swapped sides.
      const rect = Rect.fromLTWH(2, 3, 4, 5);
      final turned = ImagePipeline.rotateCropRect(rect, height: 20);
      expect(turned, const Rect.fromLTWH(12, 2, 5, 4));
    });

    test('four turns come back home', () {
      const rect = Rect.fromLTWH(2, 3, 4, 5);
      var frameW = 10.0;
      var frameH = 20.0;
      var turned = rect;
      for (var i = 0; i < 4; i++) {
        turned = ImagePipeline.rotateCropRect(turned, height: frameH);
        final nextW = frameH;
        frameH = frameW;
        frameW = nextW;
      }
      expect(turned, rect);
    });
  });
}
