'use client';

import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { curve, reducedTransition, scaleIn } from '@/design/motion';
import { cn } from '@/lib/cn';
import { Icon, type IconName } from '@/components/ui/Icon';

/**
 * The "…" menu. Secondary actions live here rather than in a visible row —
 * the most common action is one gesture away, the rest are two, nothing is
 * three (DESIGN_SYSTEM §4).
 *
 * Roving focus with the arrow keys, Escape closes and returns focus to the
 * trigger, and a click anywhere else dismisses.
 */

export interface OverflowItem {
  key: string;
  label: string;
  icon?: IconName;
  onSelect: () => void;
  destructive?: boolean;
  disabled?: boolean;
}

export interface OverflowMenuProps {
  items: OverflowItem[];
  label?: string;
  align?: 'start' | 'end';
  className?: string;
}

export function OverflowMenu({
  items,
  label = 'More options',
  align = 'end',
  className,
}: OverflowMenuProps) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const rootRef = useRef<HTMLDivElement | null>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const menuId = useId();
  const reduced = useReducedMotion();

  const close = useCallback(
    (restoreFocus = true) => {
      setOpen(false);
      if (restoreFocus) triggerRef.current?.focus();
    },
    [],
  );

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) close(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    return () => document.removeEventListener('pointerdown', onPointerDown);
  }, [close, open]);

  useEffect(() => {
    if (!open) return;
    itemRefs.current[active]?.focus();
  }, [active, open]);

  const enabled = items.filter((item) => !item.disabled);

  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setActive((current) => (current + 1) % Math.max(1, items.length));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setActive((current) => (current - 1 + items.length) % Math.max(1, items.length));
    } else if (event.key === 'Home') {
      event.preventDefault();
      setActive(0);
    } else if (event.key === 'End') {
      event.preventDefault();
      setActive(Math.max(0, items.length - 1));
    }
  };

  return (
    <div ref={rootRef} className={cn('relative', className)}>
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        aria-label={label}
        title={label}
        onClick={() => {
          setActive(0);
          setOpen((current) => !current);
        }}
        className={cn(
          'k-pressable focus-ring inline-flex size-10 items-center justify-center rounded-full',
          'border border-line bg-surface-2 text-ink-2',
          'transition-colors dur-fast ease-standard hover:bg-surface-3 hover:text-ink',
        )}
      >
        <Icon name="more" size="lg" />
      </button>

      <AnimatePresence>
        {open ? (
          <motion.div
            id={menuId}
            role="menu"
            aria-label={label}
            onKeyDown={onKeyDown}
            variants={scaleIn}
            initial="hidden"
            animate="visible"
            exit="exit"
            transition={reduced ? reducedTransition : curve.fast}
            className={cn(
              'absolute top-12 z-raised min-w-56 overflow-hidden rounded-lg',
              'border border-line bg-surface-2 py-1 shadow-high',
              align === 'end' ? 'right-0' : 'left-0',
            )}
          >
            {items.map((item, index) => (
              <button
                key={item.key}
                ref={(node) => {
                  itemRefs.current[index] = node;
                }}
                type="button"
                role="menuitem"
                disabled={item.disabled}
                tabIndex={index === active ? 0 : -1}
                onMouseEnter={() => setActive(index)}
                onClick={() => {
                  close(false);
                  item.onSelect();
                }}
                className={cn(
                  'focus-ring flex w-full items-center gap-3 px-4 py-2.5 text-left text-callout',
                  'transition-colors dur-fast ease-standard',
                  item.destructive ? 'text-danger hover:bg-danger-subtle' : 'text-ink hover:bg-surface-3',
                  'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
                )}
              >
                {item.icon ? <Icon name={item.icon} size="md" /> : null}
                {item.label}
              </button>
            ))}
            {enabled.length === 0 ? (
              <p className="px-4 py-2.5 text-caption text-ink-3">Nothing to do here.</p>
            ) : null}
          </motion.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}
