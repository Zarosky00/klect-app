'use client';

import { useEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import { createPortal } from 'react-dom';

/** Freezes the page behind an overlay without the layout jumping. */
export function useLockBodyScroll(active: boolean): void {
  useEffect(() => {
    if (!active || typeof document === 'undefined') return;
    const { body } = document;
    const previousOverflow = body.style.overflow;
    const previousPadding = body.style.paddingRight;
    const scrollbar = window.innerWidth - document.documentElement.clientWidth;
    body.style.overflow = 'hidden';
    if (scrollbar > 0) body.style.paddingRight = `${scrollbar}px`;
    return () => {
      body.style.overflow = previousOverflow;
      body.style.paddingRight = previousPadding;
    };
  }, [active]);
}

const FOCUSABLE =
  'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Keeps Tab inside the overlay and returns focus where it came from. Without
 * this, keyboard users fall straight through into the page behind.
 */
export function useFocusTrap(
  containerRef: RefObject<HTMLElement | null>,
  active: boolean,
): void {
  const restoreTo = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!active) return;
    const container = containerRef.current;
    if (!container) return;

    restoreTo.current = document.activeElement as HTMLElement | null;

    const focusables = (): HTMLElement[] =>
      Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE));

    const first = focusables()[0];
    (first ?? container).focus({ preventScroll: true });

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Tab') return;
      const items = focusables();
      const firstItem = items[0];
      const lastItem = items[items.length - 1];
      if (!firstItem || !lastItem) {
        event.preventDefault();
        return;
      }
      if (event.shiftKey && document.activeElement === firstItem) {
        event.preventDefault();
        lastItem.focus();
      } else if (!event.shiftKey && document.activeElement === lastItem) {
        event.preventDefault();
        firstItem.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown);
    const restore = restoreTo.current;
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      restore?.focus({ preventScroll: true });
    };
  }, [active, containerRef]);
}

export function useEscape(active: boolean, onEscape: () => void): void {
  const handler = useRef(onEscape);
  handler.current = onEscape;

  useEffect(() => {
    if (!active) return;
    const listener = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        handler.current();
      }
    };
    document.addEventListener('keydown', listener);
    return () => document.removeEventListener('keydown', listener);
  }, [active]);
}

/** Renders into <body> so overlays escape any `overflow: hidden` ancestor. */
export function Portal({ children }: { children: ReactNode }) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  if (!mounted || typeof document === 'undefined') return null;
  return createPortal(children, document.body);
}
