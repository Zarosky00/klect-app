/**
 * Motion presets for framer-motion, derived entirely from the generated token
 * module. Nothing here invents a number.
 *
 * DESIGN_SYSTEM.md §3, the two absolute rules:
 *   1. Anything the finger drives is a spring. Anything the system drives is a curve.
 *   2. Nothing exceeds 480ms.
 */
import type { Transition, Variants } from 'framer-motion';
import { duration, ease, spring, stagger } from './tokens.g';

/** ms → s, because framer-motion speaks seconds. */
export const secs = (ms: number): number => ms / 1000;

type Cubic = [number, number, number, number];

const cubic = (value: readonly [number, number, number, number]): Cubic => [
  value[0],
  value[1],
  value[2],
  value[3],
];

export const easing = {
  standard: cubic(ease.standard),
  decelerate: cubic(ease.decelerate),
  accelerate: cubic(ease.accelerate),
  emphasized: cubic(ease.emphasized),
  overshoot: cubic(ease.overshoot),
  linear: cubic(ease.linear),
} as const;

/** System-driven transitions — curves. */
export const curve = {
  instant: { duration: secs(duration.instant), ease: easing.standard },
  fast: { duration: secs(duration.fast), ease: easing.standard },
  base: { duration: secs(duration.base), ease: easing.standard },
  medium: { duration: secs(duration.medium), ease: easing.emphasized },
  slow: { duration: secs(duration.slow), ease: easing.emphasized },
  deliberate: { duration: secs(duration.deliberate), ease: easing.emphasized },
  enter: { duration: secs(duration.base), ease: easing.decelerate },
  exit: { duration: secs(duration.fast), ease: easing.accelerate },
} as const satisfies Record<string, Transition>;

/** Finger-driven transitions — springs. */
export const springy = {
  snappy: { type: 'spring', ...spring.snappy },
  gentle: { type: 'spring', ...spring.gentle },
  bouncy: { type: 'spring', ...spring.bouncy },
  sheet: { type: 'spring', ...spring.sheet },
} as const satisfies Record<string, Transition>;

/** The reduced-motion substitute: keep confirmation, remove travel. */
export const reducedTransition: Transition = {
  duration: secs(duration.instant),
  ease: easing.linear,
};

/**
 * Design-system constants that DESIGN_SYSTEM.md specifies but `tokens.json`
 * does not yet carry. They live here — one module, one definition — so no
 * component ever types one of these numbers itself. If they are added to
 * `packages/tokens/tokens.json`, replace these with the generated values.
 */

/** Tap feedback: scale 0.97, snappy spring, no opacity change. (§3) */
export const pressScale = 0.97;

/** Like / save burst: icon overshoots to 1.25 then settles. (§3) */
export const burstScale = 1.25;

/** Burst animation length — capped well under the 480ms ceiling. */
export const burstMs = duration.slow;

/** Gesture timings and thresholds. (§4) */
export const gesture = {
  /**
   * The double-tap window. NOTE: a single tap is never delayed by it — see
   * `Pressable`. The window only decides whether a *second* tap escalates.
   */
  doubleTapMs: 260,
  /** Hold this long and the radial peek opens. */
  longPressMs: 420,
  /** Movement past this many CSS pixels cancels a pending long press. */
  slopPx: 8,
  /** Drag distance past which a sheet dismisses. */
  sheetDismissPx: 120,
  /** Or a flick faster than this, in px/s. */
  sheetDismissVelocity: 600,
} as const;

/** Grid item entry — staggered fade + rise, capped so a long list never crawls. */
export const gridStaggerDelay = (index: number): number =>
  secs(Math.min(index, stagger.max) * stagger.grid);

export const listStaggerDelay = (index: number): number =>
  secs(Math.min(index, stagger.max) * stagger.list);

export const fadeRise: Variants = {
  hidden: { opacity: 0, y: 8 },
  visible: { opacity: 1, y: 0 },
};

export const fade: Variants = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
};

export const scaleIn: Variants = {
  hidden: { opacity: 0, scale: 0.96 },
  visible: { opacity: 1, scale: 1 },
  exit: { opacity: 0, scale: 0.98 },
};

export const sheetUp: Variants = {
  hidden: { y: '100%' },
  visible: { y: 0 },
  exit: { y: '100%' },
};

export { duration, ease, spring, stagger };
