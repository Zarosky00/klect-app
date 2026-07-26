import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../design/theme.dart';
import '../media/image_pipeline.dart';

/// One decode budget shared by every FRAME surface — the editor, the thumb
/// rail and the masonry preview all pass the same `cacheWidth`, so the engine
/// decodes each source photo exactly once and serves the rest from cache.
const int kFrameDecodeWidth = 1200;

/// The aspect presets offered in the FRAME beat.
///
/// Tall and Wide are the masonry grid's own clamp bounds ([Aspect.gridMin]
/// and [Aspect.gridMax]) — cropping to a preset is literally choosing the
/// shape of the card Surf will render.
enum CropPreset {
  /// The photo's own shape — no crop unless the user draws one.
  original(null, 'Original'),

  /// Portrait, the tallest card the grid draws.
  tall(Aspect.gridMin, 'Tall'),

  /// A perfect square.
  square(Aspect.cover, 'Square'),

  /// Landscape, the widest card the grid draws.
  wide(Aspect.gridMax, 'Wide');

  const CropPreset(this.aspect, this.label);

  /// Locked width/height ratio, or null for a free crop.
  final double? aspect;

  /// Chip label.
  final String label;
}

/// The largest rect of [aspect] (width/height) that fits centred in a
/// [width]×[height] frame.
Rect maxCenteredCrop(double width, double height, double aspect) {
  var w = width;
  var h = w / aspect;
  if (h > height) {
    h = height;
    w = h * aspect;
  }
  return Rect.fromLTWH((width - w) / 2, (height - h) / 2, w, h);
}

/// Renders the current crop of a photo live — no re-encode, no isolate: the
/// full frame is drawn scaled and offset so exactly the cropped region fills
/// the viewport (cover fit), and everything else is clipped away.
///
/// Give it bounded constraints (an [AspectRatio] or a sized box).
class CroppedPhoto extends StatelessWidget {
  /// Creates a live crop render.
  const CroppedPhoto({
    required this.bytes,
    required this.baseWidth,
    required this.baseHeight,
    required this.quarterTurns,
    required this.cropRect,
    super.key,
  });

  /// The original picked file's bytes. Flutter bakes EXIF orientation when
  /// decoding, so what renders is the oriented frame.
  final Uint8List bytes;

  /// Oriented source width, before any quarter turns.
  final int baseWidth;

  /// Oriented source height, before any quarter turns.
  final int baseHeight;

  /// Clockwise 90° rotations.
  final int quarterTurns;

  /// Crop in turned-frame pixels; null renders the full frame.
  final Rect? cropRect;

  @override
  Widget build(BuildContext context) {
    final turns = ((quarterTurns % 4) + 4) % 4;
    final tw = (turns.isOdd ? baseHeight : baseWidth).toDouble();
    final th = (turns.isOdd ? baseWidth : baseHeight).toDouble();
    final crop = cropRect ?? Rect.fromLTWH(0, 0, tw, th);

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewW = constraints.maxWidth;
          final viewH = constraints.maxHeight;
          if (!viewW.isFinite || !viewH.isFinite || crop.isEmpty) {
            return const SizedBox.shrink();
          }
          final scale = math.max(viewW / crop.width, viewH / crop.height);
          final left = viewW / 2 - crop.center.dx * scale;
          final top = viewH / 2 - crop.center.dy * scale;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: left,
                top: top,
                width: tw * scale,
                height: th * scale,
                child: RotatedBox(
                  quarterTurns: turns,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    cacheWidth: math.min(kFrameDecodeWidth, baseWidth),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Which part of the crop frame a drag grabbed.
enum _DragMode { move, pinch, topLeft, topRight, bottomLeft, bottomRight }

/// The pinch/drag crop editor — pure Flutter, no native plugins.
///
/// Controlled: the parent owns the crop rect (turned-frame pixel space) and
/// the quarter turns; this widget renders the photo with the frame overlay
/// and translates gestures into new rects via [onCropChanged].
///
/// Gestures:
///  * drag inside the frame moves it;
///  * drag a corner resizes it (respecting the locked aspect, when one is
///    set);
///  * pinch anywhere scales it about its centre.
class CropEditor extends StatefulWidget {
  /// Creates the editor.
  const CropEditor({
    required this.bytes,
    required this.baseWidth,
    required this.baseHeight,
    required this.quarterTurns,
    required this.cropRect,
    required this.lockedAspect,
    required this.onCropChanged,
    super.key,
  });

  /// Original picked bytes — see [CroppedPhoto.bytes].
  final Uint8List bytes;

  /// Oriented source width, before any quarter turns.
  final int baseWidth;

  /// Oriented source height, before any quarter turns.
  final int baseHeight;

  /// Clockwise 90° rotations currently applied.
  final int quarterTurns;

  /// Current crop in turned-frame pixels; null means the full frame.
  final Rect? cropRect;

  /// Width/height ratio the frame must keep, or null for free-form.
  final double? lockedAspect;

  /// Fired continuously while the user adjusts the frame.
  final ValueChanged<Rect> onCropChanged;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  _DragMode _mode = _DragMode.move;
  Rect _startRect = Rect.zero;
  Offset _startFocal = Offset.zero;
  bool _dragging = false;

  int get _turns => ((widget.quarterTurns % 4) + 4) % 4;
  double get _tw =>
      (_turns.isOdd ? widget.baseHeight : widget.baseWidth).toDouble();
  double get _th =>
      (_turns.isOdd ? widget.baseWidth : widget.baseHeight).toDouble();

  Rect get _rect => widget.cropRect ?? Rect.fromLTWH(0, 0, _tw, _th);

  /// Display px → image px factor for the current layout.
  double _scaleFor(BoxConstraints constraints) => math.min(
        constraints.maxWidth / _tw,
        constraints.maxHeight / _th,
      );

  double _minEdge(double scale) =>
      math.max(ImagePipeline.minCropEdge.toDouble(), Layout.tapTargetMin / scale);

  Rect _clampInside(Rect rect) {
    final w = rect.width.clamp(1.0, _tw).toDouble();
    final h = rect.height.clamp(1.0, _th).toDouble();
    final left = rect.left.clamp(0.0, _tw - w).toDouble();
    final top = rect.top.clamp(0.0, _th - h).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  /// The biggest rect of [aspect] that still fits, sized as close to
  /// [width] as bounds allow, centred on [center] then nudged inside.
  Rect _aspectRect(Offset center, double width, double aspect, double scale) {
    final minEdge = _minEdge(scale);
    final minW = math.max(minEdge, minEdge * aspect);
    final maxW = math.min(_tw, _th * aspect);
    final w = width.clamp(math.min(minW, maxW), maxW).toDouble();
    final h = w / aspect;
    return _clampInside(
      Rect.fromCenter(center: center, width: w, height: h),
    );
  }

  _DragMode _hitTest(Offset displayPoint, double scale) {
    final rect = _rect;
    final corners = <_DragMode, Offset>{
      _DragMode.topLeft: rect.topLeft,
      _DragMode.topRight: rect.topRight,
      _DragMode.bottomLeft: rect.bottomLeft,
      _DragMode.bottomRight: rect.bottomRight,
    };
    for (final entry in corners.entries) {
      if ((entry.value * scale - displayPoint).distance <=
          Layout.tapTargetMin / 2) {
        return entry.key;
      }
    }
    return _DragMode.move;
  }

  void _onScaleStart(ScaleStartDetails details, double scale) {
    _startRect = _rect;
    _startFocal = details.localFocalPoint / scale;
    _mode = details.pointerCount > 1
        ? _DragMode.pinch
        : _hitTest(details.localFocalPoint, scale);
    setState(() => _dragging = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double scale) {
    final focal = details.localFocalPoint / scale;
    final delta = focal - _startFocal;
    final aspect = widget.lockedAspect;
    final minEdge = _minEdge(scale);
    Rect next;

    if (_mode == _DragMode.pinch || details.pointerCount > 1) {
      final center = _startRect.center + delta;
      if (aspect != null) {
        next = _aspectRect(
          center,
          _startRect.width * details.scale,
          aspect,
          scale,
        );
      } else {
        final w = (_startRect.width * details.scale)
            .clamp(math.min(minEdge, _tw), _tw)
            .toDouble();
        final h = (_startRect.height * details.scale)
            .clamp(math.min(minEdge, _th), _th)
            .toDouble();
        next = _clampInside(
          Rect.fromCenter(center: center, width: w, height: h),
        );
      }
    } else if (_mode == _DragMode.move) {
      next = _clampInside(_startRect.shift(delta));
    } else {
      next = _resizeFromCorner(_mode, delta, aspect, minEdge);
    }

    widget.onCropChanged(next);
  }

  Rect _resizeFromCorner(
    _DragMode corner,
    Offset delta,
    double? aspect,
    double minEdge,
  ) {
    // The dragged corner follows the finger; the opposite corner is the
    // anchor and never moves.
    final anchor = switch (corner) {
      _DragMode.topLeft => _startRect.bottomRight,
      _DragMode.topRight => _startRect.bottomLeft,
      _DragMode.bottomLeft => _startRect.topRight,
      _DragMode.bottomRight => _startRect.topLeft,
      _ => _startRect.center,
    };
    final dragged = switch (corner) {
          _DragMode.topLeft => _startRect.topLeft,
          _DragMode.topRight => _startRect.topRight,
          _DragMode.bottomLeft => _startRect.bottomLeft,
          _DragMode.bottomRight => _startRect.bottomRight,
          _ => _startRect.center,
        } +
        delta;

    // Horizontal room between the anchor and the frame edge on the side the
    // finger is working, and the same vertically.
    final growsLeft = dragged.dx < anchor.dx;
    final growsUp = dragged.dy < anchor.dy;
    final maxW = growsLeft ? anchor.dx : _tw - anchor.dx;
    final maxH = growsUp ? anchor.dy : _th - anchor.dy;

    var w = (anchor.dx - dragged.dx).abs();
    var h = (anchor.dy - dragged.dy).abs();

    if (aspect != null) {
      // Width leads, height follows the lock; then both are pulled back
      // inside whichever bound bites first.
      final lower = math.min(math.max(minEdge, minEdge * aspect), maxW);
      w = w.clamp(lower, maxW).toDouble();
      h = w / aspect;
      if (h > maxH) {
        h = maxH;
        w = h * aspect;
      }
    } else {
      w = w.clamp(math.min(minEdge, maxW), maxW).toDouble();
      h = h.clamp(math.min(minEdge, maxH), maxH).toDouble();
    }

    final left = growsLeft ? anchor.dx - w : anchor.dx;
    final top = growsUp ? anchor.dy - h : anchor.dy;
    return _clampInside(Rect.fromLTWH(left, top, w, h));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = _scaleFor(constraints);
        if (!scale.isFinite || scale <= 0) return const SizedBox.shrink();
        final dw = _tw * scale;
        final dh = _th * scale;
        final display = Rect.fromLTWH(
          _rect.left * scale,
          _rect.top * scale,
          _rect.width * scale,
          _rect.height * scale,
        );

        return Center(
          child: SizedBox(
            width: dw,
            height: dh,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                RotatedBox(
                  quarterTurns: _turns,
                  child: Image.memory(
                    widget.bytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    cacheWidth: math.min(kFrameDecodeWidth, widget.baseWidth),
                  ),
                ),
                CustomPaint(
                  painter: _CropOverlayPainter(
                    crop: display,
                    scrim: colors.surfaceScrim,
                    line: colors.textPrimary,
                    showGrid: _dragging,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (details) => _onScaleStart(details, scale),
                  onScaleUpdate: (details) => _onScaleUpdate(details, scale),
                  onScaleEnd: (_) => setState(() => _dragging = false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.crop,
    required this.scrim,
    required this.line,
    required this.showGrid,
  });

  final Rect crop;
  final Color scrim;
  final Color line;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;

    // Darken everything outside the frame.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRect(crop);
    canvas.drawPath(outside, Paint()..color = scrim);

    // The frame itself.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Strokes.thick
      ..color = line;
    canvas.drawRect(crop, stroke);

    // Rule-of-thirds grid, only while a gesture is live.
    if (showGrid) {
      final thin = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Strokes.hairline
        ..color = line.withValues(alpha: Opacities.veil);
      for (var i = 1; i < 3; i++) {
        final x = crop.left + crop.width * i / 3;
        final y = crop.top + crop.height * i / 3;
        canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), thin);
        canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), thin);
      }
    }

    // Corner handles.
    final handle = Paint()..color = line;
    const radius = Space.s15;
    for (final corner in <Offset>[
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      canvas.drawCircle(corner, radius, handle);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      crop != oldDelegate.crop ||
      scrim != oldDelegate.scrim ||
      line != oldDelegate.line ||
      showGrid != oldDelegate.showGrid;
}
