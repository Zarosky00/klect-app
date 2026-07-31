// GENERATED FILE — DO NOT EDIT.
// Source: packages/tokens/tokens.json
// Regenerate: node packages/tokens/build.mjs

/* Values JS actually needs at runtime — motion for Framer-style springs,
   layout for masonry math. Colours stay in CSS custom properties so the
   theme can flip without a React re-render. */

export const duration = {
  "instant": 90,
  "fast": 140,
  "base": 200,
  "medium": 280,
  "slow": 360,
  "deliberate": 480
} as const;

export const ease = {
  "standard": [
    0.2,
    0,
    0,
    1
  ],
  "decelerate": [
    0.05,
    0.7,
    0.1,
    1
  ],
  "accelerate": [
    0.3,
    0,
    0.8,
    0.15
  ],
  "emphasized": [
    0.16,
    1,
    0.3,
    1
  ],
  "overshoot": [
    0.34,
    1.56,
    0.64,
    1
  ],
  "linear": [
    0,
    0,
    1,
    1
  ]
} as const;

export const spring = {
  "snappy": {
    "stiffness": 420,
    "damping": 32,
    "mass": 1
  },
  "gentle": {
    "stiffness": 220,
    "damping": 26,
    "mass": 1
  },
  "bouncy": {
    "stiffness": 380,
    "damping": 20,
    "mass": 1
  },
  "sheet": {
    "stiffness": 300,
    "damping": 30,
    "mass": 1
  }
} as const;

export const stagger = {
  "grid": 26,
  "list": 34,
  "max": 8
} as const;

/** Self-dismiss periods in ms. Not animation — the 480ms cap does not apply. */
export const dwell = {
  "banner": 5000
} as const;

/** Finger-driven commit thresholds: px, px/s and fractions of the dragged extent. */
export const drag = {
  "bannerLimit": 96,
  "commitFraction": 0.4,
  "pageCommitFraction": 0.25,
  "flingVelocityMin": 400,
  "overscrollMax": 32
} as const;

/** Async placeholder budgets in ms. */
export const timeout = {
  "thumbnail": 2000
} as const;

export const layout = {
  "breakpoint": {
    "xs": 0,
    "sm": 480,
    "md": 768,
    "lg": 1024,
    "xl": 1280,
    "2xl": 1600
  },
  "masonryColumns": {
    "xs": 2,
    "sm": 2,
    "md": 3,
    "lg": 4,
    "xl": 5,
    "2xl": 6
  },
  "masonryGutter": 10,
  "contentMaxWidth": 1320,
  "readableMaxWidth": 680,
  "tapTargetMin": 44,
  "bottomBarHeight": 60,
  "topBarHeight": 52,
  "callPillHeight": 48
} as const;

export const aspect = {
  "gridMin": 0.62,
  "gridMax": 1.6,
  "cover": 1,
  "banner": 3
} as const;

export const z = {
  "base": 0,
  "raised": 10,
  "sticky": 100,
  "chrome": 200,
  "sheet": 300,
  "modal": 400,
  "toast": 500,
  "immersive": 600
} as const;

/** Mirrors Layout.masonryColumns() in Dart. Keep the two in lockstep. */
export function masonryColumns(width: number): number {
  if (width >= 1600) return 6;
  if (width >= 1280) return 5;
  if (width >= 1024) return 4;
  if (width >= 768) return 3;
  if (width >= 480) return 2;
  if (width >= 0) return 2;
  return 2;
}
