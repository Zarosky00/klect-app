import { cn } from '@/lib/cn';

/**
 * Skeletons must match the real layout's shape exactly or the swap-in flashes
 * (DESIGN_SYSTEM §5). Never a centred spinner on a full page.
 */
export interface SkeletonProps {
  className?: string;
  /** Rounded like a photo tile, a line of text, or a circle. */
  shape?: 'block' | 'text' | 'circle';
  style?: React.CSSProperties;
}

export function Skeleton({ className, shape = 'block', style }: SkeletonProps) {
  return (
    <div
      aria-hidden
      className={cn(
        'k-shimmer',
        shape === 'circle' && 'rounded-full',
        shape === 'text' && 'h-[1em] rounded-xs',
        shape === 'block' && 'rounded-md',
        className,
      )}
      style={style}
    />
  );
}

export function SkeletonText({
  lines = 3,
  className,
}: {
  lines?: number;
  className?: string;
}) {
  return (
    <div className={cn('flex flex-col gap-2', className)}>
      {Array.from({ length: lines }, (_, index) => (
        <Skeleton
          key={index}
          shape="text"
          className={index === lines - 1 ? 'w-1/2' : 'w-full'}
        />
      ))}
    </div>
  );
}

/** A masonry tile placeholder that reserves a plausible aspect. */
export function SkeletonTile({ ratio = 0.8 }: { ratio?: number }) {
  return (
    <div className="flex flex-col gap-2">
      <Skeleton className="w-full" style={{ aspectRatio: String(ratio) }} />
      <Skeleton shape="text" className="w-3/4" />
    </div>
  );
}

export function SkeletonGrid({ count = 12 }: { count?: number }) {
  const ratios = [0.7, 1, 0.8, 1.2, 0.66, 0.9];
  return (
    <div className="k-masonry">
      {Array.from({ length: count }, (_, index) => (
        <SkeletonTile key={index} ratio={ratios[index % ratios.length] ?? 0.8} />
      ))}
    </div>
  );
}

export function SkeletonRow({ className }: { className?: string }) {
  return (
    <div className={cn('flex items-center gap-3', className)}>
      <Skeleton shape="circle" className="size-10" />
      <div className="flex-1">
        <Skeleton shape="text" className="w-1/3" />
        <Skeleton shape="text" className="mt-2 w-2/3" />
      </div>
    </div>
  );
}
