'use client';

import { useCallback, useSyncExternalStore } from 'react';
import { layout } from '@/design/tokens.g';

/**
 * Live `matchMedia` as React state, SSR-safe via `useSyncExternalStore`.
 *
 * The server snapshot is always `false` (no media to query), so callers must
 * pick their query so that `false` is the safe default — e.g. ask "is this a
 * coarse pointer?" (default: fine) rather than "is this a fine pointer?".
 */
export function useMediaQuery(query: string): boolean {
  const subscribe = useCallback(
    (onChange: () => void) => {
      const list = window.matchMedia(query);
      list.addEventListener('change', onChange);
      return () => list.removeEventListener('change', onChange);
    },
    [query],
  );
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(query).matches,
    () => false,
  );
}

/**
 * `true` on touch-first devices (phones, tablets). Hover-gated affordances —
 * tile captions, action bars, bubble actions — must not depend on a hover
 * these devices cannot produce.
 */
export function useCoarsePointer(): boolean {
  return useMediaQuery('(pointer: coarse)');
}

/**
 * `true` below the `md` breakpoint token — the same threshold the chrome uses
 * to swap the desktop rail for the mobile bars.
 */
export function usePhoneViewport(): boolean {
  // max-width mirrors Tailwind's `md:` boundary: md applies at >= 768.
  return useMediaQuery(`(max-width: ${layout.breakpoint.md - 1}px)`);
}
