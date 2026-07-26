'use client';

import { memo, useCallback, useMemo, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent } from 'react';
import Link from 'next/link';
import { motion, useReducedMotion } from 'framer-motion';
import { ActionBar } from '@/components/ui/ActionBar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import { Pressable } from '@/components/ui/Pressable';
import { curve, fadeRise, gridStaggerDelay, reducedTransition } from '@/design/motion';
import { cn } from '@/lib/cn';
import { entityHref, ENTITY_LABEL } from '@/lib/entities';
import { useCoarsePointer } from '@/lib/media-query';
import { compactCount, plural } from '@/lib/format';
import type { SocialSeed } from '@/lib/interactions';
import { mediaUrl } from '@/lib/storage';
import { tileKey, type TileCard } from './tile-card';

/**
 * One surf tile.
 *
 * At rest it is the photograph and nothing else (DESIGN_SYSTEM §4). Counts,
 * actions and the owner fade in on hover or keyboard focus; everything rarer
 * lives behind the long-press peek.
 *
 * The gesture contract comes from `Pressable`, so a single click is never
 * delayed by the double-click window:
 *   click        → Closeup (an intercepting route: the URL changes, the grid
 *                  stays mounted behind the modal, Back closes it)
 *   double click → immersive fullscreen viewer
 *   right click / long press → the radial quick-action peek
 *
 * The action overlay is a *sibling* of the `<button>`, never a child — nesting
 * a control inside a button is invalid HTML and breaks keyboard semantics.
 */

export interface SurfTileProps {
  card: TileCard;
  /** Feed position — drives the entry stagger only. */
  index: number;
  /** Roving tabindex: exactly one tile in a grid is tabbable at a time. */
  tabbable: boolean;
  sizes: string;
  priority?: boolean;
  showOwner?: boolean;
  onOpen: (card: TileCard) => void;
  onImmersive: (card: TileCard) => void;
  onPeek: (card: TileCard, position: { x: number; y: number }) => void;
  onFocusTile?: (key: string) => void;
  onTileKeyDown?: (event: ReactKeyboardEvent<HTMLButtonElement>) => void;
}

function childSummary(card: TileCard): string | null {
  if (card.type === 'item') {
    return card.counts.child > 1
      ? `${card.counts.child} ${plural(card.counts.child, 'photo')}`
      : null;
  }
  return `${compactCount(card.counts.child)} ${plural(card.counts.child, 'item')}`;
}

export const SurfTile = memo(function SurfTile({
  card,
  index,
  tabbable,
  sizes,
  priority = false,
  showOwner = true,
  onOpen,
  onImmersive,
  onPeek,
  onFocusTile,
  onTileKeyDown,
}: SurfTileProps) {
  const reduced = useReducedMotion();
  const [revealed, setRevealed] = useState(false);
  // Touch devices have no hover to reveal with — caption and actions stay on.
  const coarse = useCoarsePointer();
  const shown = revealed || coarse;
  const key = tileKey(card);

  const seed = useMemo<SocialSeed>(
    () => ({
      likeCount: card.counts.like,
      saveCount: card.counts.save,
      repostCount: card.counts.repost,
      commentCount: card.counts.comment,
      viewCount: card.counts.view,
      childCount: card.counts.child,
      viewerLiked: card.viewer.liked,
      viewerSaved: card.viewer.saved,
      viewerReposted: card.viewer.reposted,
    }),
    [card],
  );

  const handleKeyDown = useCallback(
    (event: ReactKeyboardEvent<HTMLButtonElement>) => {
      onTileKeyDown?.(event);
      if (event.defaultPrevented) return;
      // Enter opens the closeup (Pressable's default); Space escalates.
      if (event.key === ' ' || event.key === 'Spacebar') {
        event.preventDefault();
        onImmersive(card);
      }
    },
    [card, onImmersive, onTileKeyDown],
  );

  const summary = childSummary(card);
  const isSet = card.type !== 'item';

  return (
    <motion.div
      className="group relative"
      variants={fadeRise}
      initial="hidden"
      animate="visible"
      transition={
        reduced ? reducedTransition : { ...curve.enter, delay: gridStaggerDelay(index) }
      }
      onMouseEnter={() => setRevealed(true)}
      onMouseLeave={() => setRevealed(false)}
    >
      <Pressable
        data-surf-tile={key}
        data-entity-type={card.type}
        data-entity-id={card.id}
        tabIndex={tabbable ? 0 : -1}
        aria-label={`${ENTITY_LABEL[card.type]}: ${card.title}${
          card.owner ? ` by ${card.owner.displayName}` : ''
        }`}
        feedback={false}
        className="block w-full overflow-hidden rounded-lg bg-surface-2"
        onActivate={() => onOpen(card)}
        onEscalate={() => onImmersive(card)}
        onPeek={(position) => onPeek(card, position)}
        onFocus={() => {
          setRevealed(true);
          onFocusTile?.(key);
        }}
        onBlur={() => setRevealed(false)}
        onKeyDown={handleKeyDown}
      >
        <BlurhashImage
          src={mediaUrl(card.coverPath)}
          alt={card.title}
          width={card.width}
          height={card.height}
          blurhash={card.blurhash}
          dominantColor={card.accentColor}
          sizes={sizes}
          priority={priority}
          className="transition-transform dur-medium ease-emphasized group-hover:scale-[1.02] motion-reduce:group-hover:scale-100"
        />

        {/* Chrome at rest: nothing but a whisper of structure on set tiles. */}
        {isSet ? (
          <span className="glass pointer-events-none absolute left-2 top-2 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-micro uppercase tracking-widest text-ink">
            <Icon name="grid" size="xs" />
            {ENTITY_LABEL[card.type]}
          </span>
        ) : card.counts.child > 1 ? (
          <span className="glass pointer-events-none absolute left-2 top-2 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-micro tabular text-ink">
            <Icon name="image" size="xs" />
            {card.counts.child}
          </span>
        ) : null}

        <span
          className={cn(
            'pointer-events-none absolute inset-x-0 bottom-0 flex flex-col gap-0.5 p-3',
            'bg-gradient-to-t from-scrim to-transparent',
            'transition-opacity dur-fast ease-standard',
            shown ? 'opacity-100' : 'opacity-0',
          )}
        >
          <span className="truncate font-display text-title3 text-ink-inverse drop-shadow-md">
            {card.title}
          </span>
          <span className="flex items-center gap-1.5 truncate text-caption text-ink-inverse/80">
            {showOwner && card.owner ? <span className="truncate">@{card.owner.username}</span> : null}
            {showOwner && card.owner && summary ? <span aria-hidden>·</span> : null}
            {summary ? <span className="truncate tabular">{summary}</span> : null}
          </span>
        </span>
      </Pressable>

      {/* Sibling of the button, never a child. Mounted only once revealed so a
          60-tile grid does not carry 60 idle action bars — except on touch,
          where "revealed" would never happen and the actions must simply be
          there. */}
      {shown ? (
        <div
          className="absolute right-2 top-2 z-raised"
          onMouseEnter={() => setRevealed(true)}
        >
          <ActionBar
            type={card.type}
            id={card.id}
            seed={seed}
            variant="overlay"
            title={card.title}
            showComment={false}
            showViews={false}
            showShare={false}
            showReport={false}
            className="gap-0"
          />
        </div>
      ) : null}

      {/* A real, crawlable link to the canonical page. Not a tab stop — the
          button above is the keyboard affordance — but reachable in a screen
          reader's link list and followed by indexers. */}
      <Link
        href={entityHref(card.type, card.id)}
        tabIndex={-1}
        className="sr-only"
      >
        {`Open ${card.title}`}
      </Link>
    </motion.div>
  );
});
