'use client';

import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { cn } from '@/lib/cn';
import { drawCroppedCover, type CropRect, type DrawableImage } from './crop';

/**
 * Live canvas render of a photo's current FRAME edit — the web twin of
 * mobile's `CroppedPhoto`: cover-fit of exactly the cropped region, no
 * re-encode. Used by the FRAME thumb rail, the masonry-tile preview and the
 * FILE photo tray, so every surface shows the same truth.
 */
export interface CroppedPreviewProps {
  image: DrawableImage | null;
  baseWidth: number;
  baseHeight: number;
  quarterTurns: number;
  crop: CropRect | null;
  className?: string;
  style?: CSSProperties;
}

export function CroppedPreview({
  image,
  baseWidth,
  baseHeight,
  quarterTurns,
  crop,
  className,
  style,
}: CroppedPreviewProps) {
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });

  useEffect(() => {
    const wrap = wrapRef.current;
    if (!wrap) return;
    const measure = () => {
      const rect = wrap.getBoundingClientRect();
      setSize((current) =>
        current.width === rect.width && current.height === rect.height
          ? current
          : { width: rect.width, height: rect.height },
      );
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(wrap);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !image || size.width <= 0 || size.height <= 0) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(size.width * dpr));
    canvas.height = Math.max(1, Math.round(size.height * dpr));
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, size.width, size.height);
    drawCroppedCover(
      ctx,
      image,
      quarterTurns,
      baseWidth,
      baseHeight,
      crop,
      size.width,
      size.height,
    );
  }, [image, baseWidth, baseHeight, quarterTurns, crop, size]);

  return (
    <div ref={wrapRef} style={style} className={cn('overflow-hidden bg-skeleton', className)}>
      <canvas ref={canvasRef} className="size-full" aria-hidden />
    </div>
  );
}
