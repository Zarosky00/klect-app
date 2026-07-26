import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

export interface AuthCardProps {
  title: string;
  description?: string;
  children: ReactNode;
  footer?: ReactNode;
  className?: string;
  wide?: boolean;
}

export function AuthCard({
  title,
  description,
  children,
  footer,
  className,
  wide = false,
}: AuthCardProps) {
  return (
    <section
      className={cn(
        'w-full rounded-xl border border-line bg-surface-1 p-6 shadow-mid sm:p-8',
        wide ? 'max-w-160' : 'max-w-105',
        className,
      )}
    >
      <h1 className="font-display text-display3 text-ink">{title}</h1>
      {description ? <p className="mt-2 text-callout text-ink-2">{description}</p> : null}

      <div className="mt-6">{children}</div>

      {footer ? (
        <div className="mt-6 border-t border-line-subtle pt-4 text-callout text-ink-2">
          {footer}
        </div>
      ) : null}
    </section>
  );
}
