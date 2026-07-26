'use client';

import Link from 'next/link';
import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { Icon, type IconName } from './Icon';

export type ChipTone = 'neutral' | 'accent' | 'success' | 'danger' | 'info';

const toneClasses: Record<ChipTone, { off: string; on: string }> = {
  neutral: {
    off: 'border-line bg-surface-2 text-ink-2 hover:bg-surface-3 hover:text-ink',
    on: 'border-accent bg-accent-subtle text-accent',
  },
  accent: {
    off: 'border-line bg-surface-2 text-ink-2 hover:text-accent',
    on: 'border-accent bg-accent text-ink-on-accent',
  },
  success: {
    off: 'border-line bg-surface-2 text-ink-2',
    on: 'border-success bg-repost-subtle text-success',
  },
  danger: {
    off: 'border-line bg-surface-2 text-ink-2',
    on: 'border-danger bg-danger-subtle text-danger',
  },
  info: {
    off: 'border-line bg-surface-2 text-ink-2',
    on: 'border-info bg-comment-subtle text-info',
  },
};

const base = cn(
  'inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5',
  'text-label transition-colors dur-fast ease-standard whitespace-nowrap',
);

export interface ChipProps {
  children: ReactNode;
  tone?: ChipTone;
  selected?: boolean;
  icon?: IconName;
  onClick?: () => void;
  onRemove?: () => void;
  href?: string;
  className?: string;
  disabled?: boolean;
}

export function Chip({
  children,
  tone = 'neutral',
  selected = false,
  icon,
  onClick,
  onRemove,
  href,
  className,
  disabled,
}: ChipProps) {
  const classes = cn(
    base,
    selected ? toneClasses[tone].on : toneClasses[tone].off,
    (onClick || href) && 'k-pressable focus-ring cursor-pointer',
    disabled && 'pointer-events-none opacity-[var(--k-opacity-disabled)]',
    className,
  );

  const inner = (
    <>
      {icon ? <Icon name={icon} size="xs" filled={selected} /> : null}
      {children}
      {onRemove ? (
        <span
          role="button"
          tabIndex={0}
          aria-label="Remove"
          className="focus-ring -mr-1 ml-0.5 rounded-full p-0.5 text-ink-3 hover:text-ink"
          onClick={(event) => {
            event.preventDefault();
            event.stopPropagation();
            onRemove();
          }}
          onKeyDown={(event) => {
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault();
              event.stopPropagation();
              onRemove();
            }
          }}
        >
          <Icon name="close" size="xs" />
        </span>
      ) : null}
    </>
  );

  if (href) {
    return (
      <Link href={href} className={classes}>
        {inner}
      </Link>
    );
  }

  if (onClick) {
    return (
      <button
        type="button"
        onClick={onClick}
        aria-pressed={selected}
        disabled={disabled}
        className={classes}
      >
        {inner}
      </button>
    );
  }

  return <span className={classes}>{inner}</span>;
}

export interface ChipGroupProps {
  children: ReactNode;
  className?: string;
  /** Renders as a tab-like radio group for filters. */
  label?: string;
}

export function ChipGroup({ children, className, label }: ChipGroupProps) {
  return (
    <div
      role={label ? 'group' : undefined}
      aria-label={label}
      className={cn('flex flex-wrap items-center gap-2', className)}
    >
      {children}
    </div>
  );
}
