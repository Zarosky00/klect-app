'use client';

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { aspect, layout, masonryColumns } from '@/design/tokens.g';
import { cn } from '@/lib/cn';

/**
 * A *measured* masonry — not `column-count`.
 *
 * Why it matters: with CSS columns the browser re-balances every column each
 * time you append a page, so tiles that are already on screen move. That is a
 * layout shift on every scroll tick. Here each card is assigned to the shortest
 * column by a deterministic greedy pass, so the assignment of card `i` depends
 * only on cards `0..i-1`: appending a page can never move a tile that is
 * already placed.
 *
 * The height used for that pass is the reserved height — `columnWidth / ratio`,
 * with `ratio` taken from the cover's intrinsic `width`/`height` exactly as
 * `BlurhashImage` reserves it. No image needs to have loaded, so CLS is ~0.
 *
 * Before hydration (and with JS off) the same children render inside the
 * token-driven `.k-masonry` CSS-column fallback, so the HTML a crawler receives
 * already contains every tile and every link. The swap to measured columns
 * happens in a layout effect — synchronously, before the browser paints — so
 * the reader never sees the intermediate layout.
 */

const useIsomorphicLayoutEffect =
  typeof window === 'undefined' ? useEffect : useLayoutEffect;

/** The grid-safe ratio band. Mirrors `BlurhashImage`'s clamp exactly. */
export function tileRatio(
  width: number | null | undefined,
  height: number | null | undefined,
  fallback: number = aspect.cover,
): number {
  const intrinsic =
    typeof width === 'number' && typeof height === 'number' && width > 0 && height > 0
      ? width / height
      : fallback;
  return Math.min(Math.max(intrinsic, aspect.gridMin), aspect.gridMax);
}

/**
 * Greedy shortest-column packing in ratio units (column width = 1), so the
 * result is independent of the pixel width and stable across a resize that
 * keeps the column count.
 */
export function distribute<T>(
  entries: readonly T[],
  columnCount: number,
  ratioOf: (entry: T) => number,
): T[][] {
  const columns: T[][] = Array.from({ length: columnCount }, () => []);
  const heights = new Array<number>(columnCount).fill(0);

  for (const entry of entries) {
    let target = 0;
    for (let index = 1; index < columnCount; index += 1) {
      if ((heights[index] ?? 0) < (heights[target] ?? 0)) target = index;
    }
    columns[target]?.push(entry);
    heights[target] = (heights[target] ?? 0) + 1 / Math.max(ratioOf(entry), aspect.gridMin);
  }

  return columns;
}

/** Measures the container and derives the column count from the token ramp. */
export function useMasonryColumns(
  ref: React.RefObject<HTMLElement | null>,
  columnsOverride?: number,
): number {
  const [width, setWidth] = useState(0);

  useIsomorphicLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;

    setWidth(element.getBoundingClientRect().width);

    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver((entries) => {
      const next = entries[0]?.contentRect.width ?? 0;
      setWidth((current) => (Math.abs(current - next) < 1 ? current : next));
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [ref]);

  if (width <= 0) return 0;
  if (columnsOverride && columnsOverride > 0) return columnsOverride;
  return masonryColumns(width);
}

export interface MasonryProps<T> {
  entries: readonly T[];
  keyOf: (entry: T) => string;
  ratioOf: (entry: T) => number;
  children: (entry: T, index: number) => ReactNode;
  /** Force a column count — used by the marketing preview. */
  columns?: number;
  className?: string;
  /** Called with the live column count so callers can size `sizes=""`. */
  onColumnsChange?: (columns: number) => void;
}

export function Masonry<T>({
  entries,
  keyOf,
  ratioOf,
  children,
  columns: columnsOverride,
  className,
  onColumnsChange,
}: MasonryProps<T>) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const columnCount = useMasonryColumns(containerRef, columnsOverride);

  const notify = useCallback(
    (value: number) => onColumnsChange?.(value),
    [onColumnsChange],
  );

  useEffect(() => {
    if (columnCount > 0) notify(columnCount);
  }, [columnCount, notify]);

  // Index lookup keeps the entry animation stagger tied to feed order rather
  // than to the position inside a column.
  const indexByKey = useMemo(() => {
    const map = new Map<string, number>();
    entries.forEach((entry, index) => map.set(keyOf(entry), index));
    return map;
  }, [entries, keyOf]);

  const columns = useMemo(
    () => (columnCount > 0 ? distribute(entries, columnCount, ratioOf) : []),
    [columnCount, entries, ratioOf],
  );

  if (columnCount === 0) {
    // Pre-hydration / no-JS: every tile is present, in feed order.
    return (
      <div ref={containerRef} className={cn('k-masonry', className)}>
        {entries.map((entry, index) => (
          <div key={keyOf(entry)}>{children(entry, index)}</div>
        ))}
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className={cn('flex items-start', className)}
      style={{ gap: 'var(--k-masonry-gutter)' }}
    >
      {columns.map((column, columnIndex) => (
        <div
          key={columnIndex}
          className="flex min-w-0 flex-1 flex-col"
          style={{ gap: 'var(--k-masonry-gutter)' }}
        >
          {column.map((entry) => {
            const key = keyOf(entry);
            return <div key={key}>{children(entry, indexByKey.get(key) ?? 0)}</div>;
          })}
        </div>
      ))}
    </div>
  );
}

/** `sizes` hint that matches the token column ramp. */
export function masonrySizes(columnCount: number): string {
  if (columnCount > 0) return `${Math.ceil(100 / columnCount)}vw`;
  const { md, lg, xl } = layout.breakpoint;
  return [
    `(max-width: ${md}px) ${Math.ceil(100 / layout.masonryColumns.sm)}vw`,
    `(max-width: ${lg}px) ${Math.ceil(100 / layout.masonryColumns.md)}vw`,
    `(max-width: ${xl}px) ${Math.ceil(100 / layout.masonryColumns.lg)}vw`,
    `${Math.ceil(100 / layout.masonryColumns.xl)}vw`,
  ].join(', ');
}
