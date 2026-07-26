// Renders the KLECT app-icon source PNGs — the production path for the
// "K + shelf" mark. Not a scratch file: run it whenever the mark or the
// brand tokens change, then regenerate the platform icons:
//
//   flutter test test/tools/render_app_icon_test.dart
//   dart run flutter_launcher_icons
//
// The mark: a single-story grotesque K whose lower leg flattens into a
// shelf plane — the product in one glyph (collections live on shelves).
// Oxblood on noir, straight from the generated design tokens; a raw hex
// here would be a bug (AGENTS.md rule 5).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/design/tokens.g.dart';

const int _size = 1024;

/// Android adaptive icons mask the outer third away; content must sit inside
/// the central safe circle (66/108 of the canvas). flutter_launcher_icons
/// additionally wraps the foreground in a 16% `<inset>`, so the source glyph
/// is drawn larger here: 0.56 × 0.68 ≈ 0.38 of the canvas — glyph box
/// half-diagonal ≈ 29dp, inside the 33dp safe radius.
const double _adaptiveGlyphScale = 0.56;

/// The legacy / iOS icon shows the full square, so the glyph breathes larger.
const double _fullGlyphScale = 0.54;

const KlectColors _brand = KlectColorsDark();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the K + shelf icon source set', () async {
    final outDir = Directory('assets/icon');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    // Adaptive foreground: glyph only, transparent, safe-zone padded.
    final foreground = await _renderLayer(
      glyphColor: _brand.accentDefault,
      glyphScale: _adaptiveGlyphScale,
    );
    // Adaptive background: solid noir.
    final background = await _renderLayer(background: _brand.bgBase);
    // Android 13+ themed icon: alpha-only glyph, the system tints it.
    final monochrome = await _renderLayer(
      glyphColor: _brand.textPrimary,
      glyphScale: _adaptiveGlyphScale,
    );
    // Legacy Android mipmaps + the iOS set: glyph on noir, full square.
    final icon = await _renderLayer(
      background: _brand.bgBase,
      glyphColor: _brand.accentDefault,
      glyphScale: _fullGlyphScale,
    );

    final layers = <String, Uint8List>{
      'foreground.png': foreground,
      'background.png': background,
      'monochrome.png': monochrome,
      'icon.png': icon,
    };
    layers.forEach((name, bytes) {
      // A 1024² PNG that came out this small would be an empty canvas.
      expect(bytes.length, greaterThan(1000), reason: '$name is trivial');
      expect(
        bytes.sublist(0, 8),
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        reason: '$name is not a PNG',
      );
      File('${outDir.path}/$name').writeAsBytesSync(bytes);
    });
  });
}

Future<Uint8List> _renderLayer({
  Color? background,
  Color? glyphColor,
  double glyphScale = _adaptiveGlyphScale,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final side = _size.toDouble();

  if (background != null) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()..color = background,
    );
  }
  if (glyphColor != null) {
    final box = side * glyphScale;
    _paintKShelf(
      canvas,
      Rect.fromLTWH((side - box) / 2, (side - box) / 2, box, box),
      glyphColor,
    );
  }

  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Paints the mark into [box]. Coordinates are unit-square fractions of the
/// box so the glyph scales losslessly with the layer it is drawn on.
void _paintKShelf(Canvas canvas, Rect box, Color color) {
  Offset at(double x, double y) =>
      Offset(box.left + x * box.width, box.top + y * box.height);

  // Stroke weight of the grotesque: bold enough to survive a 48 px mipmap.
  final w = box.width * 0.18;
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.butt
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  const joinY = 0.52; // where arm and leg leave the stem
  const shelfY = 1 - 0.18 / 2; // shelf centreline hugs the bottom edge
  const stemX = 0.18 / 2; // stem centreline hugs the left edge

  final path = Path()
    // The shelf plane — full width, the ground everything stands on.
    ..moveTo(at(0, shelfY).dx, at(0, shelfY).dy)
    ..lineTo(at(1, shelfY).dx, at(1, shelfY).dy)
    // The stem, top edge down onto the shelf.
    ..moveTo(at(stemX, 0).dx, at(stemX, 0).dy)
    ..lineTo(at(stemX, shelfY).dx, at(stemX, shelfY).dy)
    // The upper arm.
    ..moveTo(at(stemX, joinY).dx, at(stemX, joinY).dy)
    ..lineTo(at(0.88, 0.05).dx, at(0.88, 0.05).dy)
    // The lower leg: a straight descent that flattens into the shelf —
    // the quadratic's control point keeps the entry tangent continuous and
    // the exit tangent horizontal.
    ..moveTo(at(stemX, joinY).dx, at(stemX, joinY).dy)
    ..lineTo(at(0.52, 0.81).dx, at(0.52, 0.81).dy)
    ..quadraticBezierTo(
      at(0.66, 0.905).dx,
      at(0.66, 0.905).dy,
      at(0.86, shelfY).dx,
      at(0.86, shelfY).dy,
    );

  canvas.drawPath(path, paint);
}
