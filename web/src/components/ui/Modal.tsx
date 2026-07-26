'use client';

import { useCallback, useId, useRef, type ReactNode } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { curve, reducedTransition, scaleIn } from '@/design/motion';
import { cn } from '@/lib/cn';
import { IconButton } from './Button';
import { Portal, useEscape, useFocusTrap, useLockBodyScroll } from './overlay';

export type ModalSize = 'sm' | 'md' | 'lg' | 'full';

const sizeClasses: Record<ModalSize, string> = {
  sm: 'max-w-105',
  md: 'max-w-160',
  lg: 'w-[92vw] max-w-275',
  full: 'max-w-[96vw] h-[92vh]',
};

export interface ModalProps {
  open: boolean;
  onClose: () => void;
  title?: string;
  /** Hides the visible title but keeps it for screen readers. */
  titleHidden?: boolean;
  description?: string;
  size?: ModalSize;
  children: ReactNode;
  footer?: ReactNode;
  /** Clicking the scrim closes. Off for destructive flows. */
  dismissOnBackdrop?: boolean;
  className?: string;
  contentClassName?: string;
}

export function Modal({
  open,
  onClose,
  title,
  titleHidden = false,
  description,
  size = 'md',
  children,
  footer,
  dismissOnBackdrop = true,
  className,
  contentClassName,
}: ModalProps) {
  const panelRef = useRef<HTMLDivElement | null>(null);
  const titleId = useId();
  const descriptionId = useId();
  const reduced = useReducedMotion();

  useLockBodyScroll(open);
  useFocusTrap(panelRef, open);
  useEscape(open, onClose);

  const onBackdrop = useCallback(() => {
    if (dismissOnBackdrop) onClose();
  }, [dismissOnBackdrop, onClose]);

  return (
    <Portal>
      <AnimatePresence>
        {open ? (
          <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
            <motion.div
              className="absolute inset-0 bg-scrim"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={reduced ? reducedTransition : curve.fast}
              onClick={onBackdrop}
              aria-hidden
            />

            <motion.div
              ref={panelRef}
              role="dialog"
              aria-modal="true"
              aria-labelledby={title ? titleId : undefined}
              aria-describedby={description ? descriptionId : undefined}
              tabIndex={-1}
              variants={scaleIn}
              initial="hidden"
              animate="visible"
              exit="exit"
              transition={reduced ? reducedTransition : curve.medium}
              className={cn(
                'relative flex w-full flex-col overflow-hidden',
                'rounded-xl border border-line bg-surface-1 shadow-high',
                'max-h-[92vh]',
                sizeClasses[size],
                className,
              )}
            >
              {title ? (
                <header
                  className={cn(
                    'flex items-start gap-4 border-b border-line-subtle px-6 py-4',
                    titleHidden && 'sr-only',
                  )}
                >
                  <div className="min-w-0 flex-1">
                    <h2 id={titleId} className="font-display text-title1 text-ink">
                      {title}
                    </h2>
                    {description ? (
                      <p id={descriptionId} className="mt-1 text-callout text-ink-2">
                        {description}
                      </p>
                    ) : null}
                  </div>
                  <IconButton icon="close" label="Close" onClick={onClose} size="sm" />
                </header>
              ) : (
                <div className="absolute right-3 top-3 z-raised">
                  <IconButton icon="close" label="Close" onClick={onClose} size="sm" />
                </div>
              )}

              <div className={cn('min-h-0 flex-1 overflow-y-auto', contentClassName)}>
                {children}
              </div>

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
