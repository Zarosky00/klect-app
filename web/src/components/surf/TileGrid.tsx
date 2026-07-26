'use client';

import { useCallback, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent } from 'react';
import dynamic from 'next/dynamic';
import { useRouter } from 'next/navigation';
import { closeupHref } from '@/lib/routes';
import { cn } from '@/lib/cn';
import type { ImmersiveSource } from './immersive-source';
import { Masonry, masonrySizes, tileRatio } from './Masonry';
import type { PeekTarget } from './PeekMenu';
import { SurfTile } from './SurfTile';
import { tileKey, type TileCard } from './tile-card';

/**
 * The two gesture escalations are heavyweight (framer-motion, the closeup API,
 * the social engine) and most sessions never trigger them — they load on the
 * first double-tap / long-press instead of riding in the feed bundle. Once
 * requested they stay mounted, so exit animations keep working.
 */
const ImmersiveViewer = dynamic(
  () => import('./ImmersiveViewer').then((module) => module.ImmersiveViewer),
  { ssr: false },
);
const PeekMenu = dynamic(
  () => import('./PeekMenu').then((module) => module.PeekMenu),
  { ssr: false },
);

/**
 * The masonry plus the whole gesture layer, reusable anywhere a set of tiles
 * appears: the surf feed, a collection page, a subcollection page, an item's
 * siblings, the marketing preview.
 *
 * Click opens the closeup as an intercepting route — the URL becomes
 * `/closeup/[type]/[id]`, this grid stays mounted behind the modal, and Back
 * closes it. A hard load of the same URL renders the full page instead.
 *
 * Keyboard: arrow keys move focus geometrically across the masonry (so it works
 * regardless of which column a tile landed in), Enter opens the closeup, Space
 * opens the immersive viewer, and the grid keeps a single tab stop via a roving
 * tabindex.
 */

export interface TileGridProps {
  cards: readonly TileCard[];
  showOwner?: boolean;
  /** How many leading tiles load eagerly — the ones above the fold. */
  priorityCount?: number;
  columns?: number;
  className?: string;
  emptyState?: React.ReactNode;
}

type Direction = 'left' | 'right' | 'up' | 'down';

/**
 * Geometric focus movement. Masonry has no row/column grid to index into, so
 * the nearest tile in the requested direction wins, measured centre to centre
 * with the off-axis distance weighted down.
 */
function findNeighbour(
  container: HTMLElement,
  from: HTMLElement,
  direction: Direction,
): HTMLElement | null {
  const tiles = Array.from(
    container.querySelectorAll<HTMLElement>('[data-surf-tile]'),
  ).filter((tile) => tile !== from);
  if (tiles.length === 0) return null;

  const origin = from.getBoundingClientRect();
  const ox = origin.left + origin.width / 2;
  const oy = origin.top + origin.height / 2;

  let best: HTMLElement | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (const tile of tiles) {
    const rect = tile.getBoundingClientRect();
    const dx = rect.left + rect.width / 2 - ox;
    const dy = rect.top + rect.height / 2 - oy;

    const along =
      direction === 'left' ? -dx : direction === 'right' ? dx : direction === 'up' ? -dy : dy;
    if (along <= 1) continue;

    const across = direction === 'left' || direction === 'right' ? Math.abs(dy) : Math.abs(dx);
    const score = along + across * 2;
    if (score < bestScore) {
      bestScore = score;
      best = tile;
    }
  }

  return best;
}

export function TileGrid({
  cards,
  showOwner = true,
  priorityCount = 6,
  columns,
  className,
  emptyState,
}: TileGridProps) {
  const router = useRouter();
  const containerRef = useRef<HTMLDivElement | null>(null);

  const [columnCount, setColumnCount] = useState(0);
  const [activeKey, setActiveKey] = useState<string | null>(null);
  const [peek, setPeek] = useState<{
    target: PeekTarget;
    position: { x: number; y: number };
  } | null>(null);
  const [immersive, setImmersive] = useState<ImmersiveSource | null>(null);
  /** Latch: the lazy chunks mount on first use and stay mounted after. */
  const [peekRequested, setPeekRequested] = useState(false);
  const [immersiveRequested, setImmersiveRequested] = useState(false);

  const openCloseup = useCallback(
    (card: TileCard) => {
      router.push(closeupHref(card.type, card.id));
    },
    [router],
  );

  const openImmersive = useCallback((card: TileCard) => {
    setImmersiveRequested(true);
    setImmersive({
      type: card.type,
      id: card.id,
      title: card.title,
      cover: { path: card.coverPath, width: card.width, height: card.height },
    });
  }, []);

  const openPeek = useCallback(
    (card: TileCard, position: { x: number; y: number }) => {
      setPeekRequested(true);
      setPeek({
        target: {
          type: card.type,
          id: card.id,
          title: card.title,
          seed: {
            likeCount: card.counts.like,
            saveCount: card.counts.save,
            repostCount: card.counts.repost,
            commentCount: card.counts.comment,
            viewCount: card.counts.view,
            viewerLiked: card.viewer.liked,
            viewerSaved: card.viewer.saved,
            viewerReposted: card.viewer.reposted,
          },
          ownerUsername: card.owner?.username ?? null,
        },
        position,
      });
    },
    [],
  );

  const onTileKeyDown = useCallback((event: ReactKeyboardEvent<HTMLButtonElement>) => {
    const map: Record<string, Direction> = {
      ArrowLeft: 'left',
      ArrowRight: 'right',
      ArrowUp: 'up',
      ArrowDown: 'down',
    };
    const direction = map[event.key];
    const container = containerRef.current;
    if (!direction || !container) return;

    event.preventDefault();
    const next = findNeighbour(container, event.currentTarget, direction);
    if (!next) return;
    const key = next.getAttribute('data-surf-tile');
    if (key) setActiveKey(key);
    next.focus({ preventScroll: false });
  }, []);

  const keyOf = useCallback((card: TileCard) => tileKey(card), []);
  const ratioOf = useCallback(
    (card: TileCard) => tileRatio(card.width, card.height),
    [],
  );

  const sizes = useMemo(() => masonrySizes(columnCount), [columnCount]);
  const firstKey = cards.length > 0 ? tileKey(cards[0] as TileCard) : null;

  if (cards.length === 0 && emptyState) return <>{emptyState}</>;

  return (
    <div ref={containerRef} className={cn('relative', className)}>
      <Masonry
        entries={cards}
        keyOf={keyOf}
        ratioOf={ratioOf}
        onColumnsChange={setColumnCount}
        {...(columns === undefined ? {} : { columns })}
      >
        {(card, index) => (
          <SurfTile
            card={card}
            index={index}
            tabbable={activeKey === null ? tileKey(card) === firstKey : activeKey === tileKey(card)}
            sizes={sizes}
            priority={index < priorityCount}
            showOwner={showOwner}
            onOpen={openCloseup}
            onImmersive={openImmersive}
            onPeek={openPeek}
            onFocusTile={setActiveKey}
            onTileKeyDown={onTileKeyDown}
          />
        )}
      </Masonry>

      {peekRequested ? (
        <PeekMenu
          target={peek?.target ?? null}
          position={peek?.position ?? null}
          onClose={() => setPeek(null)}
        />
      ) : null}

      {immersiveRequested ? (
        <ImmersiveViewer source={immersive} onClose={() => setImmersive(null)} />
      ) : null}
    </div>
  );
}
