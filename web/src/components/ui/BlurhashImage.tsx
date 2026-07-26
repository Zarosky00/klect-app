'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import Image from 'next/image';
import { decode } from 'blurhash';
import { aspect } from '@/design/tokens.g';
import { cn } from '@/lib/cn';
import { isOptimizableImageSrc } from '@/lib/storage';

/**
 * The masonry workhorse.
 *
 * The tile is reserved from the cover's intrinsic `width`/`height` BEFORE the
 * image loads, the blurhash is painted into that box, and the photograph
 * cross-fades in over `fast`. The grid therefore never reflows — which is the
 * whole reason `surf_card` carries `width`, `height` and `cover_blurhash`.
 *
 * Extreme ratios are clamped to `aspect.gridMin`..`aspect.gridMax` so one very
 * tall image cannot own the viewport (tokens.json, `aspect.note`).
 */

const BLURHASH_RESOLUTION = 32;

export interface BlurhashImageProps {
  src: string | null | undefined;
  alt: string;
  /** Intrinsic pixels of the source image. */
  width?: number | null;
  height?: number | null;
  blurhash?: string | null;
  /** Fallback ratio (w/h) when intrinsic size is unknown. */
  fallbackAspect?: number;
  /** Clamp the ratio into the grid-safe band. Off for closeup/detail views. */
  clamp?: boolean;
  className?: string;
  imageClassName?: string;
  sizes?: string;
  priority?: boolean;
  /** Solid colour painted under the blurhash while it decodes. */
  dominantColor?: string | null;
  onLoad?: () => void;
}

export function BlurhashImage({
  src,
  alt,
  width,
  height,
  blurhash,
  fallbackAspect = aspect.cover,
  clamp = true,
  className,
  imageClassName,
  sizes = '(max-width: 768px) 50vw, (max-width: 1280px) 25vw, 20vw',
  priority = false,
  dominantColor,
  onLoad,
}: BlurhashImageProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [loaded, setLoaded] = useState(false);

  const ratio = useMemo(() => {
    const intrinsic =
      typeof width === 'number' && typeof height === 'number' && width > 0 && height > 0
        ? width / height
        : fallbackAspect;
    if (!clamp) return intrinsic;
    return Math.min(Math.max(intrinsic, aspect.gridMin), aspect.gridMax);
  }, [clamp, fallbackAspect, height, width]);

  useEffect(() => {
    if (!blurhash) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    let cancelled = false;
    try {
      const pixels = decode(blurhash, BLURHASH_RESOLUTION, BLURHASH_RESOLUTION);
      if (cancelled) return;
      const context = canvas.getContext('2d');
      if (!context) return;
      const imageData = context.createImageData(BLURHASH_RESOLUTION, BLURHASH_RESOLUTION);
      imageData.data.set(pixels);
      context.putImageData(imageData, 0, 0);
    } catch {
      // A malformed hash is not worth an error boundary — the solid colour
      // underneath is a perfectly good placeholder.
    }
    return () => {
      cancelled = true;
    };
  }, [blurhash]);

  const style: CSSProperties = {
    aspectRatio: String(ratio),
    backgroundColor: dominantColor ?? undefined,
  };

  return (
    <div
      className={cn(
        'relative w-full overflow-hidden bg-skeleton',
        className,
      )}
      style={style}
    >
      {blurhash ? (
        <canvas
          ref={canvasRef}
          width={BLURHASH_RESOLUTION}
          height={BLURHASH_RESOLUTION}
          aria-hidden
          className={cn(
            'absolute inset-0 size-full transition-opacity dur-fast ease-standard',
            loaded ? 'opacity-0' : 'opacity-100',
          )}
        />
      ) : null}

      {src ? (
        /* `fill` inside the aspect-ratio box the blurhash already reserved:
           next/image serves a srcset scaled to `sizes` (a 180px masonry tile
           downloads a ~256px webp instead of the 2048px original), while the
           reserved box keeps CLS at zero exactly as before. Hosts outside
           `remotePatterns` fall back to the original file rather than crash. */
        <Image
          src={src}
          alt={alt}
          fill
          sizes={sizes}
          priority={priority}
          unoptimized={!isOptimizableImageSrc(src)}
          onLoad={() => {
            setLoaded(true);
            onLoad?.();
          }}
          className={cn(
            'object-cover transition-opacity dur-fast ease-standard',
            loaded ? 'opacity-100' : 'opacity-0',
            imageClassName,
          )}
        />
      ) : null}
    </div>
  );
}
