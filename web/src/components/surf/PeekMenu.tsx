'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { Icon, type IconName } from '@/components/ui/Icon';
import { Portal, useEscape } from '@/components/ui/overlay';
import { ReportDialog } from '@/components/ui/ReportDialog';
import { curve, reducedTransition, springy } from '@/design/motion';
import { cn } from '@/lib/cn';
import { entityHref, type EntityType } from '@/lib/entities';
import { SITE_URL } from '@/lib/env';
import { useEntitySocial } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import type { SocialSeed } from '@/lib/interactions';

/**
 * The long-press / right-click peek: like · save · repost · share · report,
 * laid out on an arc around the press point.
 *
 * "Hidden but easily accessible" — the actions never occupy the card at rest,
 * and they are one gesture away when you want them (DESIGN_SYSTEM §4).
 */

export interface PeekTarget {
  type: EntityType;
  id: string;
  title: string;
  seed?: SocialSeed;
  ownerUsername?: string | null;
}

export interface PeekMenuProps {
  target: PeekTarget | null;
  position: { x: number; y: number } | null;
  onClose: () => void;
}

interface PeekAction {
  key: string;
  icon: IconName;
  label: string;
  /** Full class strings — Tailwind only sees classes it can read literally. */
  tone: string;
  hoverTone: string;
  active?: boolean;
  run: () => void;
}

/** Radius of the arc and the button box, both on the 4px token ramp. */
const RADIUS_STEPS = 22; // × --k-space-1 (4px) = 88px
const BUTTON_STEPS = 12; // × --k-space-1 (4px) = 48px

export function PeekMenu({ target, position, onClose }: PeekMenuProps) {
  const open = target !== null && position !== null;
  const { user } = useSession();
  const { toast, success, fromError } = useToast();
  const [reporting, setReporting] = useState(false);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const reduced = useReducedMotion();

  // The store keys on (type, id); an inert key while closed keeps hook order
  // stable without subscribing to anything real.
  const social = useEntitySocial(
    target?.type ?? 'item',
    target?.id ?? '',
    target?.seed,
  );

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
    if (!target) return;
    const url = `${SITE_URL}${entityHref(target.type, target.id)}`;
    try {
      if (typeof navigator !== 'undefined' && navigator.share) {
        await navigator.share({ title: target.title, url });
        return;
      }
      await navigator.clipboard.writeText(url);
      success('Link copied');
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') return;
      fromError(error);
    }
  }, [fromError, success, target]);

  const actions = useMemo<PeekAction[]>(() => {
    if (!target) return [];
    return [
      {
        key: 'like',
        icon: 'heart',
        label: social.liked ? 'Unlike' : 'Like',
        tone: 'text-like',
        hoverTone: 'hover:text-like',
        active: social.liked,
        run: () => {
          if (requireAuth()) social.like();
        },
      },
      {
        key: 'save',
        icon: 'bookmark',
        label: social.saved ? 'Remove from saved' : 'Save',
        tone: 'text-save',
        hoverTone: 'hover:text-save',
        active: social.saved,
        run: () => {
          if (requireAuth()) social.save();
        },
      },
      {
        key: 'repost',
        icon: 'repost',
        label: social.reposted ? 'Undo repost' : 'Repost',
        tone: 'text-repost',
        hoverTone: 'hover:text-repost',
        active: social.reposted,
        run: () => {
          if (requireAuth()) social.repost();
        },
      },
      {
        key: 'share',
        icon: 'share',
        label: 'Share',
        tone: 'text-share',
        hoverTone: 'hover:text-share',
        run: () => void share(),
      },
      {
        key: 'report',
        icon: 'flag',
        label: 'Report',
        tone: 'text-danger',
        hoverTone: 'hover:text-danger',
        run: () => {
          if (requireAuth()) setReporting(true);
        },
      },
    ];
  }, [requireAuth, share, social, target]);

  // Focus the first action so the peek is operable from the keyboard too.
  useEffect(() => {
    if (!open) return;
    const first = containerRef.current?.querySelector<HTMLButtonElement>('button');
    first?.focus({ preventScroll: true });
  }, [open]);

  const onKeyDown = useCallback((event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft' && event.key !== 'Tab') return;
    const buttons = Array.from(
      containerRef.current?.querySelectorAll<HTMLButtonElement>('button') ?? [],
    );
    if (buttons.length === 0) return;
    const current = buttons.indexOf(document.activeElement as HTMLButtonElement);
    const step = event.key === 'ArrowLeft' || (event.key === 'Tab' && event.shiftKey) ? -1 : 1;
    event.preventDefault();
    const next = (current + step + buttons.length) % buttons.length;
    buttons[next]?.focus({ preventScroll: true });
  }, []);

  const geometry = useMemo(() => {
    if (!position) return null;
    // Arc opens toward whichever side has room, so the peek never leaves the
    // viewport on an edge tile.
    const openLeft =
      typeof window !== 'undefined' && position.x > window.innerWidth * 0.6;
    const openUp =
      typeof window !== 'undefined' && position.y > window.innerHeight * 0.6;
    return { openLeft, openUp };
  }, [position]);

  return (
    <>
      <Portal>
        <AnimatePresence>
          {open && position && geometry ? (
            <div className="fixed inset-0 z-sheet" role="presentation">
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

              <div
                ref={containerRef}
                role="menu"
                aria-label={`Quick actions for ${target.title}`}
                onKeyDown={onKeyDown}
                className="absolute"
                style={{ left: position.x, top: position.y }}
              >
                {actions.map((action, index) => {
                  // Five actions spread over a quarter-turn fan.
                  const spread = Math.PI / 2;
                  const start = -spread / 2;
                  const step =
                    actions.length > 1 ? spread / (actions.length - 1) : 0;
                  const angle = start + step * index;
                  const radius = `calc(var(--k-space-1) * ${RADIUS_STEPS})`;
                  const dx = Math.sin(angle) * (geometry.openLeft ? -1 : 1);
                  const dy = -Math.cos(angle) * (geometry.openUp ? 1 : -1);

                  return (
                    <motion.button
                      key={action.key}
                      type="button"
                      role="menuitem"
                      aria-label={action.label}
                      title={action.label}
                      initial={{ opacity: 0, scale: 0.6, x: 0, y: 0 }}
                      animate={{
                        opacity: 1,
                        scale: 1,
                        x: reduced ? 0 : `calc(${radius} * ${dx.toFixed(4)})`,
                        y: reduced ? 0 : `calc(${radius} * ${dy.toFixed(4)})`,
                      }}
                      exit={{ opacity: 0, scale: 0.6, x: 0, y: 0 }}
                      transition={
                        reduced
                          ? reducedTransition
                          : { ...springy.bouncy, delay: index * 0.02 }
                      }
                      onClick={() => {
                        action.run();
                        if (action.key !== 'report') onClose();
                      }}
                      className={cn(
                        'focus-ring glass absolute grid -translate-x-1/2 -translate-y-1/2 place-items-center',
                        'rounded-full border border-line shadow-high',
                        'transition-colors dur-fast ease-standard',
                        action.active ? action.tone : cn('text-ink', action.hoverTone),
                      )}
                      style={{
                        width: `calc(var(--k-space-1) * ${BUTTON_STEPS})`,
                        height: `calc(var(--k-space-1) * ${BUTTON_STEPS})`,
                      }}
                    >
                      <Icon name={action.icon} size="lg" filled={action.active} />
                    </motion.button>
                  );
                })}
              </div>
            </div>
          ) : null}
        </AnimatePresence>
      </Portal>

      {target ? (
        <ReportDialog
          open={reporting}
          onClose={() => {
            setReporting(false);
            onClose();
          }}
          target={{ kind: 'entity', type: target.type, id: target.id }}
          subject={target.title}
        />
      ) : null}
    </>
  );
}
