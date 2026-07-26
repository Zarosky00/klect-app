'use client';

import { cn } from '@/lib/cn';
import { toKlectError } from '@/lib/errors';
import { Button } from './Button';
import { Icon } from './Icon';

/** Every error state offers a way forward. No dead ends (CHECKLIST H). */
export interface ErrorStateProps {
  error?: unknown;
  title?: string;
  description?: string;
  onRetry?: () => void;
  retryLabel?: string;
  className?: string;
  compact?: boolean;
}

export function ErrorState({
  error,
  title,
  description,
  onRetry,
  retryLabel = 'Try again',
  className,
  compact = false,
}: ErrorStateProps) {
  const klect = error === undefined ? null : toKlectError(error);
  const heading = title ?? (klect?.kind === 'network' ? 'You are offline' : 'That did not load');
  const body =
    description ??
    klect?.message ??
    'Something went wrong on our side. It is usually temporary.';
  const canRetry = onRetry && (klect === null || klect.retryable);

  return (
    <div
      role="alert"
      className={cn(
        'flex flex-col items-center justify-center gap-4 text-center',
        compact ? 'px-6 py-10' : 'px-6 py-20',
        className,
      )}
    >
      <span className="grid size-14 place-items-center rounded-full bg-danger-subtle text-danger">
        <Icon name="alert" size="xl" />
      </span>

      <h2 className={cn('font-display text-ink', compact ? 'text-title2' : 'text-display3')}>
        {heading}
      </h2>
      <p className="readable-max text-callout text-ink-2">{body}</p>

      {canRetry ? (
        <Button variant="secondary" onClick={onRetry} iconLeft="repost">
          {retryLabel}
        </Button>
      ) : null}
    </div>
  );
}
