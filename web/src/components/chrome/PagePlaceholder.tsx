import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { Icon, type IconName } from '@/components/ui/Icon';

/**
 * A declared-but-not-yet-built route.
 *
 * Every route in the product exists from day one so deep links, middleware
 * rules, sitemaps and navigation are all correct before the feature lands. A
 * feature agent replaces the whole page file; nothing here is meant to survive.
 */
export interface PagePlaceholderProps {
  title: string;
  description: string;
  icon?: IconName;
  /** What the feature agent building this route is expected to deliver. */
  contract?: string[];
  children?: ReactNode;
  className?: string;
}

export function PagePlaceholder({
  title,
  description,
  icon = 'grid',
  contract,
  children,
  className,
}: PagePlaceholderProps) {
  return (
    <div className={cn('content-max px-4 py-10 sm:px-6 md:py-16', className)}>
      <div className="readable-max flex flex-col items-start gap-4">
        <span className="grid size-12 place-items-center rounded-full bg-surface-2 text-ink-3">
          <Icon name={icon} size="xl" />
        </span>

        <h1 className="font-display text-display2 text-ink">{title}</h1>
        <p className="text-body text-ink-2">{description}</p>

        {contract && contract.length > 0 ? (
          <div className="mt-2 w-full rounded-lg border border-line-subtle bg-surface-1 p-5">
            <h2 className="text-label text-ink-3">This route will provide</h2>
            <ul className="mt-3 flex flex-col gap-2">
              {contract.map((line) => (
                <li key={line} className="flex items-start gap-2 text-callout text-ink-2">
                  <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-accent" />
                  {line}
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {children}
      </div>
    </div>
  );
}
