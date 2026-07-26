/**
 * FRAME-beat crop math — the web twin of mobile's
 * `lib/features/create/frame/crop_frame.dart` + `media/image_pipeline.dart`.
 *
 * All rects live in **turned-frame pixel space**: the photo's oriented pixels
 * after the quarter turns are applied. That is the same space the mobile
 * pipeline crops in, so a draft framed on either client means the same thing.
 *
 * Pure functions only (plus two canvas draw helpers) — no React, no DOM state.
 */
import { aspect as aspectTokens } from '@/design/tokens.g';

export interface CropRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** Smallest crop edge, in source pixels — mirrors `ImagePipeline.minCropEdge`. */
export const MIN_CROP_EDGE = 8;

/** Grid clamp bounds — a Surf card can never be shaped outside these. */
export const GRID_ASPECT_MIN = aspectTokens.gridMin;
export const GRID_ASPECT_MAX = aspectTokens.gridMax;

export type CropPresetId = 'original' | 'tall' | 'square' | 'wide';

export interface CropPreset {
  id: CropPresetId;
  label: string;
  /** Locked width/height ratio, or null for a free crop. */
  aspect: number | null;
}

/**
 * Tall and Wide are the masonry grid's own clamp bounds — cropping to a preset
 * is literally choosing the shape of the card Surf will render.
 */
export const CROP_PRESETS: readonly CropPreset[] = [
  { id: 'original', label: 'Original', aspect: null },
  { id: 'tall', label: 'Tall', aspect: aspectTokens.gridMin },
  { id: 'square', label: 'Square', aspect: aspectTokens.cover },
  { id: 'wide', label: 'Wide', aspect: aspectTokens.gridMax },
] as const;

export function presetById(id: CropPresetId): CropPreset {
  return CROP_PRESETS.find((preset) => preset.id === id) ?? CROP_PRESETS[0]!;
}

/** Normalises quarter turns into 0..3. */
export function normalizeTurns(turns: number): number {
  return ((turns % 4) + 4) % 4;
}

/** Turned-frame dimensions for a photo of `baseWidth`×`baseHeight`. */
export function turnedSize(
  baseWidth: number,
  baseHeight: number,
  quarterTurns: number,
): { width: number; height: number } {
  return normalizeTurns(quarterTurns) % 2 === 1
    ? { width: baseHeight, height: baseWidth }
    : { width: baseWidth, height: baseHeight };
}

/** The largest rect of `ratio` (width/height) that fits centred in the frame. */
export function maxCenteredCrop(width: number, height: number, ratio: number): CropRect {
  let w = width;
  let h = w / ratio;
  if (h > height) {
    h = height;
    w = h * ratio;
  }
  return { left: (width - w) / 2, top: (height - h) / 2, width: w, height: h };
}

const clamp = (value: number, lo: number, hi: number): number =>
  Math.min(Math.max(value, lo), hi);

/** Pulls a rect fully inside the `tw`×`th` frame, shrinking only if it must. */
export function clampInside(rect: CropRect, tw: number, th: number): CropRect {
  const width = clamp(rect.width, 1, tw);
  const height = clamp(rect.height, 1, th);
  return {
    left: clamp(rect.left, 0, tw - width),
    top: clamp(rect.top, 0, th - height),
    width,
    height,
  };
}

function fromCenter(cx: number, cy: number, width: number, height: number): CropRect {
  return { left: cx - width / 2, top: cy - height / 2, width, height };
}

/**
 * The biggest rect of `ratio` that still fits, sized as close to `width` as
 * bounds allow, centred on (`cx`,`cy`) then nudged inside — mobile's
 * `_aspectRect`.
 */
export function aspectRect(
  cx: number,
  cy: number,
  width: number,
  ratio: number,
  tw: number,
  th: number,
  minEdge: number,
): CropRect {
  const minW = Math.max(minEdge, minEdge * ratio);
  const maxW = Math.min(tw, th * ratio);
  const w = clamp(width, Math.min(minW, maxW), maxW);
  return clampInside(fromCenter(cx, cy, w, w / ratio), tw, th);
}

/** Drag-inside-the-frame: shift, then clamp. */
export function moveBy(start: CropRect, dx: number, dy: number, tw: number, th: number): CropRect {
  return clampInside({ ...start, left: start.left + dx, top: start.top + dy }, tw, th);
}

/**
 * Two-finger pinch: scale about the rect's centre shifted by the focal-point
 * drift (`dx`,`dy`), respecting a locked aspect — mobile's pinch branch.
 */
export function pinchRect(
  start: CropRect,
  factor: number,
  dx: number,
  dy: number,
  ratio: number | null,
  tw: number,
  th: number,
  minEdge: number,
): CropRect {
  const cx = start.left + start.width / 2 + dx;
  const cy = start.top + start.height / 2 + dy;
  if (ratio !== null) {
    return aspectRect(cx, cy, start.width * factor, ratio, tw, th, minEdge);
  }
  const w = clamp(start.width * factor, Math.min(minEdge, tw), tw);
  const h = clamp(start.height * factor, Math.min(minEdge, th), th);
  return clampInside(fromCenter(cx, cy, w, h), tw, th);
}

/** Wheel/trackpad zoom: scale about the rect's own centre. */
export function scaleAbout(
  start: CropRect,
  factor: number,
  ratio: number | null,
  tw: number,
  th: number,
  minEdge: number,
): CropRect {
  return pinchRect(start, factor, 0, 0, ratio, tw, th, minEdge);
}

export type CropCorner = 'tl' | 'tr' | 'bl' | 'br';

/**
 * Corner-handle resize: the dragged corner follows the pointer; the opposite
 * corner is the anchor and never moves — mobile's `_resizeFromCorner`.
 */
export function resizeFromCorner(
  start: CropRect,
  corner: CropCorner,
  dx: number,
  dy: number,
  ratio: number | null,
  tw: number,
  th: number,
  minEdge: number,
): CropRect {
  const right = start.left + start.width;
  const bottom = start.top + start.height;
  const anchor = {
    tl: { x: right, y: bottom },
    tr: { x: start.left, y: bottom },
    bl: { x: right, y: start.top },
    br: { x: start.left, y: start.top },
  }[corner];
  const draggedStart = {
    tl: { x: start.left, y: start.top },
    tr: { x: right, y: start.top },
    bl: { x: start.left, y: bottom },
    br: { x: right, y: bottom },
  }[corner];
  const dragged = { x: draggedStart.x + dx, y: draggedStart.y + dy };

  const growsLeft = dragged.x < anchor.x;
  const growsUp = dragged.y < anchor.y;
  const maxW = growsLeft ? anchor.x : tw - anchor.x;
  const maxH = growsUp ? anchor.y : th - anchor.y;

  let w = Math.abs(anchor.x - dragged.x);
  let h = Math.abs(anchor.y - dragged.y);

  if (ratio !== null) {
    // Width leads, height follows the lock; then both are pulled back inside
    // whichever bound bites first.
    const lower = Math.min(Math.max(minEdge, minEdge * ratio), maxW);
    w = clamp(w, lower, maxW);
    h = w / ratio;
    if (h > maxH) {
      h = maxH;
      w = h * ratio;
    }
  } else {
    w = clamp(w, Math.min(minEdge, maxW), maxW);
    h = clamp(h, Math.min(minEdge, maxH), maxH);
  }

  return clampInside(
    {
      left: growsLeft ? anchor.x - w : anchor.x,
      top: growsUp ? anchor.y - h : anchor.y,
      width: w,
      height: h,
    },
    tw,
    th,
  );
}

/**
 * Rotates a crop rect a quarter turn clockwise inside a frame whose pre-turn
 * height was `height` — mobile's `ImagePipeline.rotateCropRect`, so an
 * existing crop follows the photo instead of snapping back to full frame.
 */
export function rotateCropRect(rect: CropRect, height: number): CropRect {
  return {
    left: height - rect.top - rect.height,
    top: rect.left,
    width: rect.height,
    height: rect.width,
  };
}

/** width/height of the crop (or the full turned frame when crop is null). */
export function cropAspect(crop: CropRect | null, tw: number, th: number): number {
  const w = crop ? crop.width : tw;
  const h = crop ? crop.height : th;
  return h <= 0 ? 1 : w / h;
}

/** The shape Surf will actually draw — extreme ratios are clamped. */
export function clampGridAspect(ratio: number): number {
  return clamp(ratio, GRID_ASPECT_MIN, GRID_ASPECT_MAX);
}

/* ── canvas drawing ───────────────────────────────────────────────────────── */

export type DrawableImage = HTMLImageElement | ImageBitmap | HTMLCanvasElement;

/**
 * Draws the oriented source into a context whose coordinate space is the
 * turned frame (0,0)–(tw,th), applying the quarter turns.
 */
export function drawTurnedImage(
  ctx: CanvasRenderingContext2D,
  image: DrawableImage,
  quarterTurns: number,
  tw: number,
  th: number,
): void {
  const turns = normalizeTurns(quarterTurns);
  ctx.save();
  switch (turns) {
    case 1:
      ctx.translate(tw, 0);
      ctx.rotate(Math.PI / 2);
      // Odd turns: the source's own width runs along the turned height.
      ctx.drawImage(image, 0, 0, th, tw);
      break;
    case 2:
      ctx.translate(tw, th);
      ctx.rotate(Math.PI);
      ctx.drawImage(image, 0, 0, tw, th);
      break;
    case 3:
      ctx.translate(0, th);
      ctx.rotate(-Math.PI / 2);
      ctx.drawImage(image, 0, 0, th, tw);
      break;
    default:
      ctx.drawImage(image, 0, 0, tw, th);
  }
  ctx.restore();
}

/**
 * Cover-fit render of the current crop into a `viewW`×`viewH` context — the
 * web twin of mobile's `CroppedPhoto`: the full turned frame is drawn scaled
 * and offset so exactly the cropped region fills the viewport.
 */
export function drawCroppedCover(
  ctx: CanvasRenderingContext2D,
  image: DrawableImage,
  quarterTurns: number,
  baseWidth: number,
  baseHeight: number,
  crop: CropRect | null,
  viewW: number,
  viewH: number,
): void {
  const { width: tw, height: th } = turnedSize(baseWidth, baseHeight, quarterTurns);
  const rect = crop ?? { left: 0, top: 0, width: tw, height: th };
  if (rect.width <= 0 || rect.height <= 0 || viewW <= 0 || viewH <= 0) return;
  const scale = Math.max(viewW / rect.width, viewH / rect.height);
  ctx.save();
  ctx.translate(
    viewW / 2 - (rect.left + rect.width / 2) * scale,
    viewH / 2 - (rect.top + rect.height / 2) * scale,
  );
  ctx.scale(scale, scale);
  drawTurnedImage(ctx, image, quarterTurns, tw, th);
  ctx.restore();
}
