'use client';

/**
 * Console charts.
 *
 * Built to the dataviz method, and to Klect's token rule at the same time —
 * which is why none of these are canvas or a charting library. Every mark is a
 * box or an SVG stroke whose colour, radius, spacing and stroke width resolve to
 * a `--k-*` custom property, so the charts re-theme with the rest of the app and
 * contain no literal design value.
 *
 * Decisions worth stating:
 * - Both charts plot **magnitude**, not identity, so both are sequential: one
 *   hue (oxblood accent) for every mark. A value-ramp across nominal categories
 *   would double-encode length as hue, which is an anti-pattern.
 * - Bars cap at 24px and carry a 4px rounded data-end, square at the baseline.
 * - Adjacent bars are separated by a 2px gap in the surface colour, never a stroke.
 * - Gridlines are solid hairlines one step off the surface, never dashed.
 * - Values are never printed on every mark: the axis, the hover tooltip and the
 *   table view carry them, and the table view is one click away (plus always
 *   present for screen readers).
 */

import { useMemo, useState } from 'react';
import { cn } from '@/lib/cn';
import { calendarDate, fullDateTime } from '@/lib/format';
import { Icon } from '@/components/ui/Icon';
import { groupDigits, tdClass, thClass } from './ui';

const DAY_MS = 86_400_000;

const dayStart = (day: string): number => Date.parse(`${day}T00:00:00Z`);
const dayLabel = (day: string): string => calendarDate(`${day}T00:00:00Z`);

export interface DayPoint {
  day: string;
  n: number;
}

/**
 * `admin_metrics().signups_14d` only emits days that actually had a signup, so
 * a quiet week would otherwise render as four bars pretending to be fourteen.
 * `endDay` is passed in from the server render so the window is identical on
 * both sides of hydration.
 */
export function fillDays(series: DayPoint[], endDay: string, count: number): DayPoint[] {
  const byDay = new Map<string, number>();
  for (const point of series) {
    if (typeof point?.day === 'string') byDay.set(point.day.slice(0, 10), Number(point.n) || 0);
  }
  const end = dayStart(endDay);
  const days: DayPoint[] = [];
  for (let index = count - 1; index >= 0; index -= 1) {
    const day = new Date(end - index * DAY_MS).toISOString().slice(0, 10);
    days.push({ day, n: byDay.get(day) ?? 0 });
  }
  return days;
}

/** Round a max up to a clean axis top so the tick labels read as round numbers. */
function niceCeiling(value: number): number {
  if (value <= 0) return 1;
  const magnitude = 10 ** Math.floor(Math.log10(value));
  for (const step of [1, 2, 2.5, 5, 10]) {
    const candidate = step * magnitude;
    if (candidate >= value) return candidate;
  }
  return 10 * magnitude;
}

/* ── column chart: signups over 14 days ───────────────────────────────────── */

export interface DayColumnsProps {
  series: DayPoint[];
  /** ISO `YYYY-MM-DD` for the right-hand edge of the window. */
  endDay: string;
  days?: number;
  /** Names the single series — there is no legend, per the one-series rule. */
  label: string;
}

export function DayColumns({ series, endDay, days = 14, label }: DayColumnsProps) {
  const [active, setActive] = useState<number | null>(null);
  const [asTable, setAsTable] = useState(false);

  const points = useMemo(() => fillDays(series, endDay, days), [days, endDay, series]);
  const total = points.reduce((sum, point) => sum + point.n, 0);
  const peak = points.reduce((max, point) => Math.max(max, point.n), 0);
  const ceiling = niceCeiling(peak);
  const peakIndex = points.findIndex((point) => point.n === peak && peak > 0);

  const first = points[0];
  const last = points[points.length - 1];

  return (
    <figure className="flex min-w-0 flex-col gap-2">
      <figcaption className="flex items-baseline justify-between gap-2">
        <span className="text-caption text-ink-2">
          {label} — <span className="tabular text-ink">{groupDigits(total)}</span> total
        </span>
        <button
          type="button"
          onClick={() => setAsTable((value) => !value)}
          aria-pressed={asTable}
          className="focus-ring inline-flex items-center gap-1 rounded-xs px-1 py-0.5 text-micro uppercase text-ink-3 transition-colors dur-fast ease-standard hover:text-ink"
        >
          <Icon name="grid" size="xs" />
          {asTable ? 'Chart' : 'Table'}
        </button>
      </figcaption>

      {asTable ? (
        <DayTable points={points} label={label} />
      ) : (
        <>
          <div className="flex min-w-0 gap-2">
            {/* y axis — only the round numbers the marks are not labelled with */}
            <div
              aria-hidden
              className="flex h-40 shrink-0 flex-col justify-between text-right text-micro tabular text-ink-3"
            >
              <span>{groupDigits(ceiling)}</span>
              <span>{groupDigits(ceiling / 2)}</span>
              <span>0</span>
            </div>

            <div className="relative min-w-0 flex-1">
              <div aria-hidden className="absolute inset-0 flex flex-col justify-between">
                <span className="block border-t border-line-subtle" />
                <span className="block border-t border-line-subtle" />
                <span className="block border-t border-line" />
              </div>

              <div className="relative flex h-40 items-stretch gap-0.5">
                {points.map((point, index) => {
                  const height = ceiling > 0 ? (point.n / ceiling) * 100 : 0;
                  const isActive = active === index;
                  return (
                    <button
                      key={point.day}
                      type="button"
                      onPointerEnter={() => setActive(index)}
                      onPointerLeave={() => setActive((value) => (value === index ? null : value))}
                      onFocus={() => setActive(index)}
                      onBlur={() => setActive((value) => (value === index ? null : value))}
                      aria-label={`${dayLabel(point.day)}: ${groupDigits(point.n)}`}
                      className="focus-ring group flex min-w-0 flex-1 cursor-default items-end rounded-xs"
                    >
                      <span
                        aria-hidden
                        style={{ height: `${height}%` }}
                        className={cn(
                          'mx-auto block w-full max-w-6 rounded-t-xs transition-colors dur-fast ease-standard',
                          point.n === 0 ? 'bg-line' : isActive ? 'bg-accent-hover' : 'bg-accent',
                        )}
                      />
                    </button>
                  );
                })}
              </div>

              {active !== null && points[active] ? (
                <span
                  role="status"
                  style={{ left: `${((active + 0.5) / points.length) * 100}%` }}
                  className={cn(
                    'pointer-events-none absolute top-0 z-raised whitespace-nowrap rounded-xs',
                    'border border-line bg-surface-3 px-1.5 py-0.5 text-micro text-ink shadow-mid',
                    active === 0
                      ? 'translate-x-0'
                      : active === points.length - 1
                        ? '-translate-x-full'
                        : '-translate-x-1/2',
                  )}
                >
                  {dayLabel(points[active].day)} ·{' '}
                  <span className="tabular">{groupDigits(points[active].n)}</span>
                </span>
              ) : null}
            </div>
          </div>

          <div className="flex items-center justify-between pl-8 text-micro tabular text-ink-3">
            <span>{first ? dayLabel(first.day) : ''}</span>
            {peakIndex >= 0 && points[peakIndex] ? (
              <span className="text-ink-2">
                peak {groupDigits(peak)} · {dayLabel(points[peakIndex].day)}
              </span>
            ) : null}
            <span>{last ? dayLabel(last.day) : ''}</span>
          </div>

          {/* The values are never gated behind the tooltip. */}
          <div className="sr-only">
            <DayTable points={points} label={label} />
          </div>
        </>
      )}
    </figure>
  );
}

function DayTable({ points, label }: { points: DayPoint[]; label: string }) {
  return (
    <div className="max-h-64 min-w-0 overflow-auto">
      <table className="w-full border-collapse text-caption">
        <caption className="sr-only">{label} by day</caption>
        <thead>
          <tr>
            <th className={cn(thClass, 'text-left')}>Day</th>
            <th className={cn(thClass, 'text-right')}>Count</th>
          </tr>
        </thead>
        <tbody>
          {points.map((point) => (
            <tr key={point.day}>
              <td className={tdClass}>
                <time dateTime={point.day} title={fullDateTime(`${point.day}T00:00:00Z`)}>
                  {dayLabel(point.day)}
                </time>
              </td>
              <td className={cn(tdClass, 'text-right tabular')}>{groupDigits(point.n)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ── horizontal bar list: magnitude across named categories ───────────────── */

export interface BarRow {
  key: string;
  label: string;
  value: number;
  href?: string;
}

export function BarList({ rows, emptyLabel = 'Nothing to show.' }: { rows: BarRow[]; emptyLabel?: string }) {
  const max = rows.reduce((peak, row) => Math.max(peak, row.value), 0);

  if (rows.length === 0) {
    return <p className="py-4 text-center text-caption text-ink-3">{emptyLabel}</p>;
  }

  return (
    <ul className="flex flex-col gap-2.5">
      {rows.map((row) => (
        <li key={row.key} className="flex min-w-0 flex-col gap-1">
          <div className="flex min-w-0 items-baseline justify-between gap-2">
            <span className="truncate text-caption text-ink-2">{row.label}</span>
            <span className="shrink-0 tabular text-caption text-ink">{groupDigits(row.value)}</span>
          </div>
          <span className="block h-2 w-full overflow-hidden rounded-r-xs bg-surface-2">
            <span
              aria-hidden
              style={{ width: max > 0 ? `${(row.value / max) * 100}%` : '0%' }}
              className="block h-full rounded-r-xs bg-accent"
            />
          </span>
        </li>
      ))}
    </ul>
  );
}

/* ── sparkline: the trend slot of a stat tile ─────────────────────────────── */

export function Sparkline({ values, className }: { values: number[]; className?: string }) {
  const points = values.length > 0 ? values : [0];
  const max = Math.max(...points, 1);
  const step = points.length > 1 ? 100 / (points.length - 1) : 0;
  const path = points
    .map((value, index) => `${(index * step).toFixed(2)},${(100 - (value / max) * 100).toFixed(2)}`)
    .join(' ');
  const lastValue = points[points.length - 1] ?? 0;

  return (
    <span className={cn('relative block h-6 w-full', className)} aria-hidden>
      <svg
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
        className="size-full stroke-accent"
        role="presentation"
      >
        <polyline
          points={path}
          fill="none"
          vectorEffect="non-scaling-stroke"
          strokeLinecap="round"
          strokeLinejoin="round"
          style={{ strokeWidth: 'var(--k-stroke-thick)' }}
        />
      </svg>
      <span
        className="absolute size-2 -translate-x-1/2 translate-y-1/2 rounded-full bg-accent ring-2 ring-surface-1"
        style={{ left: '100%', bottom: `${(lastValue / max) * 100}%` }}
      />
    </span>
  );
}
