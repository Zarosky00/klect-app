'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { adminModerateEntity } from '@/lib/api';
import { cn } from '@/lib/cn';
import { duration } from '@/design/tokens.g';
import {
  ENTITY_LABEL,
  SURFACE_ENTITY_TYPES,
  VISIBILITY_LABELS,
  entityHref,
  type SurfaceEntityType,
} from '@/lib/entities';
import { handle, plural } from '@/lib/format';
import { profileHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import { Button } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { TextField } from '@/components/ui/TextField';
import { useSupabase } from '@/providers/session-provider';
import {
  CONTENT_FILTERS,
  CONTENT_FILTER_LABELS,
  describeServerError,
  listAdminContent,
  type AdminContentRow,
  type AdminErrorInfo,
  type ContentVisibilityFilter,
} from './data';
import { ResolveDialog, type ResolveIntent, type ResolvePayload } from './ResolveDialog';
import { useAdminToast } from './useAdminToast';
import {
  AdminPage,
  Badge,
  TimeAgo,
  groupDigits,
  tableClass,
  tdClass,
  thClass,
} from './ui';

const PAGE = 30;

export interface ContentConsoleProps {
  initialType: SurfaceEntityType;
  initialFilter: ContentVisibilityFilter;
  initialRows: AdminContentRow[];
  initialError?: AdminErrorInfo | null;
}

interface HideIntent {
  row: AdminContentRow;
  hidden: boolean;
}

export function ContentConsole({
  initialType,
  initialFilter,
  initialRows,
  initialError = null,
}: ContentConsoleProps) {
  const supabase = useSupabase();
  const { toast, fail } = useAdminToast();

  const [type, setType] = useState<SurfaceEntityType>(initialType);
  const [filter, setFilter] = useState<ContentVisibilityFilter>(initialFilter);
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState<AdminContentRow[]>(initialRows);
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [exhausted, setExhausted] = useState(initialRows.length < PAGE);
  const [error, setError] = useState<AdminErrorInfo | null>(initialError);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [intent, setIntent] = useState<HideIntent | null>(null);

  const hydrated = useRef(false);

  const load = useCallback(
    async (nextType: SurfaceEntityType, nextFilter: ContentVisibilityFilter, q: string) => {
      setLoading(true);
      setError(null);
      try {
        const next = await listAdminContent(supabase, {
          type: nextType,
          filter: nextFilter,
          q,
          limit: PAGE,
          offset: 0,
        });
        setRows(next);
        setExhausted(next.length < PAGE);
      } catch (thrown) {
        setError(describeServerError(thrown));
        setRows([]);
      } finally {
        setLoading(false);
      }
    },
    [supabase],
  );

  // One debounce constant for the whole console, taken from the token module.
  useEffect(() => {
    if (!hydrated.current) {
      hydrated.current = true;
      return;
    }
    const timer = setTimeout(() => void load(type, filter, query), duration.medium);
    return () => clearTimeout(timer);
  }, [filter, load, query, type]);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const url = new URL(window.location.href);
    url.searchParams.set('type', type);
    url.searchParams.set('filter', filter);
    window.history.replaceState(null, '', url.toString());
  }, [filter, type]);

  const loadMore = useCallback(async () => {
    setLoadingMore(true);
    try {
      const next = await listAdminContent(supabase, {
        type,
        filter,
        q: query,
        limit: PAGE,
        offset: rows.length,
      });
      const seen = new Set(rows.map((row) => row.id));
      setRows((current) => [...current, ...next.filter((row) => !seen.has(row.id))]);
      setExhausted(next.length < PAGE);
    } catch (thrown) {
      fail(thrown, () => void loadMore());
    } finally {
      setLoadingMore(false);
    }
  }, [fail, filter, query, rows, supabase, type]);

  const moderate = useCallback(
    async (row: AdminContentRow, hidden: boolean, payload: ResolvePayload) => {
      const snapshot = rows;
      const stamp = new Date().toISOString();

      // Optimistic: flip the row, and drop it if it no longer matches the filter.
      setRows((current) =>
        current
          .map((candidate) =>
            candidate.id === row.id ? { ...candidate, hidden_at: hidden ? stamp : null } : candidate,
          )
          .filter((candidate) => {
            if (filter === 'hidden') return candidate.hidden_at !== null;
            if (filter === 'visible') return candidate.hidden_at === null;
            return true;
          }),
      );
      setBusyId(row.id);

      try {
        await adminModerateEntity(supabase, {
          type: row.type,
          id: row.id,
          hidden,
          ...(payload.reason === undefined ? {} : { reason: payload.reason }),
        });
        toast.success(
          hidden ? `${ENTITY_LABEL[row.type]} hidden` : `${ENTITY_LABEL[row.type]} restored`,
          hidden
            ? `“${row.title}” is now invisible to everyone but its owner and staff.`
            : `“${row.title}” is back in every feed.`,
        );
      } catch (thrown) {
        setRows(snapshot);
        fail(thrown, () => void moderate(row, hidden, payload));
      } finally {
        setBusyId(null);
      }
    },
    [fail, filter, rows, supabase, toast],
  );

  const hiddenCount = rows.filter((row) => row.hidden_at !== null).length;

  return (
    <AdminPage
      title="Content"
      description="Hide and restore collections, subcollections and items. Hiding is reversible; nothing here deletes."
      actions={
        <Button
          size="sm"
          variant="secondary"
          iconLeft="repost"
          loading={loading}
          onClick={() => void load(type, filter, query)}
        >
          Refresh
        </Button>
      }
      toolbar={
        <>
          <div role="tablist" aria-label="Entity type" className="flex flex-wrap gap-1">
            {SURFACE_ENTITY_TYPES.map((value) => {
              const selected = value === type;
              return (
                <button
                  key={value}
                  role="tab"
                  type="button"
                  aria-selected={selected}
                  onClick={() => setType(value)}
                  className={cn(
                    'focus-ring rounded-xs px-2 py-1 text-label transition-colors dur-fast ease-standard',
                    selected
                      ? 'bg-surface-3 text-ink'
                      : 'text-ink-2 hover:bg-surface-2 hover:text-ink',
                  )}
                >
                  {plural(2, ENTITY_LABEL[value])}
                </button>
              );
            })}
          </div>

          <span aria-hidden className="h-5 w-px bg-line" />

          <div role="group" aria-label="Visibility" className="flex flex-wrap gap-1">
            {CONTENT_FILTERS.map((value) => {
              const selected = value === filter;
              return (
                <button
                  key={value}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => setFilter(value)}
                  className={cn(
                    'focus-ring rounded-xs px-2 py-1 text-label transition-colors dur-fast ease-standard',
                    selected
                      ? 'bg-surface-3 text-ink'
                      : 'text-ink-2 hover:bg-surface-2 hover:text-ink',
                  )}
                >
                  {CONTENT_FILTER_LABELS[value]}
                </button>
              );
            })}
          </div>

          <div className="min-w-0 flex-1 sm:max-w-80">
            <TextField
              label="Search content"
              labelHidden
              iconLeft="search"
              placeholder={`Search ${plural(2, ENTITY_LABEL[type]).toLowerCase()}…`}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
          </div>

          {hiddenCount > 0 ? (
            <Badge tone="warning" icon="eye">
              {groupDigits(hiddenCount)} hidden on this page
            </Badge>
          ) : null}
        </>
      }
    >
      <div className="overflow-hidden rounded-md border border-line-subtle bg-surface-1">
        {loading ? (
          <div className="flex flex-col gap-3 p-3">
            {Array.from({ length: 6 }, (_, index) => (
              <SkeletonRow key={index} />
            ))}
          </div>
        ) : error ? (
          <ErrorState
            title={error.refused ? 'Refused by the server' : 'That did not load'}
            description={error.message}
            compact
            onRetry={() => void load(type, filter, query)}
          />
        ) : rows.length === 0 ? (
          <EmptyState
            icon="grid"
            compact
            title="Nothing here"
            description={
              filter === 'hidden'
                ? 'No content is currently hidden by moderation.'
                : 'No rows match this filter.'
            }
          />
        ) : (
          <>
            <div className="min-w-0 overflow-x-auto">
              <table className={tableClass}>
                <caption className="sr-only">
                  {plural(2, ENTITY_LABEL[type])}, {CONTENT_FILTER_LABELS[filter].toLowerCase()}
                </caption>
                <thead>
                  <tr>
                    <th className={cn(thClass, 'text-left')}>Content</th>
                    <th className={cn(thClass, 'text-left')}>Owner</th>
                    <th className={cn(thClass, 'text-left')}>Visibility</th>
                    <th className={cn(thClass, 'text-right')}>
                      {type === 'item' ? 'Photos' : 'Items'}
                    </th>
                    <th className={cn(thClass, 'text-right')}>Likes</th>
                    <th className={cn(thClass, 'text-right')}>Views</th>
                    <th className={cn(thClass, 'text-right')}>Age</th>
                    <th className={cn(thClass, 'text-right')}>
                      <span className="sr-only">Actions</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => {
                    const hidden = row.hidden_at !== null;
                    const cover = mediaUrl(row.cover_path);
                    return (
                      <tr
                        key={`${row.type}-${row.id}`}
                        className={cn(
                          'group transition-colors dur-fast ease-standard hover:bg-surface-2',
                          busyId === row.id && 'opacity-[var(--k-opacity-veil)]',
                        )}
                      >
                        <td className={tdClass}>
                          <span className="flex min-w-0 items-center gap-2">
                            <span className="size-8 shrink-0 overflow-hidden rounded-xs bg-skeleton">
                              {cover ? (
                                /* eslint-disable-next-line @next/next/no-img-element -- covers
                                   come from arbitrary hosts; see BlurhashImage's note. */
                                <img
                                  src={cover}
                                  alt=""
                                  loading="lazy"
                                  decoding="async"
                                  className="size-full object-cover"
                                />
                              ) : null}
                            </span>
                            <Link
                              href={entityHref(row.type, row.id)}
                              className="focus-ring min-w-0 max-w-80 truncate rounded-xs text-label text-ink underline-offset-4 hover:text-accent hover:underline"
                            >
                              {row.title}
                            </Link>
                            {hidden ? (
                              <Badge tone="warning" icon="eye">
                                hidden
                              </Badge>
                            ) : null}
                            {row.deleted_at ? (
                              <Badge tone="danger" icon="trash">
                                deleted
                              </Badge>
                            ) : null}
                          </span>
                        </td>

                        <td className={tdClass}>
                          {row.owner ? (
                            <Link
                              href={profileHref(row.owner.username)}
                              className="focus-ring rounded-xs text-caption text-ink-2 hover:text-accent"
                            >
                              {handle(row.owner.username)}
                            </Link>
                          ) : (
                            <span className="text-ink-3">—</span>
                          )}
                        </td>

                        <td className={cn(tdClass, 'text-caption text-ink-2')}>
                          {row.visibility ? VISIBILITY_LABELS[row.visibility] : 'Inherited'}
                        </td>
                        <td className={cn(tdClass, 'text-right tabular text-ink-2')}>
                          {groupDigits(row.child_count)}
                        </td>
                        <td className={cn(tdClass, 'text-right tabular text-ink-2')}>
                          {groupDigits(row.like_count)}
                        </td>
                        <td className={cn(tdClass, 'text-right tabular text-ink-2')}>
                          {groupDigits(row.view_count)}
                        </td>
                        <td className={cn(tdClass, 'text-right text-ink-3')}>
                          <TimeAgo value={hidden ? row.hidden_at : row.created_at} />
                        </td>

                        <td className={cn(tdClass, 'text-right')}>
                          {hidden ? (
                            <button
                              type="button"
                              disabled={busyId !== null}
                              onClick={() => void moderate(row, false, {})}
                              className="focus-ring inline-flex items-center gap-1 rounded-xs border border-line bg-surface-2 px-2 py-1 text-caption text-ink-2 transition-colors dur-fast ease-standard hover:text-success disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]"
                            >
                              <Icon name="repost" size="xs" />
                              Restore
                            </button>
                          ) : (
                            <button
                              type="button"
                              disabled={busyId !== null}
                              onClick={() => setIntent({ row, hidden: true })}
                              className="focus-ring inline-flex items-center gap-1 rounded-xs border border-line bg-surface-2 px-2 py-1 text-caption text-ink-2 transition-colors dur-fast ease-standard hover:text-warning disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]"
                            >
                              <Icon name="eye" size="xs" />
                              Hide
                            </button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div className="flex items-center justify-between gap-3 border-t border-line-subtle px-3 py-2">
              <span className="text-caption text-ink-3">
                {groupDigits(rows.length)} {plural(rows.length, 'row')} shown
              </span>
              {exhausted ? (
                <Badge tone="neutral">
                  <Icon name="check" size="xs" />
                  end of list
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
        open={intent !== null}
        spec={intent ? hideIntentSpec(intent) : null}
        subject={intent ? `“${intent.row.title}”` : ''}
        note="Recorded as a moderation action and written to the audit log."
        onCancel={() => setIntent(null)}
        onConfirm={async (payload) => {
          const current = intent;
          setIntent(null);
          if (current) await moderate(current.row, current.hidden, payload);
        }}
      />
    </AdminPage>
  );
}

function hideIntentSpec(intent: HideIntent): ResolveIntent {
  return {
    label: intent.hidden ? 'Hide' : 'Restore',
    icon: intent.hidden ? 'eye' : 'repost',
    tone: intent.hidden ? 'warning' : 'success',
    duration: false,
    blurb: intent.hidden
      ? `Sets hidden_at on this ${ENTITY_LABEL[intent.row.type].toLowerCase()}. It leaves every feed, search result and profile except its owner's and staff's, and nothing is deleted.`
      : 'Clears hidden_at and puts the content back everywhere it used to appear.',
  };
}
