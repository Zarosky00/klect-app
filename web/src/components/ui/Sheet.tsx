'use client';

import { useId, useRef, type ReactNode } from 'react';
import { AnimatePresence, motion, useReducedMotion, type PanInfo } from 'framer-motion';
import { curve, gesture, reducedTransition, springy } from '@/design/motion';
import { cn } from '@/lib/cn';
import { Portal, useEscape, useFocusTrap, useLockBodyScroll } from './overlay';

export type SheetSide = 'bottom' | 'right';

export interface SheetProps {
  open: boolean;
  onClose: () => void;
  title?: string;
  description?: string;
  side?: SheetSide;
  children: ReactNode;
  footer?: ReactNode;
  className?: string;
}

/**
 * Drag-to-dismiss with velocity carry — the finger drives it, so it is a
 * spring, not a curve (DESIGN_SYSTEM §3).
 */
const DISMISS_DISTANCE = gesture.sheetDismissPx;
const DISMISS_VELOCITY = gesture.sheetDismissVelocity;

export function Sheet({
  open,
  onClose,
  title,
  description,
  side = 'bottom',
  children,
  footer,
  className,
}: SheetProps) {
  const panelRef = useRef<HTMLDivElement | null>(null);
  const titleId = useId();
  const descriptionId = useId();
  const reduced = useReducedMotion();

  useLockBodyScroll(open);
  useFocusTrap(panelRef, open);
  useEscape(open, onClose);

  const isBottom = side === 'bottom';

  const onDragEnd = (_event: unknown, info: PanInfo) => {
    const distance = isBottom ? info.offset.y : info.offset.x;
    const velocity = isBottom ? info.velocity.y : info.velocity.x;
    if (distance > DISMISS_DISTANCE || velocity > DISMISS_VELOCITY) onClose();
  };

  return (
    <Portal>
      <AnimatePresence>
        {open ? (
          <div className="fixed inset-0 z-sheet">
            <motion.div
              className="absolute inset-0 bg-scrim"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={reduced ? reducedTransition : curve.fast}
              onClick={onClose}
              aria-hidden
            />

            <motion.div
              ref={panelRef}
              role="dialog"
              aria-modal="true"
              aria-labelledby={title ? titleId : undefined}
              aria-describedby={description ? descriptionId : undefined}
              tabIndex={-1}
              drag={reduced ? false : isBottom ? 'y' : 'x'}
              dragConstraints={isBottom ? { top: 0, bottom: 0 } : { left: 0, right: 0 }}
              dragElastic={{ top: 0, bottom: 0.6, left: 0, right: 0.6 }}
              onDragEnd={onDragEnd}
              initial={isBottom ? { y: '100%' } : { x: '100%' }}
              animate={isBottom ? { y: 0 } : { x: 0 }}
              exit={isBottom ? { y: '100%' } : { x: '100%' }}
              transition={reduced ? reducedTransition : springy.sheet}
              className={cn(
                'absolute flex flex-col border-line bg-surface-1 shadow-high',
                isBottom
                  ? 'inset-x-0 bottom-0 max-h-[88vh] rounded-t-2xl border-t'
                  : 'inset-y-0 right-0 w-full max-w-110 border-l',
                className,
              )}
            >
              {isBottom ? (
                <div className="flex justify-center pt-3" aria-hidden>
                  <span className="h-1 w-10 rounded-full bg-line-strong" />
                </div>
              ) : null}

              {title ? (
                <header className="px-6 pb-4 pt-4">
                  <h2 id={titleId} className="font-display text-title1 text-ink">
                    {title}
                  </h2>
                  {description ? (
                    <p id={descriptionId} className="mt-1 text-callout text-ink-2">
                      {description}
                    </p>
                  ) : null}
                </header>
              ) : null}

              <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6">{children}</div>

              {footer ? (
                <footer className="flex items-center justify-end gap-3 border-t border-line-subtle px-6 py-4">
                  {footer}
                </footer>
              ) : null}
            </motion.div>
          </div>
        ) : null}
      </AnimatePresence>
    </Portal>
  );
}
