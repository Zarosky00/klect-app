'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { curve, duration, reducedTransition } from '@/design/motion';
import { cn } from '@/lib/cn';
import { IconButton } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { Portal, useEscape, useLockBodyScroll } from '@/components/ui/overlay';

/**
 * The double-tap destination: fullscreen, pinch/pan, swipe between images,
 * chrome auto-hides (DESIGN_SYSTEM §4).
 *
 * Written rather than pulled from a library so every colour, radius, duration
 * and curve comes from the token modules — a third-party lightbox ships its own
 * stylesheet full of literals and cannot follow a theme switch.
 */

export interface ImmersivePhoto {
  id: string;
  src: string | null;
  alt: string;
  width?: number | null;
  height?: number | null;
}

export interface ImmersiveViewerProps {
  open: boolean;
  onClose: () => void;
  photos: ImmersivePhoto[];
  initialIndex?: number;
  title?: string;
}

/** How long the chrome stays up after the last interaction. §4: 2s. */
const CHROME_IDLE_MS = duration.deliberate * 5;
const MAX_ZOOM = 4;
const MIN_ZOOM = 1;
const ZOOM_STEP = 1.6;
/** A horizontal flick past this many pixels advances while unzoomed. */
const SWIPE_PX = 80;

export function ImmersiveViewer({
  open,
  onClose,
  photos,
  initialIndex = 0,
  title,
}: ImmersiveViewerProps) {
  const reduced = useReducedMotion();
  const [index, setIndex] = useState(initialIndex);
  const [zoom, setZoom] = useState(MIN_ZOOM);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [chromeVisible, setChromeVisible] = useState(true);
  const idleTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pinchStart = useRef<{ distance: number; zoom: number } | null>(null);

  const count = photos.length;
  const photo = photos[Math.min(index, Math.max(0, count - 1))];

  useLockBodyScroll(open);
  useEscape(open, onClose);

  const resetTransform = useCallback(() => {
    setZoom(MIN_ZOOM);
    setPan({ x: 0, y: 0 });
  }, []);

  useEffect(() => {
    if (!open) return;
    setIndex(Math.min(Math.max(0, initialIndex), Math.max(0, count - 1)));
    resetTransform();
    setChromeVisible(true);
  }, [count, initialIndex, open, resetTransform]);

  const wakeChrome = useCallback(() => {
    setChromeVisible(true);
    if (idleTimer.current) clearTimeout(idleTimer.current);
    idleTimer.current = setTimeout(() => setChromeVisible(false), CHROME_IDLE_MS);
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

  const go = useCallback(
    (delta: number) => {
      if (count < 2) return;
      setIndex((current) => (current + delta + count) % count);
      resetTransform();
      wakeChrome();
    },
    [count, resetTransform, wakeChrome],
  );

  const zoomBy = useCallback(
    (factor: number) => {
      setZoom((current) => {
        const next = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, current * factor));
        if (next === MIN_ZOOM) setPan({ x: 0, y: 0 });
        return next;
      });
      wakeChrome();
    },
    [wakeChrome],
  );

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      switch (event.key) {
        case 'ArrowRight':
          event.preventDefault();
          go(1);
          break;
        case 'ArrowLeft':
          event.preventDefault();
          go(-1);
          break;
        case '+':
        case '=':
          event.preventDefault();
          zoomBy(ZOOM_STEP);
          break;
        case '-':
          event.preventDefault();
          zoomBy(1 / ZOOM_STEP);
          break;
        case '0':
          event.preventDefault();
          resetTransform();
          break;
        default:
          wakeChrome();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [go, open, resetTransform, wakeChrome, zoomBy]);

  const onWheel = useCallback(
    (event: React.WheelEvent) => {
      if (!event.ctrlKey && Math.abs(event.deltaY) < 2) return;
      zoomBy(event.deltaY < 0 ? ZOOM_STEP : 1 / ZOOM_STEP);
    },
    [zoomBy],
  );

  const onTouchStart = useCallback((event: React.TouchEvent) => {
    if (event.touches.length !== 2) return;
    const [a, b] = [event.touches[0], event.touches[1]];
    if (!a || !b) return;
    pinchStart.current = {
      distance: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY),
      zoom,
    };
  }, [zoom]);

  const onTouchMove = useCallback((event: React.TouchEvent) => {
    const start = pinchStart.current;
    if (!start || event.touches.length !== 2) return;
    const [a, b] = [event.touches[0], event.touches[1]];
    if (!a || !b) return;
    const distance = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
    if (start.distance <= 0) return;
    setZoom(Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, (start.zoom * distance) / start.distance)));
  }, []);

  const onTouchEnd = useCallback(() => {
    pinchStart.current = null;
    setZoom((current) => {
      if (current <= MIN_ZOOM) setPan({ x: 0, y: 0 });
      return current;
    });
  }, []);

  if (!photo) return null;

  const transition = reduced ? reducedTransition : curve.medium;

  return (
    <Portal>
      <AnimatePresence>
        {open ? (
          <motion.div
            className="fixed inset-0 z-immersive flex flex-col bg-base"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={reduced ? reducedTransition : curve.fast}
            role="dialog"
            aria-modal="true"
            aria-label={title ? `${title} — fullscreen viewer` : 'Fullscreen viewer'}
            onPointerMove={wakeChrome}
          >
            <div
              className={cn(
                'pointer-events-none absolute inset-x-0 top-0 z-raised flex items-center gap-3 p-4',
                'transition-opacity dur-fast ease-standard',
                chromeVisible ? 'opacity-100' : 'opacity-0',
              )}
            >
              <span
                className="glass pointer-events-auto rounded-full border border-line px-3 py-1.5 text-caption text-ink"
                aria-live="polite"
              >
                {count > 1 ? `Photo ${index + 1} of ${count}` : (title ?? 'Photo')}
              </span>
              <span className="flex-1" />
              <span className="glass pointer-events-auto flex items-center gap-1 rounded-full border border-line p-1">
                <IconButton
                  icon="search"
                  label="Zoom out"
                  size="sm"
                  onClick={() => zoomBy(1 / ZOOM_STEP)}
                />
                <span className="tabular px-1 text-micro text-ink-2">
                  {Math.round(zoom * 100)}%
                </span>
                <IconButton
                  icon="plus"
                  label="Zoom in"
                  size="sm"
                  onClick={() => zoomBy(ZOOM_STEP)}
                />
              </span>
              <span className="glass pointer-events-auto rounded-full border border-line p-1">
                <IconButton icon="close" label="Close fullscreen" size="sm" onClick={onClose} />
              </span>
            </div>

            <div
              className="relative flex min-h-0 flex-1 items-center justify-center overflow-hidden"
              onWheel={onWheel}
              onTouchStart={onTouchStart}
              onTouchMove={onTouchMove}
              onTouchEnd={onTouchEnd}
            >
              <motion.div
                key={photo.id}
                className="flex size-full items-center justify-center"
                drag={zoom > MIN_ZOOM ? true : 'x'}
                dragMomentum={false}
                dragElastic={zoom > MIN_ZOOM ? 0 : 0.2}
                onDragEnd={(_event, info) => {
                  if (zoom > MIN_ZOOM) {
                    setPan((current) => ({
                      x: current.x + info.offset.x,
                      y: current.y + info.offset.y,
                    }));
                    return;
                  }
                  if (info.offset.x < -SWIPE_PX) go(1);
                  else if (info.offset.x > SWIPE_PX) go(-1);
                }}
                initial={{ opacity: 0, scale: 0.98 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={transition}
                onDoubleClick={() => (zoom > MIN_ZOOM ? resetTransform() : zoomBy(ZOOM_STEP * 1.5))}
              >
                {photo.src ? (
                  /* eslint-disable-next-line @next/next/no-img-element -- media
                     lives on arbitrary hosts today; see BlurhashImage. */
                  <img
                    src={photo.src}
                    alt={photo.alt}
                    draggable={false}
                    className="max-h-full max-w-full select-none object-contain"
                    style={{
                      transform: `translate3d(${pan.x}px, ${pan.y}px, 0) scale(${zoom})`,
                      transition: reduced ? undefined : 'transform var(--k-dur-fast) var(--k-ease-standard)',
                      cursor: zoom > MIN_ZOOM ? 'grab' : 'zoom-in',
                    }}
                  />
                ) : (
                  <span className="text-callout text-ink-3">This photo is unavailable.</span>
                )}
              </motion.div>

              {count > 1 ? (
                <>
                  <button
                    type="button"
                    aria-label="Previous photo"
                    onClick={() => go(-1)}
                    className={cn(
                      'glass focus-ring absolute left-3 grid size-11 place-items-center rounded-full border border-line text-ink',
                      'transition-opacity dur-fast ease-standard',
                      chromeVisible ? 'opacity-100' : 'opacity-0',
                    )}
                  >
                    <Icon name="chevron-left" size="lg" />
                  </button>
                  <button
                    type="button"
                    aria-label="Next photo"
                    onClick={() => go(1)}
                    className={cn(
                      'glass focus-ring absolute right-3 grid size-11 place-items-center rounded-full border border-line text-ink',
                      'transition-opacity dur-fast ease-standard',
                      chromeVisible ? 'opacity-100' : 'opacity-0',
                    )}
                  >
                    <Icon name="chevron-right" size="lg" />
                  </button>
                </>
              ) : null}
            </div>

            {count > 1 ? (
              <div
                className={cn(
                  'flex shrink-0 items-center justify-center gap-2 p-4',
                  'transition-opacity dur-fast ease-standard',
                  chromeVisible ? 'opacity-100' : 'opacity-0',
                )}
              >
                {photos.map((entry, position) => (
                  <button
                    key={entry.id}
                    type="button"
                    aria-label={`Go to photo ${position + 1}`}
                    aria-current={position === index ? 'true' : undefined}
                    onClick={() => {
                      setIndex(position);
                      resetTransform();
                      wakeChrome();
                    }}
                    className={cn(
                      'focus-ring h-1.5 rounded-full transition-all dur-fast ease-standard',
                      position === index ? 'w-6 bg-accent' : 'w-1.5 bg-line-strong',
                    )}
                  />
                ))}
              </div>
            ) : null}
          </motion.div>
        ) : null}
      </AnimatePresence>
    </Portal>
  );
}
