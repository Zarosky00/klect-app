'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { adminMetrics } from '@/lib/api';
import { REPORT_REASON_LABELS, type ReportReason } from '@/lib/entities';
import { cn } from '@/lib/cn';
import { shortTimeAgo } from '@/lib/format';
import { routes } from '@/lib/routes';
import type { AdminMetrics } from '@/lib/types';
import { Button } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { useSupabase } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { BarList, DayColumns, Sparkline, fillDays, type BarRow } from './charts';
import {
  AdminPage,
  Badge,
  Panel,
  StatTile,
  groupDigits,
  heroFigureClass,
} from './ui';

export interface AdminDashboardProps {
  initialMetrics: AdminMetrics;
  /** `YYYY-MM-DD` for the right edge of the signup window, fixed by the server
   *  render so the chart is identical on both sides of hydration. */
  endDay: string;
}

export function AdminDashboard({ initialMetrics, endDay }: AdminDashboardProps) {
  const supabase = useSupabase();
  const toast = useToast();

  const [metrics, setMetrics] = useState<AdminMetrics>(initialMetrics);
  const [refreshing, setRefreshing] = useState(false);
  const [refreshedAt, setRefreshedAt] = useState<string | null>(null);
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    try {
      const next = await adminMetrics(supabase);
      setMetrics(next);
      setRefreshedAt(new Date().toISOString());
    } catch (error) {
      toast.fromError(error, { retry: () => void refresh() });
    } finally {
      setRefreshing(false);
    }
  }, [supabase, toast]);

  const { users, content, engagement, moderation, signups_14d: signups } = metrics;

  const reasonRows: BarRow[] = Object.entries(moderation.by_reason ?? {})
    .map(([reason, count]) => ({
      key: reason,
      label: REPORT_REASON_LABELS[reason as ReportReason] ?? reason,
      value: Number(count) || 0,
    }))
    .filter((row) => row.value > 0)
    .sort((a, b) => b.value - a.value);

  const weekTrend = fillDays(signups ?? [], endDay, 7).map((point) => point.n);
  const queueDepth = moderation.open + moderation.reviewing;

  return (
    <AdminPage
      title="Overview"
      description="Every figure comes from admin_metrics(). Nothing on this page is counted in the browser."
      actions={
        <>
          {mounted && refreshedAt ? (
            <span className="text-caption text-ink-3">
              updated {shortTimeAgo(refreshedAt)} ago
            </span>
          ) : null}
          <Button
            size="sm"
            variant="secondary"
            iconLeft="repost"
            loading={refreshing}
            onClick={() => void refresh()}
          >
            Refresh
          </Button>
        </>
      }
    >
      {/* Held at reduced opacity while refetching — never a skeleton flash. */}
      <div
        className={cn(
          'flex flex-col gap-4 transition-opacity dur-base ease-standard',
          refreshing && 'opacity-[var(--k-opacity-veil)]',
        )}
        aria-busy={refreshing}
      >
        {/* The one number the console leads with. */}
        <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]">
          <Link
            href={routes.adminReports}
            className={cn(
              'focus-ring group flex flex-col justify-between gap-2 rounded-md border p-4',
              'transition-colors dur-fast ease-standard',
              moderation.open > 0
                ? 'border-danger/40 bg-danger-subtle hover:border-danger'
                : 'border-line-subtle bg-surface-1 hover:bg-surface-2',
            )}
          >
            <span className="flex items-center gap-2 text-caption text-ink-2">
              <Icon name="flag" size="sm" />
              Reports waiting
            </span>
            <span className={cn(heroFigureClass, moderation.open > 0 ? 'text-danger' : 'text-ink')}>
              {groupDigits(moderation.open)}
            </span>
            <span className="flex flex-wrap items-center gap-2 text-caption text-ink-2">
              <span>{groupDigits(moderation.reviewing)} in review</span>
              <span aria-hidden className="text-ink-3">
                ·
              </span>
              <span>{groupDigits(moderation.actioned_7d)} actioned this week</span>
              <span className="ml-auto inline-flex items-center gap-1 text-ink-3 transition-colors dur-fast ease-standard group-hover:text-ink">
                Triage
                <Icon name="chevron-right" size="xs" />
              </span>
            </span>
          </Link>

          <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
            <StatTile label="Collectors" value={users.total} sub="all time" />
            <StatTile
              label="Suspended"
              value={users.suspended}
              tone={users.suspended > 0 ? 'danger' : 'neutral'}
              sub={`${percent(users.suspended, users.total)} of accounts`}
            />
            <StatTile
              label="New"
              value={users.new_7d}
              sub="last 7 days"
              trend={<Sparkline values={weekTrend} />}
            />
            <StatTile label="Active" value={users.active_24h} sub="seen in 24h" />
          </div>
        </section>

        <section className="grid gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
          <Panel
            title="Signups"
            description="New accounts per day, last 14 days"
            icon="activity"
          >
            <DayColumns series={signups ?? []} endDay={endDay} days={14} label="Signups" />
          </Panel>

          <Panel
            title="Moderation load"
            description="Open and reviewing reports, by reason"
            icon="flag"
            actions={
              queueDepth > 0 ? (
                <Badge tone={moderation.open > 0 ? 'danger' : 'neutral'}>
                  {groupDigits(queueDepth)} queued
                </Badge>
              ) : null
            }
          >
            <BarList rows={reasonRows} emptyLabel="Queue is clear." />
          </Panel>
        </section>

        <section className="grid gap-4 md:grid-cols-2">
          <Panel title="Content" description="Live rows, deleted excluded" icon="grid" bodyClassName="p-0">
            <NumberList
              rows={[
                { key: 'collections', label: 'Collections', value: content.collections },
                { key: 'subcollections', label: 'Subcollections', value: content.subcollections },
                { key: 'items', label: 'Items', value: content.items },
                { key: 'media', label: 'Photos', value: content.media },
                { key: 'posts', label: 'Posts', value: content.posts },
                { key: 'comments', label: 'Comments', value: content.comments },
                {
                  key: 'hidden',
                  label: 'Hidden by moderation',
                  value: content.hidden,
                  tone: content.hidden > 0 ? 'danger' : 'neutral',
                  href: `${routes.adminContent}?filter=hidden`,
                },
              ]}
            />
          </Panel>

          <Panel title="Engagement" description="All-time interaction volume" icon="heart" bodyClassName="p-0">
            <NumberList
              rows={[
                { key: 'likes', label: 'Likes', value: engagement.likes },
                { key: 'saves', label: 'Saves', value: engagement.saves },
                { key: 'reposts', label: 'Reposts', value: engagement.reposts },
                { key: 'follows', label: 'Follows', value: engagement.follows },
                { key: 'messages', label: 'Messages', value: engagement.messages },
                { key: 'calls', label: 'Calls', value: engagement.calls },
              ]}
            />
          </Panel>
        </section>
      </div>
    </AdminPage>
  );
}

function percent(part: number, whole: number): string {
  if (!whole) return '0%';
  const value = (part / whole) * 100;
  return `${value >= 10 || value === 0 ? Math.round(value) : Math.round(value * 10) / 10}%`;
}

interface NumberRow {
  key: string;
  label: string;
  value: number;
  tone?: 'neutral' | 'danger';
  href?: string;
}

function NumberList({ rows }: { rows: NumberRow[] }) {
  const rowClass =
    'flex items-baseline justify-between gap-3 border-b border-line-subtle px-3 py-2';

  return (
    <ul className="flex flex-col">
      {rows.map((row) => {
        const body = (
          <>
            <span className="min-w-0 truncate text-caption text-ink-2">{row.label}</span>
            <span
              className={cn(
                'shrink-0 tabular text-label',
                row.tone === 'danger' ? 'text-danger' : 'text-ink',
              )}
            >
              {groupDigits(row.value)}
            </span>
          </>
        );

        return (
          <li key={row.key} className="last:[&>*]:border-b-0">
            {row.href ? (
              <Link
                href={row.href}
                className={cn(
                  rowClass,
                  'focus-ring transition-colors dur-fast ease-standard hover:bg-surface-2',
                )}
              >
                {body}
              </Link>
            ) : (
              <div className={rowClass}>{body}</div>
            )}
          </li>
        );
      })}
    </ul>
  );
}
