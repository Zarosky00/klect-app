'use client';

import { cn } from '@/lib/cn';

/**
 * The taste-overlap score, drawn on the match ramp.
 *
 * Colour alone never carries the meaning (DESIGN_SYSTEM §6): the arc length and
 * the printed percentage say the same thing, and the ring is labelled for
 * screen readers.
 */

export type MatchBand = 'low' | 'mid' | 'high' | 'peak';

/** Data binning, not design values — the colours themselves are all tokens. */
export function matchBand(score: number): MatchBand {
  if (score >= 0.8) return 'peak';
  if (score >= 0.6) return 'high';
  if (score >= 0.4) return 'mid';
  return 'low';
}

const bandClasses: Record<MatchBand, string> = {
  low: 'text-match-low',
  mid: 'text-match-mid',
  high: 'text-match-high',
  peak: 'text-match-peak',
};

export const BAND_LABELS: Record<MatchBand, string> = {
  low: 'Some overlap',
  mid: 'Good overlap',
  high: 'Strong overlap',
  peak: 'Uncanny overlap',
};

/** Ring geometry in SVG user units — pure layout maths. */
const RADIUS = 22;
const STROKE = 4;
const BOX = (RADIUS + STROKE) * 2;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

export interface MatchRingProps {
  /** 0..1 taste overlap from `get_matches`. */
  score: number;
  size?: number;
  className?: string;
}

export function MatchRing({ score, size = 56, className }: MatchRingProps) {
  const clamped = Math.min(1, Math.max(0, score));
  const percent = Math.round(clamped * 100);
  const band = matchBand(clamped);

  return (
    <span
      className={cn('relative inline-grid shrink-0 place-items-center', bandClasses[band], className)}
      style={{ width: size, height: size }}
      role="img"
      aria-label={`${percent}% taste match — ${BAND_LABELS[band].toLowerCase()}`}
      title={`${percent}% match`}
    >
      <svg viewBox={`0 0 ${BOX} ${BOX}`} width={size} height={size} aria-hidden>
        <circle
          cx={BOX / 2}
          cy={BOX / 2}
          r={RADIUS}
          fill="none"
          stroke="var(--k-surface-3)"
          strokeWidth={STROKE}
        />
        <circle
          cx={BOX / 2}
          cy={BOX / 2}
          r={RADIUS}
          fill="none"
          stroke="currentColor"
          strokeWidth={STROKE}
          strokeLinecap="round"
          strokeDasharray={CIRCUMFERENCE}
          strokeDashoffset={CIRCUMFERENCE * (1 - clamped)}
          transform={`rotate(-90 ${BOX / 2} ${BOX / 2})`}
          style={{ transition: 'stroke-dashoffset var(--k-dur-medium) var(--k-ease-emphasized)' }}
        />
      </svg>
      <span className="tabular absolute text-micro font-semibold">{percent}</span>
    </span>
  );
}
