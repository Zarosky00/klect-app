'use client';

import { forwardRef, useCallback, useEffect, useRef } from 'react';
import type { ButtonHTMLAttributes, CSSProperties, PointerEvent as ReactPointerEvent } from 'react';
import { gesture, pressScale } from '@/design/motion';
import { cn } from '@/lib/cn';

/**
 * The gesture surface. DESIGN_SYSTEM.md §4, implemented without the double-tap
 * delay penalty.
 *
 * A naive `onClick` + `onDoubleClick` pair forces every single tap to wait out
 * the double-tap window (~260ms), which is exactly what makes a web app feel
 * cheap. Instead:
 *
 *   · the FIRST tap fires `onActivate` immediately — the closeup starts opening
 *     on the same frame the finger lifts;
 *   · a second tap inside `doubleTapMs` fires `onEscalate`, and the closeup
 *     transition it interrupts is expected to hand off into the immersive
 *     viewer rather than being cancelled;
 *   · a press held past `longPressMs` fires `onPeek` and suppresses the tap.
 *
 * The user perceives zero delay because there is none: nothing is deferred.
 *
 * Web mapping of long-press: pointer hold, plus `contextmenu` (right click),
 * so a mouse user gets the peek too.
 */

export interface PressableProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'> {
  /** Single tap — open the Closeup. Fires immediately, never debounced. */
  onActivate?: (event: { pointerType: string }) => void;
  /** Double tap — escalate to the immersive fullscreen viewer. */
  onEscalate?: () => void;
  /** Long press / right click — the radial quick-action peek. */
  onPeek?: (position: { x: number; y: number }) => void;
  doubleTapMs?: number;
  longPressMs?: number;
  /** Applies the tap-feedback scale. Turn off for large surfaces. */
  feedback?: boolean;
  asChildTag?: 'button' | 'div';
}

const DEFAULT_DOUBLE_TAP_MS = gesture.doubleTapMs;
const DEFAULT_LONG_PRESS_MS = gesture.longPressMs;

export const Pressable = forwardRef<HTMLButtonElement, PressableProps>(function Pressable(
  {
    onActivate,
    onEscalate,
    onPeek,
    doubleTapMs = DEFAULT_DOUBLE_TAP_MS,
    longPressMs = DEFAULT_LONG_PRESS_MS,
    feedback = true,
    className,
    children,
    onKeyDown,
    style,
    ...rest
  },
  ref,
) {
  const lastTapAt = useRef(0);
  const longPressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const peeked = useRef(false);
  const pointerDownAt = useRef<{ x: number; y: number } | null>(null);

  const clearLongPress = useCallback(() => {
    if (longPressTimer.current !== null) {
      clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }
  }, []);

  useEffect(() => clearLongPress, [clearLongPress]);

  const handlePointerDown = useCallback(
    (event: ReactPointerEvent<HTMLButtonElement>) => {
      if (event.button !== 0 && event.pointerType === 'mouse') return;
      peeked.current = false;
      pointerDownAt.current = { x: event.clientX, y: event.clientY };
      if (!onPeek) return;
      clearLongPress();
      const point = { x: event.clientX, y: event.clientY };
      longPressTimer.current = setTimeout(() => {
        peeked.current = true;
        onPeek(point);
      }, longPressMs);
    },
    [clearLongPress, longPressMs, onPeek],
  );

  const handlePointerMove = useCallback(
    (event: ReactPointerEvent<HTMLButtonElement>) => {
      const start = pointerDownAt.current;
      if (!start || longPressTimer.current === null) return;
      const moved =
        Math.abs(event.clientX - start.x) > gesture.slopPx ||
        Math.abs(event.clientY - start.y) > gesture.slopPx;
      if (moved) clearLongPress();
    },
    [clearLongPress],
  );

  const handlePointerUp = useCallback(
    (event: ReactPointerEvent<HTMLButtonElement>) => {
      clearLongPress();
      pointerDownAt.current = null;
      if (peeked.current) {
        peeked.current = false;
        return;
      }
      if (event.button !== 0 && event.pointerType === 'mouse') return;

      const now = Date.now();
      const sinceLast = now - lastTapAt.current;

      if (onEscalate && sinceLast < doubleTapMs) {
        lastTapAt.current = 0;
        onEscalate();
        return;
      }

      lastTapAt.current = now;
      onActivate?.({ pointerType: event.pointerType });
    },
    [clearLongPress, doubleTapMs, onActivate, onEscalate],
  );

  const handlePointerCancel = useCallback(() => {
    clearLongPress();
    pointerDownAt.current = null;
    peeked.current = false;
  }, [clearLongPress]);

  const handleContextMenu = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      if (!onPeek) return;
      event.preventDefault();
      onPeek({ x: event.clientX, y: event.clientY });
    },
    [onPeek],
  );

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLButtonElement>) => {
      onKeyDown?.(event);
      if (event.defaultPrevented) return;
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        onActivate?.({ pointerType: 'keyboard' });
      } else if (event.key === 'f' || event.key === 'F') {
        // Keyboard equivalent of the double tap.
        onEscalate?.();
      } else if (event.key === 'ContextMenu' || (event.shiftKey && event.key === 'F10')) {
        const rect = event.currentTarget.getBoundingClientRect();
        onPeek?.({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 });
      }
    },
    [onActivate, onEscalate, onKeyDown, onPeek],
  );

  return (
    <button
      ref={ref}
      type="button"
      className={cn(
        // `k-no-callout` suppresses the iOS long-press image sheet so a held
        // press reaches `onPeek` instead of Safari's own menu.
        'focus-ring k-no-callout relative select-none touch-manipulation',
        feedback && 'k-pressable',
        className,
      )}
      style={
        feedback
          ? ({ ...style, '--k-press-scale': String(pressScale) } as CSSProperties)
          : style
      }
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerCancel}
      onPointerLeave={handlePointerCancel}
      onContextMenu={handleContextMenu}
      onKeyDown={handleKeyDown}
      {...rest}
    >
      {children}
    </button>
  );
});
