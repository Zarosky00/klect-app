'use client';

import { forwardRef, useEffect, useRef, useState } from 'react';
import type { ButtonHTMLAttributes, CSSProperties } from 'react';
import { burstMs, burstScale, pressScale } from '@/design/motion';
import { cn } from '@/lib/cn';
import { compactCount } from '@/lib/format';
import { Icon, type IconName } from './Icon';

/**
 * Tabular digits, icon left, colour only once the viewer has acted.
 * The number rolls vertically — DESIGN_SYSTEM §3: never fade the whole number.
 */

export interface RollingCountProps {
  value: number;
  className?: string;
}

export function RollingCount({ value, className }: RollingCountProps) {
  const text = compactCount(value);
  const previous = useRef(value);
  const [direction, setDirection] = useState<'up' | 'down'>('up');

  useEffect(() => {
    if (value !== previous.current) {
      setDirection(value > previous.current ? 'up' : 'down');
      previous.current = value;
    }
  }, [value]);

  return (
    /* Each character is keyed by its own value, so a changed digit remounts and
       re-enters while unchanged digits sit still. */
    <span className={cn('k-count-roll tabular', className)} aria-hidden>
      {[...text].map((character, index) => (
        <span
          key={`${index}-${character}`}
          className={direction === 'up' ? 'k-roll-up' : 'k-roll-down'}
        >
          {character}
        </span>
      ))}
    </span>
  );
}

export type CountPillTone = 'like' | 'save' | 'repost' | 'comment' | 'share' | 'view' | 'neutral';

const toneActiveClasses: Record<CountPillTone, string> = {
  like: 'text-like',
  save: 'text-save',
  repost: 'text-repost',
  comment: 'text-comment',
  share: 'text-share',
  view: 'text-ink-2',
  neutral: 'text-accent',
};

const toneHoverClasses: Record<CountPillTone, string> = {
  like: 'hover:text-like',
  save: 'hover:text-save',
  repost: 'hover:text-repost',
  comment: 'hover:text-comment',
  share: 'hover:text-ink',
  view: '',
  neutral: 'hover:text-ink',
};

export interface CountPillProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  icon: IconName;
  count: number;
  /** Announced to screen readers, e.g. "Like — 12 likes". */
  label: string;
  tone?: CountPillTone;
  active?: boolean;
  /** Renders as static text rather than a control (view counts). */
  readOnly?: boolean;
  hideZero?: boolean;
  compact?: boolean;
  /** When present, the number is its own control (for engagement details). */
  onCountClick?: () => void;
  countLabel?: string;
}

export const CountPill = forwardRef<HTMLButtonElement, CountPillProps>(function CountPill(
  {
    icon,
    count,
    label,
    tone = 'neutral',
    active = false,
    readOnly = false,
    hideZero = false,
    compact = false,
    onCountClick,
    countLabel,
    className,
    disabled,
    style,
    onClick,
    ...rest
  },
  ref,
) {
  const [bursting, setBursting] = useState(false);
  const wasActive = useRef(active);

  useEffect(() => {
    if (active && !wasActive.current) {
      setBursting(true);
      const timer = setTimeout(() => setBursting(false), burstMs);
      wasActive.current = active;
      return () => clearTimeout(timer);
    }
    wasActive.current = active;
    return undefined;
  }, [active]);

  const showCount = !hideZero || count > 0;

  const iconContent = (
    <span className={cn('inline-flex', bursting && 'k-burst')}>
      <Icon name={icon} filled={active} size={compact ? 'sm' : 'md'} />
    </span>
  );
  const countContent = showCount ? (
    <RollingCount value={count} className={compact ? 'text-micro' : 'text-count'} />
  ) : null;
  const content = <>{iconContent}{countContent}</>;

  const shared = cn(
    'inline-flex items-center gap-1.5 rounded-full transition-colors dur-fast ease-standard',
    compact ? 'px-1.5 py-0.5' : 'px-2 py-1',
    active ? toneActiveClasses[tone] : 'text-ink-2',
    className,
  );

  if (readOnly) {
    return (
      <span className={shared} title={label} aria-label={label} role="img">
        {content}
      </span>
    );
  }

  if (onCountClick) {
    return (
      <span className={cn('inline-flex items-center', active ? toneActiveClasses[tone] : 'text-ink-2', className)}>
        <button
          ref={ref}
          type="button"
          onClick={onClick}
          disabled={disabled}
          aria-pressed={active}
          aria-label={label}
          title={label}
          className={cn(
            'k-pressable focus-ring inline-flex items-center rounded-full',
            compact ? 'px-1.5 py-0.5' : 'px-2 py-1',
            !active && toneHoverClasses[tone],
            'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
          )}
          style={
            {
              ...style,
              '--k-press-scale': String(pressScale),
              '--k-burst-scale': String(burstScale),
            } as CSSProperties
          }
          {...rest}
        >
          {iconContent}
        </button>
        {showCount ? (
          <button
            type="button"
            onClick={onCountClick}
            aria-label={countLabel ?? `${count} ${label.toLowerCase()}`}
            title={countLabel ?? `${count} ${label.toLowerCase()}`}
            className={cn(
              'k-pressable focus-ring rounded-full transition-colors dur-fast ease-standard',
              compact ? 'px-1 py-0.5' : 'px-1.5 py-1',
              toneHoverClasses[tone],
            )}
          >
            {countContent}
          </button>
        ) : null}
      </span>
    );
  }

  return (
    <button
      ref={ref}
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={active}
      aria-label={label}
      title={label}
      className={cn(
        'k-pressable focus-ring',
        shared,
        !active && toneHoverClasses[tone],
        'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
      )}
      style={
        {
          ...style,
          '--k-press-scale': String(pressScale),
          '--k-burst-scale': String(burstScale),
        } as CSSProperties
      }
      {...rest}
    >
      {content}
    </button>
  );
});
