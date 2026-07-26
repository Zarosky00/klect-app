'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { IconButton } from '@/components/ui/Button';
import { Pressable } from '@/components/ui/Pressable';
import { cn } from '@/lib/cn';
import type { CloseupMedia } from '@/lib/types';
import { mediaUrl } from '@/lib/storage';

/**
 * Every photo in the set, in order, with the blurhash painted into a box that
 * was reserved from the photo's intrinsic size — so paging never reflows the
 * panel.
 *
 * Tapping the photograph escalates to the immersive viewer, which is where
 * pinch/pan/zoom live. Arrow keys page while the pager has focus.
 */
/**
 * Beats the primitive's own `object-cover` on specificity (class + element vs
 * class), because the closeup shows the whole photograph, never a crop.
 */
const CONTAIN_IMAGE = '[&_img]:object-contain';

export interface MediaPagerProps {
  media: CloseupMedia[];
  /** Used when there is no media row — a collection or subcollection cover. */
  fallback?: {
    path: string | null;
    blurhash: string | null;
    width: number | null;
    height: number | null;
  };
  title: string;
  onImmersive: (index: number) => void;
  className?: string;
}

export function MediaPager({
  media,
  fallback,
  title,
  onImmersive,
  className,
}: MediaPagerProps) {
  const [index, setIndex] = useState(0);
  const stripRef = useRef<HTMLDivElement | null>(null);

  const total = media.length;
  const current = media[Math.min(index, Math.max(total - 1, 0))];

  const go = useCallback(
    (delta: number) => {
      setIndex((value) => Math.min(Math.max(value + delta, 0), Math.max(total - 1, 0)));
    },
    [total],
  );

  useEffect(() => {
    setIndex(0);
  }, [title]);

  const onKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (event.key === 'ArrowRight') {
        event.preventDefault();
        go(1);
      } else if (event.key === 'ArrowLeft') {
        event.preventDefault();
        go(-1);
      }
    },
    [go],
  );

  const source = current
    ? {
        path: current.storage_path,
        blurhash: current.blurhash,
        width: current.width,
        height: current.height,
        alt: current.alt_text ?? `${title} — photo ${index + 1} of ${total}`,
        dominant: current.dominant_color,
      }
    : {
        path: fallback?.path ?? null,
        blurhash: fallback?.blurhash ?? null,
        width: fallback?.width ?? null,
        height: fallback?.height ?? null,
        alt: title,
        dominant: null,
      };

  return (
    <div
      className={cn('flex flex-col gap-3', className)}
      onKeyDown={onKeyDown}
      role="group"
      aria-roledescription="carousel"
      aria-label={`${title} — photos`}
    >
      <div className="relative">
        <Pressable
          feedback={false}
          className="block w-full overflow-hidden rounded-lg bg-sunken"
          aria-label={`Open ${title} fullscreen`}
          onActivate={() => onImmersive(index)}
          onEscalate={() => onImmersive(index)}
        >
          <BlurhashImage
            src={mediaUrl(source.path)}
            alt={source.alt}
            width={source.width}
            height={source.height}
            blurhash={source.blurhash}
            dominantColor={source.dominant}
            clamp={false}
            priority
            sizes="(max-width: 1024px) 100vw, 60vw"
            className={CONTAIN_IMAGE}
          />
        </Pressable>

        {total > 1 ? (
          <>
            <div className="absolute left-2 top-1/2 -translate-y-1/2">
              <IconButton
                icon="chevron-left"
                label="Previous photo"
                variant="ghost"
                size="sm"
                className="glass rounded-full text-ink"
                disabled={index === 0}
                onClick={() => go(-1)}
              />
            </div>
            <div className="absolute right-2 top-1/2 -translate-y-1/2">
              <IconButton
                icon="chevron-right"
                label="Next photo"
                variant="ghost"
                size="sm"
                className="glass rounded-full text-ink"
                disabled={index >= total - 1}
                onClick={() => go(1)}
              />
            </div>
            <p className="glass tabular absolute right-2 top-2 rounded-full px-2 py-0.5 text-micro text-ink">
              {index + 1} / {total}
            </p>
          </>
        ) : null}
      </div>

      {total > 1 ? (
        <div
          ref={stripRef}
          role="tablist"
          aria-label="Photos"
          className="flex gap-2 overflow-x-auto pb-1"
        >
          {media.map((photo, position) => (
            <button
              key={photo.id}
              type="button"
              role="tab"
              aria-selected={position === index}
              aria-label={photo.alt_text ?? `Photo ${position + 1} of ${total}`}
              onClick={() => setIndex(position)}
              className={cn(
                'focus-ring size-16 flex-none overflow-hidden rounded-sm border transition-colors dur-fast',
                position === index ? 'border-accent' : 'border-line hover:border-line-strong',
              )}
            >
              {/* No intrinsic size on purpose: the strip is square, so the tile
                  takes `fallbackAspect` and the photo crops to fill it. */}
              <BlurhashImage
                src={mediaUrl(photo.storage_path)}
                alt=""
                blurhash={photo.blurhash}
                fallbackAspect={1}
                sizes="64px"
              />
            </button>
          ))}
        </div>
      ) : null}

      {source.alt && source.alt !== title ? (
        <p className="text-caption text-ink-3">{source.alt}</p>
      ) : null}
    </div>
  );
}
