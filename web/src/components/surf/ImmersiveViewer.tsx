'use client';

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type WheelEvent as ReactWheelEvent,
} from 'react';
import Image from 'next/image';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { IconButton } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { Portal, useEscape, useLockBodyScroll } from '@/components/ui/overlay';
import { curve, duration, gesture, reducedTransition } from '@/design/motion';
import { getCloseup } from '@/lib/api';
import { cn } from '@/lib/cn';
import { isOptimizableImageSrc, mediaUrl } from '@/lib/storage';
import { useSession } from '@/providers/session-provider';
import {
  photosFromPayload,
  type ImmersivePhoto,
  type ImmersiveSource,
} from './immersive-source';

/**
 * The immersive fullscreen viewer — the double-tap half of the gesture
 * contract (DESIGN_SYSTEM §4).
 *
 * Pinch/wheel zoom, drag to pan, swipe or arrow keys between photos, Escape to
 * leave, and chrome that gets out of the way after a moment of stillness and
 * returns the instant you move.
 *
 * It opens on the cover you already have — zero perceived latency — and
 * upgrades to the entity's full photo set as soon as `get_closeup` lands. For a
 * collection or a subcollection the "photo set" is its children's covers, so a
 * double tap on a shelf sweeps through the shelf.
 *
 * Gesture transforms (pinch scale, pan, swipe drag) are written straight to
 * `element.style` through refs — never through React state — so a pinch is a
 * compositor-only update instead of a render per pointer event. State is
 * reserved for discrete changes: the photo index, chrome visibility, and
 * whether the image is zoomed at all (which flips cursor/behaviour).
 */

/** Zoom limits. Behavioural, not visual — no design token describes them. */
const MIN_SCALE = 1;
const MAX_SCALE = 4;
const DOUBLE_TAP_SCALE = 2.5;

/** "Chrome auto-hides after 2s" (§4), expressed against the duration ramp. */
const CHROME_IDLE_MS = duration.deliberate * 4;

export type { ImmersivePhoto, ImmersiveSource } from './immersive-source';
export { photosFromMedia } from './immersive-source';

interface Transform {
  scale: number;
  x: number;
  y: number;
}

const IDENTITY: Transform = { scale: MIN_SCALE, x: 0, y: 0 };

export interface ImmersiveViewerProps {
  source: ImmersiveSource | null;
  onClose: () => void;
}

export function ImmersiveViewer({ source, onClose }: ImmersiveViewerProps) {
  const open = source !== null;
  const { supabase } = useSession();
  const reduced = useReducedMotion();

  const [fetched, setFetched] = useState<ImmersivePhoto[] | null>(null);
  const [index, setIndex] = useState(0);
  /** Discrete zoom mode — flips only when the scale crosses 1. */
  const [zoomed, setZoomed] = useState(false);
  const [chrome, setChrome] = useState(true);

  const surfaceRef = useRef<HTMLDivElement | null>(null);
  const stripRef = useRef<HTMLDivElement | null>(null);
  const activeImageRef = useRef<HTMLImageElement | null>(null);
  /** The continuous gesture values live here, never in state. */
  const transformRef = useRef<Transform>(IDENTITY);
  const dragXRef = useRef(0);
  const indexRef = useRef(0);
  const stripEverApplied = useRef(false);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<{ distance: number; scale: number } | null>(null);
  const panStart = useRef<{ x: number; y: number; tx: number; ty: number } | null>(null);
  const swipeStart = useRef<{ x: number; t: number } | null>(null);
  const idleTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useLockBodyScroll(open);
  useEscape(open, onClose);

  /* ── direct style writers (compositor-speed, no re-render) ─────────────── */

  const applyStrip = useCallback(
    (animated: boolean) => {
      const strip = stripRef.current;
      if (!strip) return;
      strip.style.transition =
        animated && !reduced
          ? 'transform var(--k-dur-medium) var(--k-ease-emphasized)'
          : 'none';
      strip.style.transform = `translate3d(calc(${-indexRef.current * 100}% + ${dragXRef.current}px), 0, 0)`;
    },
    [reduced],
  );

  const applyImageTransform = useCallback(
    (animated: boolean) => {
      const img = activeImageRef.current;
      if (!img) return;
      const t = transformRef.current;
      img.style.transition =
        animated && !reduced
          ? 'transform var(--k-dur-base) var(--k-ease-standard)'
          : 'none';
      img.style.transform = `translate3d(${t.x}px, ${t.y}px, 0) scale(${t.scale})`;
      img.style.cursor = t.scale > MIN_SCALE ? 'grab' : 'zoom-in';
    },
    [reduced],
  );

  /** Callback ref for the active slide's <img>. React calls it with null for
      the outgoing element first, which is when its inline transform is wiped —
      a neighbour in the ±1 window must not keep a stale zoom. */
  const setActiveImage = useCallback(
    (element: HTMLImageElement | null) => {
      if (element === null) {
        const previous = activeImageRef.current;
        if (previous) {
          previous.style.transform = '';
          previous.style.transition = '';
          previous.style.cursor = '';
        }
        activeImageRef.current = null;
        return;
      }
      activeImageRef.current = element;
      applyImageTransform(false);
    },
    [applyImageTransform],
  );

  const resetTransform = useCallback(
    (animated = false) => {
      transformRef.current = IDENTITY;
      applyImageTransform(animated);
      setZoomed(false);
    },
    [applyImageTransform],
  );

  /* ── the photo set ──────────────────────────────────────────────────────── */

  const fallback = useMemo<ImmersivePhoto[]>(() => {
    if (!source) return [];
    return [
      {
        id: `${source.type}:${source.id}`,
        src: mediaUrl(source.cover.path),
        alt: source.title,
        width: source.cover.width,
        height: source.cover.height,
      },
    ];
  }, [source]);

  const photos = useMemo<ImmersivePhoto[]>(() => {
    if (source?.photos && source.photos.length > 0) return source.photos;
    if (fetched && fetched.length > 0) return fetched;
    return fallback;
  }, [fallback, fetched, source]);

  useEffect(() => {
    if (!source) {
      setFetched(null);
      return;
    }
    setIndex(Math.min(source.startIndex ?? 0, Math.max(photos.length - 1, 0)));
    resetTransform();
    // The caller already handed us the full set; no round trip needed.
    if (source.photos && source.photos.length > 0) return;

    let cancelled = false;
    void getCloseup(supabase, source.type, source.id)
      .then((payload) => {
        if (cancelled || !payload) return;
        const next = photosFromPayload(payload, source.title);
        if (next.length > 0) setFetched(next);
      })
      .catch(() => {
        // The cover is already on screen; a failed upgrade is not worth a toast.
      });
    return () => {
      cancelled = true;
    };
    // `photos.length` intentionally excluded: it changes as a *result* of this.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [source, supabase, resetTransform]);

  /** The strip position follows the discrete index. Animated except on the
      very first paint, where a startIndex > 0 must not sweep across the set. */
  useLayoutEffect(() => {
    if (!open) {
      stripEverApplied.current = false;
      return;
    }
    indexRef.current = index;
    dragXRef.current = 0;
    applyStrip(stripEverApplied.current);
    stripEverApplied.current = true;
  }, [applyStrip, index, open, photos.length]);

  /* ── chrome auto-hide ───────────────────────────────────────────────────── */

  const wakeChrome = useCallback(() => {
    setChrome(true);
    if (idleTimer.current) clearTimeout(idleTimer.current);
    idleTimer.current = setTimeout(() => setChrome(false), CHROME_IDLE_MS);
  }, []);

  useEffect(() => {
    if (!open) {
      if (idleTimer.current) clearTimeout(idleTimer.current);
      return;
    }
    wakeChrome();
    return () => {
      if (idleTimer.current) clearTimeout(idleTimer.current);
    };
  }, [open, wakeChrome]);

  /* ── navigation ─────────────────────────────────────────────────────────── */

  const go = useCallback(
    (delta: number) => {
      setIndex((current) => {
        const next = current + delta;
        if (next < 0 || next > photos.length - 1) return current;
        return next;
      });
      resetTransform();
      wakeChrome();
    },
    [photos.length, resetTransform, wakeChrome],
  );

  const zoomTo = useCallback(
    (scale: number, animated = true) => {
      const clamped = Math.min(Math.max(scale, MIN_SCALE), MAX_SCALE);
      transformRef.current =
        clamped === MIN_SCALE ? IDENTITY : { ...transformRef.current, scale: clamped };
      applyImageTransform(animated);
      setZoomed(clamped > MIN_SCALE);
    },
    [applyImageTransform],
  );

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      switch (event.key) {
        case 'ArrowRight':
          event.preventDefault();
          go(1);
          break;
        case 'ArrowLeft':
          event.preventDefault();
          go(-1);
          break;
        case 'Home':
          event.preventDefault();
          setIndex(0);
          resetTransform();
          break;
        case 'End':
          event.preventDefault();
          setIndex(photos.length - 1);
          resetTransform();
          break;
        case '+':
        case '=':
          event.preventDefault();
          zoomTo(transformRef.current.scale * 1.5);
          break;
        case '-':
          event.preventDefault();
          zoomTo(transformRef.current.scale / 1.5);
          break;
        case '0':
          event.preventDefault();
          resetTransform(true);
          break;
        default:
          return;
      }
      wakeChrome();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [go, open, photos.length, resetTransform, wakeChrome, zoomTo]);

  /* ── pointer gestures ───────────────────────────────────────────────────── */

  const distanceBetweenPointers = (): number => {
    const points = [...pointers.current.values()];
    const a = points[0];
    const b = points[1];
    if (!a || !b) return 0;
    return Math.hypot(a.x - b.x, a.y - b.y);
  };

  const onPointerDown = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      event.currentTarget.setPointerCapture(event.pointerId);
      pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
      wakeChrome();

      if (pointers.current.size === 2) {
        pinch.current = {
          distance: distanceBetweenPointers(),
          scale: transformRef.current.scale,
        };
        swipeStart.current = null;
        panStart.current = null;
        // A swipe that escalates into a pinch must not leave the strip
        // half-dragged.
        dragXRef.current = 0;
        applyStrip(false);
        return;
      }

      if (transformRef.current.scale > MIN_SCALE) {
        panStart.current = {
          x: event.clientX,
          y: event.clientY,
          tx: transformRef.current.x,
          ty: transformRef.current.y,
        };
      } else {
        swipeStart.current = { x: event.clientX, t: performance.now() };
      }
    },
    [applyStrip, wakeChrome],
  );

  const onPointerMove = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (!pointers.current.has(event.pointerId)) return;
      pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });

      if (pinch.current && pointers.current.size >= 2) {
        const distance = distanceBetweenPointers();
        if (pinch.current.distance > 0) {
          const ratio = distance / pinch.current.distance;
          zoomTo(pinch.current.scale * ratio, false);
        }
        return;
      }

      if (panStart.current) {
        const start = panStart.current;
        transformRef.current = {
          ...transformRef.current,
          x: start.tx + (event.clientX - start.x),
          y: start.ty + (event.clientY - start.y),
        };
        applyImageTransform(false);
        return;
      }

      if (swipeStart.current) {
        dragXRef.current = event.clientX - swipeStart.current.x;
        applyStrip(false);
      }
    },
    [applyImageTransform, applyStrip, zoomTo],
  );

  const endGesture = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      pointers.current.delete(event.pointerId);
      if (pointers.current.size < 2) pinch.current = null;

      if (panStart.current) {
        panStart.current = null;
        return;
      }

      const start = swipeStart.current;
      swipeStart.current = null;
      if (!start) return;

      const travelled = event.clientX - start.x;
      const elapsed = Math.max(performance.now() - start.t, 1);
      const velocity = (Math.abs(travelled) / elapsed) * 1000;
      const committed =
        Math.abs(travelled) > gesture.sheetDismissPx ||
        (velocity > gesture.sheetDismissVelocity && Math.abs(travelled) > gesture.slopPx);

      // Spring back (or on) immediately; if the swipe committed, `go` moves the
      // index and the layout effect animates the strip to its new home.
      dragXRef.current = 0;
      applyStrip(true);
      if (committed) go(travelled < 0 ? 1 : -1);
    },
    [applyStrip, go],
  );

  const onWheel = useCallback(
    (event: ReactWheelEvent<HTMLDivElement>) => {
      if (photos.length === 0) return;
      wakeChrome();
      const next = transformRef.current.scale * (event.deltaY < 0 ? 1.12 : 1 / 1.12);
      zoomTo(next);
    },
    [photos.length, wakeChrome, zoomTo],
  );

  const toggleZoom = useCallback(() => {
    zoomTo(transformRef.current.scale > MIN_SCALE ? MIN_SCALE : DOUBLE_TAP_SCALE);
    wakeChrome();
  }, [wakeChrome, zoomTo]);

  /* ── render ─────────────────────────────────────────────────────────────── */

  const current = photos[index];
  const total = photos.length;

  return (
    <Portal>
      <AnimatePresence>
        {open && source ? (
          <motion.div
            role="dialog"
            aria-modal="true"
            aria-label={`${source.title} — fullscreen viewer`}
            className="fixed inset-0 z-immersive select-none overflow-hidden bg-base"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={reduced ? reducedTransition : curve.fast}
          >
            <div
              ref={surfaceRef}
              className="absolute inset-0 touch-none"
              onPointerDown={onPointerDown}
              onPointerMove={onPointerMove}
              onPointerUp={endGesture}
              onPointerCancel={endGesture}
              onWheel={onWheel}
              onDoubleClick={toggleZoom}
              onMouseMove={wakeChrome}
            >
              {/* Transform is owned by `applyStrip`, not JSX — React must never
                  clobber a mid-gesture position on an unrelated re-render. */}
              <div ref={stripRef} className="flex h-full w-full">
                {photos.map((photo, position) => {
                  // Only a ±1 window is decoded, so memory stays flat on a long
                  // sweep through a big set (CHECKLIST D).
                  const near = Math.abs(position - index) <= 1;
                  const active = position === index;
                  return (
                    <div
                      key={photo.id}
                      className="grid h-full w-full flex-none place-items-center p-4"
                      aria-hidden={!active}
                    >
                      {near && photo.src ? (
                        <span className="relative block h-full w-full">
                          {/* Viewport-sized via `sizes`, so the viewer streams a
                              screen-fit rendition instead of the original.
                              Eager: the ±1 window sits off-viewport until the
                              swipe, exactly when it is too late to start. */}
                          <Image
                            ref={active ? setActiveImage : undefined}
                            src={photo.src}
                            alt={photo.alt}
                            fill
                            sizes="100vw"
                            loading="eager"
                            draggable={false}
                            unoptimized={!isOptimizableImageSrc(photo.src)}
                            className={cn(
                              'object-contain',
                              active && !zoomed && 'cursor-zoom-in',
                            )}
                          />
                        </span>
                      ) : (
                        <span className="size-full max-h-full rounded-lg bg-surface-1" />
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Chrome fades out first, and comes back the instant you move. */}
            <div
              className={cn(
                'pointer-events-none absolute inset-x-0 top-0 flex items-start gap-3 p-4',
                'bg-gradient-to-b from-scrim to-transparent',
                'transition-opacity dur-fast ease-standard',
                chrome ? 'opacity-100' : 'opacity-0',
              )}
            >
              <div className="pointer-events-auto">
                <IconButton
                  icon="close"
                  label="Close fullscreen"
                  variant="ghost"
                  onClick={onClose}
                  className="text-ink"
                />
              </div>
              <div className="min-w-0 flex-1 pt-2">
                <p className="truncate font-display text-title2 text-ink">{source.title}</p>
                {current?.alt && current.alt !== source.title ? (
                  <p className="truncate text-caption text-ink-2">{current.alt}</p>
                ) : null}
              </div>
              {total > 1 ? (
                <p className="tabular pt-3 text-label text-ink-2">
                  {index + 1} / {total}
                </p>
              ) : null}
            </div>

            {total > 1 ? (
              <>
                <div
                  className={cn(
                    'absolute left-2 top-1/2 -translate-y-1/2 transition-opacity dur-fast',
                    chrome ? 'opacity-100' : 'opacity-0',
                  )}
                >
                  <IconButton
                    icon="chevron-left"
                    label="Previous photo"
                    variant="ghost"
                    onClick={() => go(-1)}
                    disabled={index === 0}
                    className="rounded-full bg-glass text-ink"
                  />
                </div>
                <div
                  className={cn(
                    'absolute right-2 top-1/2 -translate-y-1/2 transition-opacity dur-fast',
                    chrome ? 'opacity-100' : 'opacity-0',
                  )}
                >
                  <IconButton
                    icon="chevron-right"
                    label="Next photo"
                    variant="ghost"
                    onClick={() => go(1)}
                    disabled={index === total - 1}
                    className="rounded-full bg-glass text-ink"
                  />
                </div>
              </>
            ) : null}

            <div
              className={cn(
                'absolute inset-x-0 bottom-0 flex flex-col items-center gap-3 p-4',
                'bg-gradient-to-t from-scrim to-transparent',
                'transition-opacity dur-fast ease-standard',
                chrome ? 'opacity-100' : 'pointer-events-none opacity-0',
              )}
            >
              {total > 1 ? (
                <div
                  role="tablist"
                  aria-label="Photos"
                  className="flex max-w-full gap-2 overflow-x-auto px-2 py-1"
                >
                  {photos.map((photo, position) => (
                    <button
                      key={photo.id}
                      type="button"
                      role="tab"
                      aria-selected={position === index}
                      aria-label={`Photo ${position + 1} of ${total}`}
                      onClick={() => {
                        setIndex(position);
                        resetTransform();
                        wakeChrome();
                      }}
                      className={cn(
                        'focus-ring relative size-12 flex-none overflow-hidden rounded-sm border',
                        position === index
                          ? 'border-accent'
                          : 'border-line opacity-[var(--k-opacity-hover)]',
                      )}
                    >
                      {photo.src ? (
                        /* 48px box → 48px rendition. The rail must never pull
                           the originals the main stage is already paying for. */
                        <Image
                          src={photo.src}
                          alt=""
                          fill
                          sizes="48px"
                          unoptimized={!isOptimizableImageSrc(photo.src)}
                          className="object-cover"
                        />
                      ) : (
                        <span className="grid size-full place-items-center bg-surface-2 text-ink-3">
                          <Icon name="image" size="sm" />
                        </span>
                      )}
                    </button>
                  ))}
                </div>
              ) : null}

              <p className="text-caption text-ink-3">
                Drag or use ← → to move · scroll or pinch to zoom · Esc to close
              </p>
            </div>

            <p aria-live="polite" className="sr-only">
              {total > 0 ? `Photo ${index + 1} of ${total}. ${current?.alt ?? ''}` : ''}
            </p>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </Portal>
  );
}
