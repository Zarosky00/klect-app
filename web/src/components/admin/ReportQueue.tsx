'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { adminListReports, adminResolveReport } from '@/lib/api';
import { cn } from '@/lib/cn';
import type { ReportStatus } from '@/lib/entities';
import { plural } from '@/lib/format';
import type { AdminReport } from '@/lib/types';
import { Button } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { useSupabase } from '@/providers/session-provider';
import { useAdminToast } from './useAdminToast';
import {
  MOD_ACTION_LABELS,
  modActionByHotkey,
  type ModActionSpec,
} from './actions';
import {
  REPORT_STATUSES,
  REPORT_STATUS_LABELS,
  countReportsByStatus,
  describeServerError,
  type AdminErrorInfo,
  type ReportCounts,
} from './data';
import { ReportRow, actionAvailable } from './ReportRow';
import { ResolveDialog, type ResolvePayload } from './ResolveDialog';
import { AdminPage, Badge, KeyboardLegend, groupDigits } from './ui';

const PAGE = 25;

export interface ReportQueueProps {
  initialStatus: ReportStatus;
  initialReports: AdminReport[];
  initialCounts: ReportCounts;
  /** Set when the server read failed — the client shows the database's words. */
  initialError?: AdminErrorInfo | null;
}

interface Pending {
  report: AdminReport;
  spec: ModActionSpec;
}

export function ReportQueue({
  initialStatus,
  initialReports,
  initialCounts,
  initialError = null,
}: ReportQueueProps) {
  const supabase = useSupabase();
  const { toast, fail } = useAdminToast();

  const [status, setStatus] = useState<ReportStatus>(initialStatus);
  const [reports, setReports] = useState<AdminReport[]>(initialReports);
  const [counts, setCounts] = useState<ReportCounts>(initialCounts);
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [exhausted, setExhausted] = useState(initialReports.length < PAGE);
  const [error, setError] = useState<AdminErrorInfo | null>(initialError);

  const [activeIndex, setActiveIndex] = useState(0);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [pending, setPending] = useState<Pending | null>(null);

  // Skip the first fetch: the server already rendered `initialStatus`.
  const hydrated = useRef(false);

  const refreshCounts = useCallback(async () => {
    try {
      setCounts(await countReportsByStatus(supabase));
    } catch {
      // A counter that fails to refresh is not worth interrupting triage for.
    }
  }, [supabase]);

  const load = useCallback(
    async (next: ReportStatus) => {
      setLoading(true);
      setError(null);
      try {
        const rows = await adminListReports(supabase, { status: next, limit: PAGE, offset: 0 });
        setReports(rows);
        setExhausted(rows.length < PAGE);
        setActiveIndex(0);
        setExpandedId(null);
      } catch (thrown) {
        setError(describeServerError(thrown));
        setReports([]);
      } finally {
        setLoading(false);
      }
    },
    [supabase],
  );

  useEffect(() => {
    if (!hydrated.current) {
      hydrated.current = true;
      return;
    }
    void load(status);
  }, [load, status]);

  const loadMore = useCallback(async () => {
    setLoadingMore(true);
    try {
      const rows = await adminListReports(supabase, {
        status,
        limit: PAGE,
        offset: reports.length,
      });
      const seen = new Set(reports.map((row) => row.id));
      const fresh = rows.filter((row) => !seen.has(row.id));
      setReports((current) => [...current, ...fresh]);
      setExhausted(rows.length < PAGE);
    } catch (thrown) {
      fail(thrown, () => void loadMore());
    } finally {
      setLoadingMore(false);
    }
  }, [fail, reports, status, supabase]);

  /* ── resolve ──────────────────────────────────────────────────────────── */

  const applyAction = useCallback(
    async (report: AdminReport, spec: ModActionSpec, payload: ResolvePayload) => {
      const nextStatus: ReportStatus = spec.action === 'none' ? 'dismissed' : 'actioned';
      const queueTab = status === 'open' || status === 'reviewing';

      // Mirror of the RPC: resolving one report auto-resolves every other open
      // report on the same target, so those rows leave the queue too.
      const siblings = queueTab
        ? reports.filter((row) => {
            if (row.id === report.id) return false;
            if (report.entity_id) {
              return row.entity_type === report.entity_type && row.entity_id === report.entity_id;
            }
            return Boolean(report.subject && row.subject?.id === report.subject.id);
          })
        : [];

      const drop = new Set<string>(siblings.map((row) => row.id));
      if (nextStatus !== status) drop.add(report.id);

      const snapshot = reports;
      if (drop.size > 0) setReports((current) => current.filter((row) => !drop.has(row.id)));
      setBusyId(report.id);
      setExpandedId((current) => (current === report.id && drop.has(report.id) ? null : current));

      try {
        await adminResolveReport(supabase, {
          reportId: report.id,
          action: spec.action,
          ...(payload.reason === undefined ? {} : { reason: payload.reason }),
          ...(payload.suspendDays === undefined ? {} : { suspendDays: payload.suspendDays }),
        });

        toast.success(
          MOD_ACTION_LABELS[spec.action],
          siblings.length > 0
            ? `Also resolved ${siblings.length} related ${plural(siblings.length, 'report')} on the same target.`
            : report.subject
              ? `@${report.subject.username} · report closed.`
              : 'Report closed.',
        );
        void refreshCounts();
      } catch (thrown) {
        setReports(snapshot);
        fail(thrown, () => void applyAction(report, spec, payload));
      } finally {
        setBusyId(null);
      }
    },
    [fail, refreshCounts, reports, status, supabase, toast],
  );

  const requestAction = useCallback(
    (report: AdminReport, spec: ModActionSpec, forceDialog = false) => {
      if (busyId) return;
      if (!actionAvailable(report, spec)) {
        toast.error(
          `${spec.label} does not apply here`,
          spec.needs === 'entity'
            ? 'This report has no content attached.'
            : 'This report has no account attached.',
        );
        return;
      }
      if (spec.confirm || forceDialog) {
        setPending({ report, spec });
        return;
      }
      void applyAction(report, spec, {});
    },
    [applyAction, busyId, toast],
  );

  /* ── keyboard ─────────────────────────────────────────────────────────── */

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (pending) return; // the dialog owns the keyboard
      if (event.metaKey || event.ctrlKey || event.altKey) return;

      const target = event.target as HTMLElement | null;
      if (
        target &&
        (target.isContentEditable ||
          /^(input|textarea|select)$/i.test(target.tagName))
      ) {
        return;
      }

      if (reports.length === 0) return;
      const current = reports[Math.min(activeIndex, reports.length - 1)];
      if (!current) return;

      if (event.key === 'j' || event.key === 'ArrowDown') {
        event.preventDefault();
        setActiveIndex((index) => Math.min(index + 1, reports.length - 1));
        return;
      }
      if (event.key === 'k' || event.key === 'ArrowUp') {
        event.preventDefault();
        setActiveIndex((index) => Math.max(index - 1, 0));
        return;
      }
      if (event.key === 'Enter') {
        event.preventDefault();
        setExpandedId((id) => (id === current.id ? null : current.id));
        return;
      }
      if (event.key === 'Escape') {
        setExpandedId(null);
        return;
      }

      // `code` rather than `key` so Shift+1 is still "1" on every layout.
      const digit = /^Digit([1-9])$/.exec(event.code)?.[1];
      if (!digit) return;
      const spec = modActionByHotkey(digit);
      if (!spec) return;
      event.preventDefault();
      requestAction(current, spec, event.shiftKey);
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [activeIndex, pending, reports, requestAction]);

  /* ── render ───────────────────────────────────────────────────────────── */

  const activeReport = reports[Math.min(activeIndex, Math.max(reports.length - 1, 0))] ?? null;

  return (
    <AdminPage
      title="Report queue"
      description="Priority first, then newest. Resolving one report closes every other open report about the same target."
      actions={
        <Button
          size="sm"
          variant="secondary"
          iconLeft="repost"
          loading={loading}
          onClick={() => {
            void load(status);
            void refreshCounts();
          }}
        >
          Refresh
        </Button>
      }
      toolbar={
        <>
          <div role="tablist" aria-label="Report status" className="flex flex-wrap gap-1">
            {REPORT_STATUSES.map((value) => {
              const selected = value === status;
              return (
                <button
                  key={value}
                  role="tab"
                  type="button"
                  aria-selected={selected}
                  onClick={() => setStatus(value)}
                  className={cn(
                    'focus-ring inline-flex items-center gap-1.5 rounded-xs px-2 py-1 text-label',
                    'transition-colors dur-fast ease-standard',
                    selected
                      ? 'bg-surface-3 text-ink'
                      : 'text-ink-2 hover:bg-surface-2 hover:text-ink',
                  )}
                >
                  {REPORT_STATUS_LABELS[value]}
                  <span
                    className={cn(
                      'tabular text-caption',
                      value === 'open' && counts.open > 0 ? 'text-danger' : 'text-ink-3',
                    )}
                  >
                    {groupDigits(counts[value])}
                  </span>
                </button>
              );
            })}
          </div>

          <KeyboardLegend
            className="ml-auto"
            hints={[
              { keys: ['j', 'k'], label: 'move' },
              { keys: ['↵'], label: 'expand' },
              { keys: ['1–7'], label: 'action' },
              { keys: ['⇧', '1–7'], label: 'action with a reason' },
            ]}
          />
        </>
      }
    >
      <div className="overflow-hidden rounded-md border border-line-subtle bg-surface-1">
        {loading ? (
          <div className="flex flex-col gap-3 p-3">
            {Array.from({ length: 5 }, (_, index) => (
              <SkeletonRow key={index} />
            ))}
          </div>
        ) : error ? (
          <ErrorState
            title={error.refused ? 'Refused by the server' : 'The queue would not load'}
            description={error.message}
            onRetry={() => void load(status)}
            compact
          />
        ) : reports.length === 0 ? (
          <EmptyState
            icon="flag"
            compact
            title={status === 'open' ? 'Queue is clear' : `Nothing ${REPORT_STATUS_LABELS[status].toLowerCase()}`}
            description={
              status === 'open'
                ? 'No open reports. New ones land here the moment they are filed.'
                : 'Reports move into this tab as they are resolved.'
            }
          />
        ) : (
          <>
            <ul role="list" className="flex flex-col">
              {reports.map((report, index) => (
                <ReportRow
                  key={report.id}
                  report={report}
                  index={index}
                  active={index === Math.min(activeIndex, reports.length - 1)}
                  expanded={expandedId === report.id}
                  busy={busyId === report.id}
                  onActivate={setActiveIndex}
                  onToggle={(id) => setExpandedId((current) => (current === id ? null : id))}
                  onAction={(target, spec) => requestAction(target, spec)}
                />
              ))}
            </ul>

            <div className="flex items-center justify-between gap-3 border-t border-line-subtle px-3 py-2">
              <span className="text-caption text-ink-3">
                {groupDigits(reports.length)} of {groupDigits(counts[status])} shown
              </span>
              {exhausted ? (
                <Badge tone="neutral">
                  <Icon name="check" size="xs" />
                  end of queue
                </Badge>
              ) : (
                <Button size="sm" variant="ghost" loading={loadingMore} onClick={() => void loadMore()}>
                  Load more
                </Button>
              )}
            </div>
          </>
        )}
      </div>

      <ResolveDialog
        open={pending !== null}
        spec={pending?.spec ?? null}
        subject={
          pending?.report.subject
            ? `@${pending.report.subject.username}`
            : pending?.report.preview?.title
              ? pending.report.preview.title
              : 'this report'
        }
        note="Resolving this also resolves every other open report about the same target."
        onCancel={() => setPending(null)}
        onConfirm={async (payload) => {
          const current = pending;
          setPending(null);
          if (current) await applyAction(current.report, current.spec, payload);
        }}
      />

      {activeReport ? (
        <p className="sr-only" aria-live="polite">
          Row {Math.min(activeIndex, reports.length - 1) + 1} of {reports.length} selected.
        </p>
      ) : null}
    </AdminPage>
  );
}
