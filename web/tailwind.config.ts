import type { Config } from 'tailwindcss';
import { layout } from './src/design/tokens.g';

/**
 * Breakpoints are the one part of the theme that CSS custom properties cannot
 * express — a media query condition may not contain `var()`. So we derive them
 * from the generated token module instead. Still zero literals: every number
 * below comes out of `packages/tokens/tokens.json`.
 *
 * Everything else (colour, spacing, radius, type, shadow, easing, blur) is
 * declared in `src/styles/theme.css` via `@theme inline` so the utilities emit
 * `var(--k-*)` directly and the whole UI re-themes without a React re-render.
 */
const px = (value: number): string => `${value}px`;

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    screens: {
      sm: px(layout.breakpoint.sm),
      md: px(layout.breakpoint.md),
      lg: px(layout.breakpoint.lg),
      xl: px(layout.breakpoint.xl),
      '2xl': px(layout.breakpoint['2xl']),
    },
  },
};

export default config;
