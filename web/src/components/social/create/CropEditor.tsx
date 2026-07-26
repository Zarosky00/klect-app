'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { layout } from '@/design/tokens.g';
import { cn } from '@/lib/cn';
import {
  MIN_CROP_EDGE,
  drawTurnedImage,
  moveBy,
  pinchRect,
  resizeFromCorner,
  scaleAbout,
  turnedSize,
  type CropCorner,
  type CropRect,
  type DrawableImage,
} from './crop';

/**
 * The canvas crop editor — the web twin of mobile's `CropEditor` in
 * `frame/crop_frame.dart`, translated to pointer events:
 *
 *  · drag inside the frame moves it;
 *  · drag a corner handle resizes it (respecting the locked aspect);
 *  · two-pointer pinch scales it about its centre;
 *  · trackpad pinch / mouse wheel zooms the frame;
 *  · arrow keys nudge it (the affordance a pointer-only editor forgets).
 *
 * Controlled: the parent owns the crop rect (turned-frame pixel space) and the
 * quarter turns; this component renders and translates gestures into new rects
 * via `onCropChange`.
 */
export interface CropEditorProps {
  image: DrawableImage;
  /** Oriented source width, before any quarter turns. */
  baseWidth: number;
  /** Oriented source height, before any quarter turns. */
  baseHeight: number;
  quarterTurns: number;
  /** Current crop in turned-frame pixels; null means the full frame. */
  crop: CropRect | null;
  /** Width/height ratio the frame must keep, or null for free-form. */
  lockedAspect: number | null;
  onCropChange: (rect: CropRect) => void;
  className?: string;
}

/** Display-px radius inside which a pointer grabs a corner handle. */
const HANDLE_HIT_RADIUS = layout.tapTargetMin / 2;
/** Drawn radius of a corner handle, display px. */
const HANDLE_RADIUS = 6;

interface Gesture {
  mode: 'move' | 'pinch' | CropCorner;
  startRect: CropRect;
  /** Image-px focal point at gesture start. */
  startFocal: { x: number; y: number };
  /** Display-px pointer distance at pinch start. */
  startDist: number;
}

export function CropEditor({
  image,
  baseWidth,
  baseHeight,
  quarterTurns,
  crop,
  lockedAspect,
  onCropChange,
  className,
}: CropEditorProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [box, setBox] = useState({ width: 0, height: 0 });
  const [dragging, setDragging] = useState(false);

  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const gesture = useRef<Gesture | null>(null);

  const { width: tw, height: th } = turnedSize(baseWidth, baseHeight, quarterTurns);
  const scale = tw > 0 && th > 0 ? Math.min(box.width / tw, box.height / th) : 0;
  const dw = tw * scale;
  const dh = th * scale;
  const rect: CropRect = useMemo(
    () => crop ?? { left: 0, top: 0, width: tw, height: th },
    [crop, tw, th],
  );
  const minEdge = scale > 0 ? Math.max(MIN_CROP_EDGE, layout.tapTargetMin / scale) : MIN_CROP_EDGE;

  /** Everything the native wheel listener needs, without rebinding it. */
  const live = useRef({ rect, lockedAspect, tw, th, minEdge, onCropChange });
  live.current = { rect, lockedAspect, tw, th, minEdge, onCropChange };

  /* ── layout ─────────────────────────────────────────────────────────────── */

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const measure = () => {
      const r = el.getBoundingClientRect();
      setBox((current) =>
        current.width === r.width && current.height === r.height
          ? current
          : { width: r.width, height: r.height },
      );
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  /* ── wheel zoom (native listener so preventDefault actually works) ──────── */

  useEffect(() => {
    const el = canvasRef.current;
    if (!el) return;
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      const state = live.current;
      // Trackpad pinch arrives as ctrl+wheel with small deltas — give it a
      // stronger response than a plain scroll wheel.
      const factor = Math.exp(-event.deltaY * (event.ctrlKey ? 0.01 : 0.002));
      state.onCropChange(
        scaleAbout(state.rect, factor, state.lockedAspect, state.tw, state.th, state.minEdge),
      );
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);

  /* ── pointer gestures ───────────────────────────────────────────────────── */

  const localPoint = useCallback((event: React.PointerEvent): { x: number; y: number } => {
    const el = canvasRef.current;
    if (!el) return { x: 0, y: 0 };
    const r = el.getBoundingClientRect();
    return { x: event.clientX - r.left, y: event.clientY - r.top };
  }, []);

  const hitTest = useCallback(
    (point: { x: number; y: number }): 'move' | CropCorner => {
      const corners: Array<[CropCorner, number, number]> = [
        ['tl', rect.left, rect.top],
        ['tr', rect.left + rect.width, rect.top],
        ['bl', rect.left, rect.top + rect.height],
        ['br', rect.left + rect.width, rect.top + rect.height],
      ];
      for (const [corner, cx, cy] of corners) {
        const dx = cx * scale - point.x;
        const dy = cy * scale - point.y;
        if (Math.hypot(dx, dy) <= HANDLE_HIT_RADIUS) return corner;
      }
      return 'move';
    },
    [rect, scale],
  );

  const onPointerDown = useCallback(
    (event: React.PointerEvent) => {
      if (scale <= 0) return;
      event.currentTarget.setPointerCapture(event.pointerId);
      const point = localPoint(event);
      pointers.current.set(event.pointerId, point);

      if (pointers.current.size === 2) {
        const [a, b] = [...pointers.current.values()];
        if (!a || !b) return;
        gesture.current = {
          mode: 'pinch',
          startRect: rect,
          startFocal: { x: (a.x + b.x) / 2 / scale, y: (a.y + b.y) / 2 / scale },
          startDist: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)),
        };
      } else {
        gesture.current = {
          mode: hitTest(point),
          startRect: rect,
          startFocal: { x: point.x / scale, y: point.y / scale },
          startDist: 0,
        };
      }
      setDragging(true);
    },
    [hitTest, localPoint, rect, scale],
  );

  const onPointerMove = useCallback(
    (event: React.PointerEvent) => {
      if (!pointers.current.has(event.pointerId)) return;
      const point = localPoint(event);
      pointers.current.set(event.pointerId, point);
      const g = gesture.current;
      if (!g || scale <= 0) return;

      let next: CropRect;
      if (g.mode === 'pinch') {
        if (pointers.current.size < 2) return;
        const [a, b] = [...pointers.current.values()];
        if (!a || !b) return;
        const factor = Math.hypot(a.x - b.x, a.y - b.y) / g.startDist;
        const focal = { x: (a.x + b.x) / 2 / scale, y: (a.y + b.y) / 2 / scale };
        next = pinchRect(
          g.startRect,
          factor,
          focal.x - g.startFocal.x,
          focal.y - g.startFocal.y,
          lockedAspect,
          tw,
          th,
          minEdge,
        );
      } else {
        const dx = point.x / scale - g.startFocal.x;
        const dy = point.y / scale - g.startFocal.y;
        next =
          g.mode === 'move'
            ? moveBy(g.startRect, dx, dy, tw, th)
            : resizeFromCorner(g.startRect, g.mode, dx, dy, lockedAspect, tw, th, minEdge);
      }
      onCropChange(next);
    },
    [localPoint, lockedAspect, minEdge, onCropChange, scale, th, tw],
  );

  const onPointerEnd = useCallback((event: React.PointerEvent) => {
    pointers.current.delete(event.pointerId);
    if (pointers.current.size === 0 || gesture.current?.mode === 'pinch') {
      gesture.current = null;
      pointers.current.clear();
      setDragging(false);
    }
  }, []);

  const onKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      const step = event.shiftKey ? 32 : 8;
      const moves: Record<string, [number, number]> = {
        ArrowLeft: [-step, 0],
        ArrowRight: [step, 0],
        ArrowUp: [0, -step],
        ArrowDown: [0, step],
      };
      const delta = moves[event.key];
      if (!delta) return;
      event.preventDefault();
      onCropChange(moveBy(rect, delta[0], delta[1], tw, th));
    },
    [onCropChange, rect, th, tw],
  );

  /* ── drawing ────────────────────────────────────────────────────────────── */

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || scale <= 0 || dw <= 0 || dh <= 0) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(dw * dpr));
    canvas.height = Math.max(1, Math.round(dh * dpr));
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Colours come from the theme's CSS custom properties, never literals.
    const styles = getComputedStyle(canvas);
    const line = styles.getPropertyValue('--k-text-primary').trim() || styles.color;
    const scrim = styles.getPropertyValue('--k-surface-scrim').trim() || styles.color;

    // The photo, in turned-frame space.
    ctx.setTransform(dpr * scale, 0, 0, dpr * scale, 0, 0);
    drawTurnedImage(ctx, image, quarterTurns, tw, th);

    // The overlay, in display space.
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const x = rect.left * scale;
    const y = rect.top * scale;
    const w = rect.width * scale;
    const h = rect.height * scale;

    // Darken everything outside the frame.
    ctx.beginPath();
    ctx.rect(0, 0, dw, dh);
    ctx.rect(x, y, w, h);
    ctx.fillStyle = scrim;
    ctx.fill('evenodd');

    // The frame itself.
    ctx.strokeStyle = line;
    ctx.lineWidth = 2;
    ctx.strokeRect(x, y, w, h);

    // Rule-of-thirds grid, only while a gesture is live.
    if (dragging) {
      ctx.save();
      ctx.globalAlpha = 0.5;
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let i = 1; i < 3; i += 1) {
        const gx = x + (w * i) / 3;
        const gy = y + (h * i) / 3;
        ctx.moveTo(gx, y);
        ctx.lineTo(gx, y + h);
        ctx.moveTo(x, gy);
        ctx.lineTo(x + w, gy);
      }
      ctx.stroke();
      ctx.restore();
    }

    // Corner handles.
    ctx.fillStyle = line;
    for (const [cx, cy] of [
      [x, y],
      [x + w, y],
      [x, y + h],
      [x + w, y + h],
    ] as const) {
      ctx.beginPath();
      ctx.arc(cx, cy, HANDLE_RADIUS, 0, Math.PI * 2);
      ctx.fill();
    }
  }, [image, quarterTurns, rect, scale, dw, dh, tw, th, dragging]);

  return (
    <div
      ref={containerRef}
      className={cn('relative grid size-full place-items-center', className)}
    >
      <canvas
        ref={canvasRef}
        role="application"
        aria-label="Crop editor — drag to move the frame, drag a corner to resize, pinch or scroll to zoom, arrow keys to nudge"
        tabIndex={0}
        style={{ width: dw, height: dh }}
        className="focus-ring max-h-full max-w-full cursor-move touch-none select-none"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
        onKeyDown={onKeyDown}
      />
    </div>
  );
}
