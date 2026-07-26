'use client';

import Link from 'next/link';
import { useEffect, useRef } from 'react';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, REPORT_REASON_LABELS, entityHref } from '@/lib/entities';
import { handle, truncate } from '@/lib/format';
import { routes } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import type { AdminReport } from '@/lib/types';
import { Avatar } from '@/components/ui/Avatar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import { ErrorState } from '@/components/ui/ErrorState';
import { MOD_ACTIONS, type ModActionSpec } from './actions';
import {
  DossierContent,
  DossierHeader,
  DossierHistory,
  DossierSkeleton,
  DossierStats,
  useUserDetail,
} from './UserDossier';
import { Badge, Kbd, Panel, TimeAgo, groupDigits } from './ui';

function priorityTone(priority: number): 'danger' | 'warning' | 'neutral' {
  if (priority >= 3) return 'danger';
  if (priority === 2) return 'warning';
  return 'neutral';
}

export interface ReportRowProps {
  report: AdminReport;
  index: number;
  active: boolean;
  expanded: boolean;
  busy: boolean;
  onActivate: (index: number) => void;
  onToggle: (id: string) => void;
  onAction: (report: AdminReport, spec: ModActionSpec) => void;
}

export function ReportRow({
  report,
  index,
  active,
  expanded,
  busy,
  onActivate,
  onToggle,
  onAction,
}: ReportRowProps) {
  const ref = useRef<HTMLLIElement | null>(null);

  useEffect(() => {
    if (active) ref.current?.scrollIntoView({ block: 'nearest' });
  }, [active]);

  const subject = report.subject;
  const reporter = report.reporter;
  const preview = report.preview;
  const previewText = preview?.title ?? preview?.description ?? null;

  return (
    <li
      ref={ref}
      data-active={active}
      className={cn(
        'group border-b border-line-subtle last:border-b-0',
        'transition-colors dur-fast ease-standard',
        'data-[active=true]:bg-surface-2',
        busy && 'opacity-[var(--k-opacity-veil)]',
      )}
    >
      <div
        role="presentation"
        onMouseDown={() => onActivate(index)}
        className="flex min-w-0 items-start gap-2 px-2 py-2"
      >
        <button
          type="button"
          aria-expanded={expanded}
          aria-label={expanded ? 'Collapse report' : 'Expand report'}
          onClick={() => onToggle(report.id)}
          className="focus-ring mt-0.5 grid size-6 shrink-0 place-items-center rounded-xs text-ink-3 transition-colors dur-fast ease-standard hover:bg-surface-3 hover:text-ink"
        >
          <Icon
            name="chevron-right"
            size="sm"
            className={cn(
              'transition-transform dur-fast ease-standard',
              expanded && 'rotate-90',
            )}
          />
        </button>

        <div className="flex min-w-0 flex-1 flex-col gap-1">
          <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
            <Badge tone={priorityTone(report.priority)} title={`Priority ${report.priority}`}>
              P{report.priority}
            </Badge>
            <Badge tone="warning">{REPORT_REASON_LABELS[report.reason] ?? report.reason}</Badge>

            {report.entity_type ? (
              <span className="text-micro uppercase text-ink-3">
                {ENTITY_LABEL[report.entity_type]}
              </span>
            ) : report.message_id ? (
              <span className="text-micro uppercase text-ink-3">Message</span>
            ) : (
              <span className="text-micro uppercase text-ink-3">Account</span>
            )}

            <span className="ml-auto shrink-0 text-caption text-ink-3">
              <TimeAgo value={report.created_at} />
            </span>
          </div>

          <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
            {subject ? (
              <span className="flex min-w-0 items-center gap-1.5">
                <Avatar
                  path={subject.avatar_path}
                  name={subject.display_name}
                  username={subject.username}
                  size="xs"
                />
                <span className="truncate text-caption text-ink">{handle(subject.username)}</span>
                {subject.is_suspended ? (
                  <Badge tone="danger" icon="lock">
                    suspended
                  </Badge>
                ) : null}
                {report.subject_open_reports > 1 ? (
                  <Badge
                    tone="danger"
                    title={`${report.subject_open_reports} open reports against this account`}
                  >
                    {groupDigits(report.subject_open_reports)} open
                  </Badge>
                ) : null}
              </span>
            ) : (
              <span className="text-caption text-ink-3">no account attached</span>
            )}

            {reporter ? (
              <span className="truncate text-caption text-ink-3">
                by {handle(reporter.username)}
              </span>
            ) : null}

            {previewText ? (
              <span className="min-w-0 flex-1 truncate text-caption text-ink-2">
                “{truncate(previewText, 90)}”
              </span>
            ) : null}
          </div>
        </div>

        <div
          className={cn(
            'flex shrink-0 items-center gap-0.5 transition-opacity dur-fast ease-standard',
            'opacity-0 group-hover:opacity-100 group-focus-within:opacity-100',
            'group-data-[active=true]:opacity-100',
          )}
        >
          {MOD_ACTIONS.map((spec) => (
            <ActionButton
              key={spec.action}
              spec={spec}
              report={report}
              disabled={busy}
              onAction={onAction}
            />
          ))}
        </div>
      </div>

      {expanded ? <ReportDetail report={report} /> : null}
    </li>
  );
}

/* ── one dense icon button per action, with its key on the tooltip ────────── */

const actionToneClass: Record<string, string> = {
  neutral: 'text-ink-3 hover:bg-surface-3 hover:text-ink',
  warning: 'text-ink-3 hover:bg-surface-3 hover:text-warning',
  success: 'text-ink-3 hover:bg-surface-3 hover:text-success',
  danger: 'text-ink-3 hover:bg-danger-subtle hover:text-danger',
  accent: 'text-ink-3 hover:bg-accent-subtle hover:text-accent',
  info: 'text-ink-3 hover:bg-surface-3 hover:text-info',
};

export function actionAvailable(report: AdminReport, spec: ModActionSpec): boolean {
  if (spec.needs === 'entity') return Boolean(report.entity_id && report.entity_type);
  if (spec.needs === 'user') return Boolean(report.subject);
  return true;
}

function ActionButton({
  spec,
  report,
  disabled,
  onAction,
}: {
  spec: ModActionSpec;
  report: AdminReport;
  disabled: boolean;
  onAction: (report: AdminReport, spec: ModActionSpec) => void;
}) {
  const available = actionAvailable(report, spec);
  const title = available
    ? `${spec.label} (${spec.hotkey})`
    : `${spec.label} — this report has no ${spec.needs === 'entity' ? 'content' : 'account'} attached`;

  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      disabled={disabled || !available}
      onClick={() => onAction(report, spec)}
      className={cn(
        'focus-ring grid size-7 place-items-center rounded-xs',
        'transition-colors dur-fast ease-standard',
        'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
        actionToneClass[spec.tone] ?? actionToneClass.neutral,
      )}
    >
      <Icon name={spec.icon} size="sm" />
    </button>
  );
}

/* ── the expanded row: the content, then the account behind it ───────────── */

function ReportDetail({ report }: { report: AdminReport }) {
  const subjectId = report.subject?.id ?? null;
  const { detail, loading, error, reload } = useUserDetail(subjectId);

  const preview = report.preview;
  const cover = mediaUrl(preview?.cover_path ?? null);
  const href =
    report.entity_type && report.entity_id
      ? entityHref(report.entity_type, report.entity_id)
      : null;

  return (
    <div className="grid gap-3 border-t border-line-subtle bg-sunken p-3 lg:grid-cols-2">
      <Panel
        title="Reported content"
        icon="image"
        actions={
          href ? (
            <Link
              href={href}
              className="focus-ring inline-flex items-center gap-1 rounded-xs px-1 py-0.5 text-micro uppercase text-ink-3 hover:text-accent"
            >
              Open
              <Icon name="link" size="xs" />
            </Link>
          ) : null
        }
      >
        <div className="flex min-w-0 gap-3">
          {cover ? (
            <div className="w-28 shrink-0 overflow-hidden rounded-sm border border-line-subtle">
              <BlurhashImage
                src={cover}
                alt={preview?.title ?? 'Reported content'}
                clamp
                sizes="112px"
              />
            </div>
          ) : null}

          <div className="flex min-w-0 flex-1 flex-col gap-1.5">
            {preview?.title ? (
              <p className="text-body-strong text-ink">{preview.title}</p>
            ) : null}
            {preview?.description ? (
              <p className="whitespace-pre-wrap break-words text-caption text-ink-2">
                {truncate(preview.description, 600)}
              </p>
            ) : null}
            {!preview?.title && !preview?.description ? (
              <p className="text-caption text-ink-3">
                {report.message_id
                  ? 'A direct message. Message bodies are not exposed to the console — action the account instead.'
                  : 'No content attached; this report is about the account itself.'}
              </p>
            ) : null}

            {report.details ? (
              <div className="mt-1 rounded-xs border border-line-subtle bg-surface-2 p-2">
                <p className="text-micro uppercase text-ink-3">Reporter wrote</p>
                <p className="mt-0.5 whitespace-pre-wrap break-words text-caption text-ink">
                  {report.details}
                </p>
              </div>
            ) : null}
          </div>
        </div>
      </Panel>

      <Panel
        title="Account history"
        icon="user"
        actions={
          subjectId ? (
            <Link
              href={`${routes.adminUsers}?u=${subjectId}`}
              className="focus-ring inline-flex items-center gap-1 rounded-xs px-1 py-0.5 text-micro uppercase text-ink-3 hover:text-accent"
            >
              Console
              <Icon name="chevron-right" size="xs" />
            </Link>
          ) : null
        }
      >
        {!subjectId ? (
          <p className="text-caption text-ink-3">This report has no account attached.</p>
        ) : loading ? (
          <DossierSkeleton />
        ) : error ? (
          <ErrorState error={error} compact onRetry={reload} />
        ) : detail ? (
          <div className="flex flex-col gap-3">
            <DossierHeader detail={detail} />
            <DossierStats detail={detail} />
            <div>
              <p className="mb-1 text-micro uppercase text-ink-3">Moderation history</p>
              <DossierHistory detail={detail} />
            </div>
            <div>
              <p className="mb-1 text-micro uppercase text-ink-3">Recent items</p>
              <DossierContent detail={detail} limit={4} />
            </div>
          </div>
        ) : null}
      </Panel>

      <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-caption text-ink-3 lg:col-span-2">
        <span>Keys:</span>
        {MOD_ACTIONS.map((spec) => (
          <span key={spec.action} className="inline-flex items-center gap-1">
            <Kbd>{spec.hotkey}</Kbd>
            {spec.label}
          </span>
        ))}
      </p>
    </div>
  );
}
