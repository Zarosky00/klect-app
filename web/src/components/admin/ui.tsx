/**
 * Console primitives.
 *
 * The staff console is an operations tool, not a marketing surface: dense rows,
 * small type, tabular figures, keyboard affordances visible on every action.
 * It is still built from the same tokens as the rest of Klect — no component in
 * this directory contains a hex, a px, a duration or a curve.
 */
import Link from 'next/link';
import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { fullDateTime, shortTimeAgo } from '@/lib/format';
import { Icon, type IconName } from '@/components/ui/Icon';

/* ── numbers ──────────────────────────────────────────────────────────────
   Locale-independent grouping. `toLocaleString()` can disagree between the
   server render and the client hydrate, which React reports as a mismatch. */

export function groupDigits(value: number | null | undefined): string {
  const n = typeof value === 'number' && Number.isFinite(value) ? Math.trunc(value) : 0;
  const sign = n < 0 ? '-' : '';
  return sign + String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/**
 * The one number a view leads with. Sans, never the display serif — a serif
 * hero figure reads as decoration rather than data.
 *
 * Neither constant sets a colour: `cn()` is `clsx`, not `tailwind-merge`, so two
 * colour utilities in one class list would resolve by stylesheet order rather
 * than by call-site intent. Callers always name the colour.
 */
export const heroFigureClass =
  'font-sans text-display1 tabular [font-weight:var(--k-text-title1-weight)]';

export const statValueClass =
  'font-sans text-display3 tabular [font-weight:var(--k-text-title1-weight)]';

/* ── page shell ───────────────────────────────────────────────────────────── */

export interface AdminPageProps {
  title: string;
  description?: string;
  /** Controls that belong to the whole page, right-aligned in the title row. */
  actions?: ReactNode;
  /**
   * One filter row above everything it scopes — never a filter inside a card
   * (dataviz anti-pattern: per-chart filters).
   */
  toolbar?: ReactNode;
  children: ReactNode;
}

export function AdminPage({ title, description, actions, toolbar, children }: AdminPageProps) {
  return (
    <div className="flex min-w-0 flex-col gap-4 pb-16">
      <header className="flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
        <div className="min-w-0">
          <h1 className="font-display text-display3 text-ink">{title}</h1>
          {description ? <p className="mt-0.5 text-caption text-ink-2">{description}</p> : null}
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
      </header>

      {toolbar ? (
        <div className="flex flex-wrap items-center gap-2 rounded-md border border-line-subtle bg-surface-1 p-2">
          {toolbar}
        </div>
      ) : null}

      {children}
    </div>
  );
}

/* ── panel ────────────────────────────────────────────────────────────────── */

export interface PanelProps {
  title?: string;
  description?: string;
  icon?: IconName;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
  bodyClassName?: string;
}

export function Panel({
  title,
  description,
  icon,
  actions,
  children,
  className,
  bodyClassName,
}: PanelProps) {
  return (
    <section
      className={cn(
        'flex min-w-0 flex-col overflow-hidden rounded-md border border-line-subtle bg-surface-1',
        className,
      )}
    >
      {title ? (
        <header className="flex items-center gap-2 border-b border-line-subtle px-3 py-2">
          {icon ? (
            <span className="text-ink-3">
              <Icon name={icon} size="sm" />
            </span>
          ) : null}
          <div className="min-w-0 flex-1">
            <h2 className="truncate text-label text-ink">{title}</h2>
            {description ? (
              <p className="truncate text-caption text-ink-3">{description}</p>
            ) : null}
          </div>
          {actions ? <div className="flex shrink-0 items-center gap-1">{actions}</div> : null}
        </header>
      ) : null}

      <div className={cn('min-w-0', bodyClassName ?? 'p-3')}>{children}</div>
    </section>
  );
}

/* ── stat tile ────────────────────────────────────────────────────────────── */

export type StatTone = 'neutral' | 'accent' | 'danger' | 'warning' | 'success' | 'info';

const statToneClass: Record<StatTone, string> = {
  neutral: 'text-ink',
  accent: 'text-accent',
  danger: 'text-danger',
  warning: 'text-warning',
  success: 'text-success',
  info: 'text-info',
};

export interface StatTileProps {
  label: string;
  value: number | string;
  /** One short line under the value — a period, a share, a caveat. */
  sub?: string;
  tone?: StatTone;
  href?: string;
  /** Sparkline or meter slot. */
  trend?: ReactNode;
}

export function StatTile({ label, value, sub, tone = 'neutral', href, trend }: StatTileProps) {
  const body = (
    <>
      <span className="text-caption text-ink-2">{label}</span>
      <span className={cn(statValueClass, statToneClass[tone])}>
        {typeof value === 'number' ? groupDigits(value) : value}
      </span>
      {trend ? <span className="mt-1 block">{trend}</span> : null}
      {sub ? <span className="text-caption text-ink-3">{sub}</span> : null}
    </>
  );

  const base =
    'flex min-w-0 flex-col gap-0.5 rounded-md border border-line-subtle bg-surface-1 p-3';

  if (href) {
    return (
      <Link
        href={href}
        className={cn(
          base,
          'focus-ring transition-colors dur-fast ease-standard hover:border-line hover:bg-surface-2',
        )}
      >
        {body}
      </Link>
    );
  }

  return <div className={base}>{body}</div>;
}

/* ── badge ────────────────────────────────────────────────────────────────── */

export type BadgeTone = StatTone;

const badgeToneClass: Record<BadgeTone, string> = {
  neutral: 'border-line bg-surface-2 text-ink-2',
  accent: 'border-accent/40 bg-accent-subtle text-accent',
  danger: 'border-danger/40 bg-danger-subtle text-danger',
  warning: 'border-warning/40 bg-surface-2 text-warning',
  success: 'border-success/40 bg-repost-subtle text-success',
  info: 'border-info/40 bg-comment-subtle text-info',
};

export interface BadgeProps {
  children: ReactNode;
  tone?: BadgeTone;
  icon?: IconName;
  className?: string;
  title?: string;
}

export function Badge({ children, tone = 'neutral', icon, className, title }: BadgeProps) {
  return (
    <span
      title={title}
      className={cn(
        'inline-flex items-center gap-1 whitespace-nowrap rounded-xs border px-1.5 py-0.5 text-micro uppercase',
        badgeToneClass[tone],
        className,
      )}
    >
      {icon ? <Icon name={icon} size="xs" /> : null}
      {children}
    </span>
  );
}

/* ── keyboard hint ────────────────────────────────────────────────────────── */

export function Kbd({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <kbd
      className={cn(
        'inline-flex h-4 min-w-4 items-center justify-center rounded-xs border border-line',
        'bg-surface-2 px-1 font-mono text-micro tabular text-ink-3',
        className,
      )}
    >
      {children}
    </kbd>
  );
}

export function KeyboardLegend({
  hints,
  className,
}: {
  hints: Array<{ keys: string[]; label: string }>;
  className?: string;
}) {
  return (
    <ul className={cn('flex flex-wrap items-center gap-x-3 gap-y-1', className)}>
      {hints.map((hint) => (
        <li key={hint.label} className="flex items-center gap-1 text-caption text-ink-3">
          {hint.keys.map((key) => (
            <Kbd key={key}>{key}</Kbd>
          ))}
          <span>{hint.label}</span>
        </li>
      ))}
    </ul>
  );
}

/* ── time ─────────────────────────────────────────────────────────────────── */

export function TimeAgo({ value, className }: { value: string | null; className?: string }) {
  if (!value) return <span className={cn('text-ink-3', className)}>—</span>;
  return (
    <time dateTime={value} title={fullDateTime(value)} className={cn('tabular', className)}>
      {shortTimeAgo(value)}
    </time>
  );
}

/* ── dense table ──────────────────────────────────────────────────────────── */

export const tableClass = 'w-full min-w-max border-collapse text-caption';

/** Alignment is always named at the call site, for the same clsx reason. */
export const thClass =
  'sticky top-0 z-raised whitespace-nowrap border-b border-line-subtle bg-surface-1 px-3 py-2 text-micro uppercase text-ink-3';

export const tdClass = 'whitespace-nowrap border-b border-line-subtle px-3 py-2 align-middle';

export function TableScroll({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('min-w-0 overflow-x-auto', className)}>
      <table className={tableClass}>{children}</table>
    </div>
  );
}

/* ── label / value pairs, for detail panels ───────────────────────────────── */

export function Field({
  label,
  children,
  className,
}: {
  label: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex min-w-0 flex-col gap-0.5', className)}>
      <span className="text-micro uppercase text-ink-3">{label}</span>
      <span className="min-w-0 break-words text-caption text-ink">{children}</span>
    </div>
  );
}

/* ── inline notice, for the forbidden / degraded cases ────────────────────── */

export function Notice({
  tone = 'warning',
  icon = 'alert',
  title,
  children,
}: {
  tone?: BadgeTone;
  icon?: IconName;
  title: string;
  children?: ReactNode;
}) {
  return (
    <div
      role="status"
      className={cn(
        'flex items-start gap-2 rounded-md border px-3 py-2',
        badgeToneClass[tone],
      )}
    >
      <span className="mt-0.5 shrink-0">
        <Icon name={icon} size="sm" />
      </span>
      <div className="min-w-0">
        <p className="text-label">{title}</p>
        {children ? <div className="mt-0.5 text-caption">{children}</div> : null}
      </div>
    </div>
  );
}
