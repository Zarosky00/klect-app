'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { curve, reducedTransition, springy } from '@/design/motion';
import { cn } from '@/lib/cn';
import { entityHref, type EntityType } from '@/lib/entities';
import { SITE_URL } from '@/lib/env';
import { Icon, type IconName } from '@/components/ui/Icon';
import { Portal, useEscape } from '@/components/ui/overlay';
import { ReportDialog } from '@/components/ui/ReportDialog';
import { useEntitySocial } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * The long-press destination: a radial quick-action peek — like · save · repost
 * · share · report (DESIGN_SYSTEM §4).
 *
 * It opens at the pointer, so the finger is already inside the ring. Every
 * action is also reachable from the keyboard: the ring is a real menu, arrow
 * keys move through it, Enter fires.
 */

export interface PeekMenuProps {
  open: boolean;
  onClose: () => void;
  position: { x: number; y: number } | null;
  type: EntityType;
  id: string;
  title?: string;
}

interface PeekAction {
  key: string;
  icon: IconName;
  label: string;
  active?: boolean;
  /** Literal class strings so Tailwind can see them at build time. */
  tone: string;
  hoverTone: string;
  run: () => void;
}

/** Ring geometry in pixels — layout maths, not a design token. */
const RADIUS = 74;
const BUTTON = 52;

export function PeekMenu({ open, onClose, position, type, id, title }: PeekMenuProps) {
  const social = useEntitySocial(type, id);
  const { user } = useSession();
  const { toast, success, fromError } = useToast();
  const reduced = useReducedMotion();
  const [reporting, setReporting] = useState(false);
  const [focused, setFocused] = useState(0);

  useEscape(open, onClose);

  const requireAuth = useCallback((): boolean => {
    if (user) return true;
    toast({
      title: 'Sign in to do that',
      description: 'Collecting, liking and reposting need an account.',
      tone: 'accent',
      action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
    });
    return false;
  }, [toast, user]);

  const share = useCallback(async () => {
    const url = `${SITE_URL}${entityHref(type, id)}`;
    try {
      if (typeof navigator !== 'undefined' && navigator.share) {
        await navigator.share({ title: title ?? 'Klect', url });
        return;
      }
      await navigator.clipboard.writeText(url);
      success('Link copied');
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') return;
      fromError(error);
    }
  }, [fromError, id, success, title, type]);

  const actions = useMemo<PeekAction[]>(
    () => [
      {
        key: 'like',
        icon: 'heart',
        label: social.liked ? 'Unlike' : 'Like',
        active: social.liked,
        tone: 'text-like',
        hoverTone: 'hover:text-like',
        run: () => {
          if (requireAuth()) social.like();
          onClose();
        },
      },
      {
        key: 'save',
        icon: 'bookmark',
        label: social.saved ? 'Remove from saved' : 'Save',
        active: social.saved,
        tone: 'text-save',
        hoverTone: 'hover:text-save',
        run: () => {
          if (requireAuth()) social.save();
          onClose();
        },
      },
      {
        key: 'repost',
        icon: 'repost',
        label: social.reposted ? 'Undo repost' : 'Repost',
        active: social.reposted,
        tone: 'text-repost',
        hoverTone: 'hover:text-repost',
        run: () => {
          if (requireAuth()) social.repost();
          onClose();
        },
      },
      {
        key: 'share',
        icon: 'share',
        label: 'Share',
        tone: 'text-share',
        hoverTone: 'hover:text-ink',
        run: () => {
          void share();
          onClose();
        },
      },
      {
        key: 'report',
        icon: 'flag',
        label: 'Report',
        tone: 'text-danger',
        hoverTone: 'hover:text-danger',
        run: () => {
          if (requireAuth()) setReporting(true);
          onClose();
        },
      },
    ],
    [onClose, requireAuth, share, social],
  );

  useEffect(() => {
    if (open) setFocused(0);
  }, [open]);

  const onKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
        event.preventDefault();
        setFocused((current) => (current + 1) % actions.length);
      } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
        event.preventDefault();
        setFocused((current) => (current - 1 + actions.length) % actions.length);
      } else if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        actions[focused]?.run();
      }
    },
    [actions, focused],
  );

  // Keep the ring on screen even when the press lands near an edge.
  const anchor = useMemo(() => {
    if (!position) return { x: 0, y: 0 };
    const margin = RADIUS + BUTTON;
    const width = typeof window === 'undefined' ? margin * 2 : window.innerWidth;
    const height = typeof window === 'undefined' ? margin * 2 : window.innerHeight;
    return {
      x: Math.min(Math.max(position.x, margin), Math.max(margin, width - margin)),
      y: Math.min(Math.max(position.y, margin), Math.max(margin, height - margin)),
    };
  }, [position]);

  return (
    <>
      <Portal>
        <AnimatePresence>
          {open && position ? (
            <div className="fixed inset-0 z-sheet">
              <motion.div
                className="absolute inset-0 bg-scrim"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={reduced ? reducedTransition : curve.fast}
                onClick={onClose}
                onContextMenu={(event) => {
                  event.preventDefault();
                  onClose();
                }}
                aria-hidden
              />

              <motion.div
                role="menu"
                aria-label="Quick actions"
                tabIndex={-1}
                ref={(node) => {
                  node?.focus();
                }}
                onKeyDown={onKeyDown}
                className="absolute"
                style={{ left: anchor.x, top: anchor.y }}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.9 }}
                transition={reduced ? reducedTransition : springy.snappy}
              >
                {actions.map((action, index) => {
                  // Half a circle opening upward keeps the finger clear of the ring.
                  const angle = Math.PI + (Math.PI * index) / (actions.length - 1);
                  const x = Math.cos(angle) * RADIUS;
                  const y = Math.sin(angle) * RADIUS;
                  return (
                    <motion.button
                      key={action.key}
                      type="button"
                      role="menuitem"
                      aria-label={action.label}
                      title={action.label}
                      onClick={action.run}
                      onMouseEnter={() => setFocused(index)}
                      className={cn(
                        'glass focus-ring absolute grid place-items-center rounded-full border shadow-mid',
                        'transition-colors dur-fast ease-standard',
                        focused === index ? 'border-accent text-ink' : 'border-line',
                        action.active ? action.tone : 'text-ink-2',
                        action.hoverTone,
                      )}
                      style={{
                        width: BUTTON,
                        height: BUTTON,
                        marginLeft: -BUTTON / 2,
                        marginTop: -BUTTON / 2,
                      }}
                      initial={{ x: 0, y: 0, opacity: 0 }}
                      animate={{ x, y, opacity: 1 }}
                      exit={{ x: 0, y: 0, opacity: 0 }}
                      transition={
                        reduced
                          ? reducedTransition
                          : { ...springy.snappy, delay: index * 0.02 }
                      }
                    >
                      <Icon name={action.icon} size="lg" filled={action.active} />
                    </motion.button>
                  );
                })}

                <span
                  className="glass pointer-events-none absolute -translate-x-1/2 translate-y-4 whitespace-nowrap rounded-full border border-line px-3 py-1 text-caption text-ink"
                  aria-hidden
                >
                  {actions[focused]?.label ?? 'Quick actions'}
                </span>
              </motion.div>
            </div>
          ) : null}
        </AnimatePresence>
      </Portal>

      <ReportDialog
        open={reporting}
        onClose={() => setReporting(false)}
        target={{ kind: 'entity', type, id }}
        {...(title === undefined ? {} : { subject: title })}
      />
    </>
  );
}
