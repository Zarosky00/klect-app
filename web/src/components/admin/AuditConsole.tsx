'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { cn } from '@/lib/cn';
import { entityHref, type EntityType } from '@/lib/entities';
import { fullDateTime, handle } from '@/lib/format';
import { routes } from '@/lib/routes';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { useSupabase } from '@/providers/session-provider';
import {
  AUDIT_ACTIONS,
  auditActionLabel,
  describeServerError,
  listAuditEntries,
  type AdminErrorInfo,
  type AdminPersonRef,
  type AuditEntry,
} from './data';
import { useAdminToast } from './useAdminToast';
import {
  AdminPage,
  Badge,
  Notice,
  TimeAgo,
  groupDigits,
  tableClass,
  tdClass,
  thClass,
} from './ui';

const PAGE = 50;

const TABLE_TO_ENTITY: Record<string, EntityType> = {
  collections: 'collection',
  subcollections: 'subcollection',
  items: 'item',
  posts: 'post',
  comments: 'comment',
};

export interface AuditConsoleProps {
  initialEntries: AuditEntry[];
  actors: AdminPersonRef[];
  /** Set when the server read was refused — usually "moderator, not admin". */
  initialError?: AdminErrorInfo | null;
}

export function AuditConsole({ initialEntries, actors, initialError = null }: AuditConsoleProps) {
  const supabase = useSupabase();
  const { fail } = useAdminToast();

  const [action, setAction] = useState('');
  const [actorId, setActorId] = useState('');
  const [entries, setEntries] = useState<AuditEntry[]>(initialEntries);
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [exhausted, setExhausted] = useState(initialEntries.length < PAGE);
  const [error, setError] = useState<AdminErrorInfo | null>(initialError);
  const [openId, setOpenId] = useState<number | null>(null);

  const hydrated = useRef(false);

  const load = useCallback(
    async (nextAction: string, nextActor: string) => {
      setLoading(true);
      setError(null);
      try {
        const rows = await listAuditEntries(supabase, {
          ...(nextAction ? { action: nextAction } : {}),
          ...(nextActor ? { actorId: nextActor } : {}),
          limit: PAGE,
          offset: 0,
        });
        setEntries(rows);
        setExhausted(rows.length < PAGE);
        setOpenId(null);
      } catch (thrown) {
        setError(describeServerError(thrown));
        setEntries([]);
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
    void load(action, actorId);
  }, [action, actorId, load]);

  const loadMore = useCallback(async () => {
    setLoadingMore(true);
    try {
      const rows = await listAuditEntries(supabase, {
        ...(action ? { action } : {}),
        ...(actorId ? { actorId } : {}),
        limit: PAGE,
        offset: entries.length,
      });
      const seen = new Set(entries.map((entry) => entry.id));
      setEntries((current) => [...current, ...rows.filter((entry) => !seen.has(entry.id))]);
      setExhausted(rows.length < PAGE);
    } catch (thrown) {
      fail(thrown, () => void loadMore());
    } finally {
      setLoadingMore(false);
    }
  }, [action, actorId, entries, fail, supabase]);

  /** Actions the filter offers: every known call site, plus anything unseen. */
  const actionOptions = useMemo(() => {
    const found = new Set<string>(AUDIT_ACTIONS);
    for (const entry of entries) found.add(entry.action);
    return [...found].sort();
  }, [entries]);

  const refused = error?.refused ?? false;

  return (
    <AdminPage
      title="Audit log"
      description="Every staff action, newest first, with the actor, the target and the detail the RPC recorded."
      actions={
        <Button
          size="sm"
          variant="secondary"
          iconLeft="repost"
          loading={loading}
          onClick={() => void load(action, actorId)}
        >
          Refresh
        </Button>
      }
      toolbar={
        <>
          <label className="flex items-center gap-2 text-caption text-ink-2">
            Action
            <select
              value={action}
              onChange={(event) => setAction(event.target.value)}
              className="focus-ring h-9 rounded-xs border border-line bg-surface-2 px-2 text-caption text-ink"
            >
              <option value="">Everything</option>
              {actionOptions.map((value) => (
                <option key={value} value={value}>
                  {auditActionLabel(value)}
                </option>
              ))}
            </select>
          </label>

          <label className="flex items-center gap-2 text-caption text-ink-2">
            Actor
            <select
              value={actorId}
              onChange={(event) => setActorId(event.target.value)}
              className="focus-ring h-9 rounded-xs border border-line bg-surface-2 px-2 text-caption text-ink"
            >
              <option value="">Anyone</option>
              {actors.map((actor) => (
                <option key={actor.id} value={actor.id}>
                  {actor.display_name} ({handle(actor.username)})
                </option>
              ))}
            </select>
          </label>

          {action || actorId ? (
            <Button
              size="sm"
              variant="ghost"
              iconLeft="close"
              onClick={() => {
                setAction('');
                setActorId('');
              }}
            >
              Clear
            </Button>
          ) : null}
        </>
      }
    >
      {refused ? (
        <Notice tone="danger" icon="lock" title={error?.message ?? 'Forbidden'}>
          The audit log is readable by admins and superadmins only — its RLS policy is{' '}
          <code className="font-mono">is_admin()</code>. Moderators can still triage reports and
          moderate content; every action they take is still written here.
        </Notice>
      ) : null}

      <div className="overflow-hidden rounded-md border border-line-subtle bg-surface-1">
        {loading ? (
          <div className="flex flex-col gap-3 p-3">
            {Array.from({ length: 6 }, (_, index) => (
              <SkeletonRow key={index} />
            ))}
          </div>
        ) : error && !refused ? (
          <ErrorState
            title="The log would not load"
            description={error.message}
            compact
            onRetry={() => void load(action, actorId)}
          />
        ) : entries.length === 0 ? (
          <EmptyState
            icon="shield"
            compact
            title={refused ? 'Nothing to show' : 'No staff actions yet'}
            description={
              refused
                ? 'Ask an admin for access, or work from the report queue.'
                : 'The log fills the moment a report is resolved, content is hidden, or a role changes.'
            }
          />
        ) : (
          <>
            <div className="min-w-0 overflow-x-auto">
              <table className={tableClass}>
                <caption className="sr-only">Audit log</caption>
                <thead>
                  <tr>
                    <th className={cn(thClass, 'text-left')}>When</th>
                    <th className={cn(thClass, 'text-left')}>Actor</th>
                    <th className={cn(thClass, 'text-left')}>Action</th>
                    <th className={cn(thClass, 'text-left')}>Target</th>
                    <th className={cn(thClass, 'text-left')}>Detail</th>
                  </tr>
                </thead>
                <tbody>
                  {entries.map((entry) => (
                    <AuditRow
                      key={entry.id}
                      entry={entry}
                      open={openId === entry.id}
                      onToggle={() => setOpenId((id) => (id === entry.id ? null : entry.id))}
                    />
                  ))}
                </tbody>
              </table>
            </div>

            <div className="flex items-center justify-between gap-3 border-t border-line-subtle px-3 py-2">
              <span className="text-caption text-ink-3">
                {groupDigits(entries.length)} entries
              </span>
              {exhausted ? (
                <Badge tone="neutral">
                  <Icon name="check" size="xs" />
                  end of log
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
    </AdminPage>
  );
}

function AuditRow({
  entry,
  open,
  onToggle,
}: {
  entry: AuditEntry;
  open: boolean;
  onToggle: () => void;
}) {
  const pairs = detailPairs(entry.detail);
  const target = targetLink(entry);

  return (
    <>
      <tr className="transition-colors dur-fast ease-standard hover:bg-surface-2">
        <td className={cn(tdClass, 'text-ink-3')} title={fullDateTime(entry.created_at)}>
          <TimeAgo value={entry.created_at} />
        </td>

        <td className={tdClass}>
          {entry.actor ? (
            <span className="flex min-w-0 items-center gap-2">
              <Avatar
                path={entry.actor.avatar_path}
                name={entry.actor.display_name}
                username={entry.actor.username}
                size="xs"
              />
              <Link
                href={`${routes.adminUsers}?u=${entry.actor.id}`}
                className="focus-ring truncate rounded-xs text-caption text-ink hover:text-accent"
              >
                {handle(entry.actor.username)}
              </Link>
            </span>
          ) : (
            <span className="text-ink-3">system</span>
          )}
        </td>

        <td className={tdClass}>
          <Badge tone="info">{auditActionLabel(entry.action)}</Badge>
        </td>

        <td className={cn(tdClass, 'text-caption text-ink-2')}>
          {target ? (
            <Link href={target.href} className="focus-ring rounded-xs hover:text-accent">
              {target.label}
            </Link>
          ) : (
            <span className="font-mono text-micro text-ink-3">
              {entry.target_table ?? '—'}
              {entry.target_id ? ` · ${entry.target_id.slice(0, 8)}` : ''}
            </span>
          )}
        </td>

        <td className={tdClass}>
          <span className="flex items-center gap-1.5">
            {pairs.slice(0, 2).map((pair) => (
              <Badge key={pair.key} tone="neutral">
                {pair.key}: {pair.value}
              </Badge>
            ))}
            <button
              type="button"
              onClick={onToggle}
              aria-expanded={open}
              className="focus-ring rounded-xs px-1 py-0.5 text-micro uppercase text-ink-3 transition-colors dur-fast ease-standard hover:text-ink"
            >
              {open ? 'Hide' : 'JSON'}
            </button>
          </span>
        </td>
      </tr>

      {open ? (
        <tr>
          <td colSpan={5} className="border-b border-line-subtle bg-sunken px-3 py-2">
            <pre className="max-h-64 overflow-auto whitespace-pre-wrap break-words font-mono text-micro text-ink-2">
              {JSON.stringify(entry.detail ?? {}, null, 2)}
            </pre>
          </td>
        </tr>
      ) : null}
    </>
  );
}

function detailPairs(detail: unknown): Array<{ key: string; value: string }> {
  if (!detail || typeof detail !== 'object' || Array.isArray(detail)) return [];
  return Object.entries(detail as Record<string, unknown>)
    .filter(([, value]) => value !== null && value !== undefined && value !== '')
    .map(([key, value]) => ({
      key,
      value: typeof value === 'string' ? value : JSON.stringify(value),
    }));
}

function targetLink(entry: AuditEntry): { href: string; label: string } | null {
  if (!entry.target_id || !entry.target_table) return null;

  if (entry.target_table === 'profiles' || entry.target_table === 'user_roles') {
    return { href: `${routes.adminUsers}?u=${entry.target_id}`, label: 'account' };
  }
  if (entry.target_table === 'reports') {
    return { href: routes.adminReports, label: 'report' };
  }

  const type = TABLE_TO_ENTITY[entry.target_table];
  if (!type) return null;
  return { href: entityHref(type, entry.target_id), label: type };
}
