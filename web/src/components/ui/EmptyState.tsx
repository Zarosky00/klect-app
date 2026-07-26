import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { Icon, type IconName } from './Icon';

/**
 * Display-serif headline + one sentence + one action.
 * Never an illustration-only dead end (DESIGN_SYSTEM §5).
 */
export interface EmptyStateProps {
  icon?: IconName;
  title: string;
  description?: string;
  action?: ReactNode;
  className?: string;
  compact?: boolean;
}

export function EmptyState({
  icon,
  title,
  description,
  action,
  className,
  compact = false,
}: EmptyStateProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center text-center',
        compact ? 'gap-3 px-6 py-10' : 'gap-4 px-6 py-20',
        className,
      )}
    >
      {icon ? (
        <span className="grid size-14 place-items-center rounded-full bg-surface-2 text-ink-3">
          <Icon name={icon} size="xl" />
        </span>
      ) : null}

      <h2
        className={cn(
          'font-display text-ink',
          compact ? 'text-title2' : 'text-display3',
        )}
      >
        {title}
      </h2>

      {description ? (
        <p className="readable-max text-callout text-ink-2">{description}</p>
      ) : null}

      {action ? <div className="mt-2">{action}</div> : null}
    </div>
  );
}
