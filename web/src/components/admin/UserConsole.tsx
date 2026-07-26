'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import {
  adminSetRole,
  adminSetUserState,
  adminSetVerified,
} from '@/lib/api';
import { cn } from '@/lib/cn';
import { duration } from '@/design/tokens.g';
import type { AppRole } from '@/lib/entities';
import { handle } from '@/lib/format';
import { profileHref } from '@/lib/routes';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { TextField } from '@/components/ui/TextField';
import { useSupabase } from '@/providers/session-provider';
import {
  USER_FILTERS,
  USER_FILTER_LABELS,
  listAdminUsers,
  listRolesFor,
  type AdminUserRow,
  type UserFilter,
} from './data';
import { ResolveDialog, type ResolveIntent, type ResolvePayload } from './ResolveDialog';
import {
  DossierContent,
  DossierHeader,
  DossierHistory,
  DossierSkeleton,
  DossierStats,
  roleTone,
  useUserDetail,
} from './UserDossier';
import { useAdminToast } from './useAdminToast';
import {
  AdminPage,
  Badge,
  KeyboardLegend,
  Panel,
  TimeAgo,
  groupDigits,
  tableClass,
  tdClass,
  thClass,
} from './ui';

/** Roles a superadmin can hand out. `user` is implicit and never granted here. */
const GRANTABLE_ROLES: readonly AppRole[] = ['moderator', 'admin', 'superadmin'];

type UserIntent =
  | { kind: 'suspend'; user: AdminUserRow }
  | { kind: 'unsuspend'; user: AdminUserRow }
  | { kind: 'role'; user: AdminUserRow; role: AppRole; grant: boolean };

export interface UserConsoleProps {
  initialUsers: AdminUserRow[];
  initialRoles: Record<string, AppRole[]>;
  initialSelectedId: string | null;
  /** The viewer's own roles — advisory only; every RPC re-checks server-side. */
  viewerRoles: AppRole[];
}

export function UserConsole({
  initialUsers,
  initialRoles,
  initialSelectedId,
  viewerRoles,
}: UserConsoleProps) {
  const supabase = useSupabase();
  const { toast, fail } = useAdminToast();

  const isAdmin = viewerRoles.includes('admin') || viewerRoles.includes('superadmin');
  const isSuperadmin = viewerRoles.includes('superadmin');

  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<UserFilter>('all');
  const [users, setUsers] = useState<AdminUserRow[]>(initialUsers);
  const [roles, setRoles] = useState<Record<string, AppRole[]>>(initialRoles);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const [selectedId, setSelectedId] = useState<string | null>(
    initialSelectedId ?? initialUsers[0]?.id ?? null,
  );
  const [intent, setIntent] = useState<UserIntent | null>(null);
  const [busy, setBusy] = useState(false);

  const searchRef = useRef<HTMLInputElement | null>(null);
  const hydrated = useRef(false);

  const detail = useUserDetail(selectedId);

  /* ── list ─────────────────────────────────────────────────────────────── */

  const load = useCallback(
    async (q: string, next: UserFilter) => {
      setLoading(true);
      setError(null);
      try {
        const rows = await listAdminUsers(supabase, { q, filter: next });
        setUsers(rows);
        setRoles(
          await listRolesFor(
            supabase,
            rows.map((row) => row.id),
          ),
        );
        if (rows.length > 0 && !rows.some((row) => row.id === selectedId)) {
          setSelectedId(rows[0]?.id ?? null);
        }
      } catch (thrown) {
        setError(thrown);
        setUsers([]);
      } finally {
        setLoading(false);
      }
    },
    [selectedId, supabase],
  );

  // Debounced by the medium motion token so the console has exactly one number
  // for "a beat" and it lives in the token file, not here.
  useEffect(() => {
    if (!hydrated.current) {
      hydrated.current = true;
      return;
    }
    const timer = setTimeout(() => void load(query, filter), duration.medium);
    return () => clearTimeout(timer);
  }, [filter, load, query]);

  /* ── keyboard ─────────────────────────────────────────────────────────── */

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (intent) return;
      if (event.metaKey || event.ctrlKey || event.altKey) return;

      const target = event.target as HTMLElement | null;
      const typing =
        target &&
        (target.isContentEditable || /^(input|textarea|select)$/i.test(target.tagName));

      if (event.key === '/' && !typing) {
        event.preventDefault();
        searchRef.current?.focus();
        return;
      }
      if (typing) return;
      if (users.length === 0) return;

      const delta =
        event.key === 'j' || event.key === 'ArrowDown'
          ? 1
          : event.key === 'k' || event.key === 'ArrowUp'
            ? -1
            : 0;
      if (delta === 0) return;

      event.preventDefault();
      setSelectedId((current) => {
        const index = users.findIndex((user) => user.id === current);
        const from = index < 0 ? 0 : index;
        const next = Math.min(Math.max(from + delta, 0), users.length - 1);
        return users[next]?.id ?? current;
      });
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [intent, users]);

  /* ── deep link + keep the selected row on screen ──────────────────────── */

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const url = new URL(window.location.href);
    if (selectedId) url.searchParams.set('u', selectedId);
    else url.searchParams.delete('u');
    window.history.replaceState(null, '', url.toString());

    if (selectedId) {
      document
        .querySelector(`[data-user-row="${selectedId}"]`)
        ?.scrollIntoView({ block: 'nearest' });
    }
  }, [selectedId]);

  /* ── mutations ────────────────────────────────────────────────────────── */

  const patchUser = useCallback((id: string, patch: Partial<AdminUserRow>) => {
    setUsers((current) => current.map((row) => (row.id === id ? { ...row, ...patch } : row)));
  }, []);

  const runIntent = useCallback(
    async (current: UserIntent, payload: ResolvePayload) => {
      setBusy(true);
      try {
        if (current.kind === 'suspend') {
          await adminSetUserState(supabase, {
            userId: current.user.id,
            suspended: true,
            ...(payload.suspendDays === undefined ? {} : { days: payload.suspendDays }),
            ...(payload.reason === undefined ? {} : { reason: payload.reason }),
          });
          patchUser(current.user.id, { is_suspended: true });
          toast.success(
            'Account suspended',
            payload.suspendDays
              ? `${handle(current.user.username)} · ${payload.suspendDays} days.`
              : `${handle(current.user.username)} · no end date.`,
          );
        } else if (current.kind === 'unsuspend') {
          await adminSetUserState(supabase, { userId: current.user.id, suspended: false });
          patchUser(current.user.id, { is_suspended: false, suspended_until: null });
          toast.success('Suspension lifted', handle(current.user.username));
        } else {
          await adminSetRole(supabase, {
            userId: current.user.id,
            role: current.role,
            grant: current.grant,
          });
          setRoles((map) => {
            const held = map[current.user.id] ?? [];
            return {
              ...map,
              [current.user.id]: current.grant
                ? [...new Set([...held, current.role])]
                : held.filter((role) => role !== current.role),
            };
          });
          toast.success(
            current.grant ? `Granted ${current.role}` : `Revoked ${current.role}`,
            handle(current.user.username),
          );
        }
        detail.reload();
      } catch (thrown) {
        fail(thrown, () => void runIntent(current, payload));
      } finally {
        setBusy(false);
      }
    },
    [detail, fail, patchUser, supabase, toast],
  );

  const toggleVerified = useCallback(
    async (user: AdminUserRow) => {
      const next = !user.is_verified;
      patchUser(user.id, { is_verified: next });
      setBusy(true);
      try {
        await adminSetVerified(supabase, user.id, next);
        toast.success(next ? 'Verified' : 'Verification removed', handle(user.username));
        detail.reload();
      } catch (thrown) {
        patchUser(user.id, { is_verified: user.is_verified });
        fail(thrown, () => void toggleVerified(user));
      } finally {
        setBusy(false);
      }
    },
    [detail, fail, patchUser, supabase, toast],
  );

  const selected = users.find((row) => row.id === selectedId) ?? null;

  return (
    <AdminPage
      title="Users"
      description="Search, inspect, and action accounts. Every mutation lands in the audit log."
      toolbar={
        <>
          <div className="min-w-0 flex-1 sm:max-w-100">
            <TextField
              ref={searchRef}
              label="Search users"
              labelHidden
              iconLeft="search"
              placeholder="Username or display name…   /"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
          </div>

          <div role="group" aria-label="Filter" className="flex flex-wrap gap-1">
            {USER_FILTERS.map((value) => {
              const selectedFilter = value === filter;
              return (
                <button
                  key={value}
                  type="button"
                  aria-pressed={selectedFilter}
                  onClick={() => setFilter(value)}
                  className={cn(
                    'focus-ring rounded-xs px-2 py-1 text-label transition-colors dur-fast ease-standard',
                    selectedFilter
                      ? 'bg-surface-3 text-ink'
                      : 'text-ink-2 hover:bg-surface-2 hover:text-ink',
                  )}
                >
                  {USER_FILTER_LABELS[value]}
                </button>
              );
            })}
          </div>

          <KeyboardLegend
            className="ml-auto"
            hints={[
              { keys: ['/'], label: 'search' },
              { keys: ['j', 'k'], label: 'move' },
            ]}
          />
        </>
      }
    >
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
        <div className="min-w-0 flex-1 overflow-hidden rounded-md border border-line-subtle bg-surface-1">
          {loading ? (
            <div className="flex flex-col gap-3 p-3">
              {Array.from({ length: 6 }, (_, index) => (
                <SkeletonRow key={index} />
              ))}
            </div>
          ) : error ? (
            <ErrorState error={error} compact onRetry={() => void load(query, filter)} />
          ) : users.length === 0 ? (
            <EmptyState
              icon="users"
              compact
              title="No accounts match"
              description="Try a different spelling, or clear the filter."
            />
          ) : (
            <div className="min-w-0 overflow-x-auto">
              <table className={tableClass}>
                <caption className="sr-only">Accounts</caption>
                <thead>
                  <tr>
                    <th className={cn(thClass, 'text-left')}>Account</th>
                    <th className={cn(thClass, 'text-left')}>State</th>
                    <th className={cn(thClass, 'text-right')}>Followers</th>
                    <th className={cn(thClass, 'text-right')}>Items</th>
                    <th className={cn(thClass, 'text-right')}>Joined</th>
                    <th className={cn(thClass, 'text-right')}>Seen</th>
                  </tr>
                </thead>
                <tbody>
                  {users.map((user) => {
                    const held = roles[user.id] ?? [];
                    const isSelected = user.id === selectedId;
                    return (
                      <tr
                        key={user.id}
                        data-user-row={user.id}
                        aria-selected={isSelected}
                        className={cn(
                          'cursor-pointer transition-colors dur-fast ease-standard',
                          isSelected ? 'bg-surface-2' : 'hover:bg-surface-2',
                        )}
                        onClick={() => setSelectedId(user.id)}
                      >
                        <td className={tdClass}>
                          <span className="flex min-w-0 items-center gap-2">
                            <Avatar
                              path={user.avatar_path}
                              name={user.display_name}
                              username={user.username}
                              size="sm"
                              verified={user.is_verified}
                            />
                            <span className="flex min-w-0 flex-col">
                              <span className="truncate text-label text-ink">
                                {user.display_name}
                              </span>
                              <span className="truncate text-caption text-ink-3">
                                {handle(user.username)}
                              </span>
                            </span>
                          </span>
                        </td>
                        <td className={tdClass}>
                          <span className="flex flex-wrap items-center gap-1">
                            {user.is_suspended ? (
                              <Badge tone="danger" icon="lock">
                                suspended
                              </Badge>
                            ) : null}
                            {held.map((role) => (
                              <Badge key={role} tone={roleTone(role)}>
                                {role}
                              </Badge>
                            ))}
                            {user.account_visibility !== 'public' ? (
                              <Badge tone="neutral">{user.account_visibility}</Badge>
                            ) : null}
                            {!user.is_suspended && held.length === 0 && user.account_visibility === 'public' ? (
                              <span className="text-ink-3">—</span>
                            ) : null}
                          </span>
                        </td>
                        <td className={cn(tdClass, 'text-right tabular text-ink-2')}>
                          {groupDigits(user.follower_count)}
                        </td>
                        <td className={cn(tdClass, 'text-right tabular text-ink-2')}>
                          {groupDigits(user.item_count)}
                        </td>
                        <td className={cn(tdClass, 'text-right text-ink-3')}>
                          <TimeAgo value={user.created_at} />
                        </td>
                        <td className={cn(tdClass, 'text-right text-ink-3')}>
                          <TimeAgo value={user.last_seen_at} />
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <aside className="w-full shrink-0 lg:sticky lg:top-20 lg:w-100">
          <Panel
            title="Account"
            icon="user"
            actions={
              selected ? (
                <Link
                  href={profileHref(selected.username)}
                  className="focus-ring inline-flex items-center gap-1 rounded-xs px-1 py-0.5 text-micro uppercase text-ink-3 hover:text-accent"
                >
                  Profile
                  <Icon name="link" size="xs" />
                </Link>
              ) : null
            }
          >
            {!selectedId ? (
              <p className="py-6 text-center text-caption text-ink-3">
                Pick an account to inspect.
              </p>
            ) : detail.loading ? (
              <DossierSkeleton />
            ) : detail.error ? (
              <ErrorState error={detail.error} compact onRetry={detail.reload} />
            ) : detail.detail ? (
              <div className="flex flex-col gap-4">
                <DossierHeader detail={detail.detail} size="lg" />

                {selected ? (
                  <div className="flex flex-wrap gap-1.5">
                    {selected.is_suspended ? (
                      <Button
                        size="sm"
                        variant="secondary"
                        iconLeft="check"
                        disabled={busy || !isAdmin}
                        title={isAdmin ? undefined : 'Admins only — the RPC enforces it too.'}
                        onClick={() => setIntent({ kind: 'unsuspend', user: selected })}
                      >
                        Lift suspension
                      </Button>
                    ) : (
                      <Button
                        size="sm"
                        variant="danger"
                        iconLeft="lock"
                        disabled={busy || !isAdmin}
                        title={isAdmin ? undefined : 'Admins only — the RPC enforces it too.'}
                        onClick={() => setIntent({ kind: 'suspend', user: selected })}
                      >
                        Suspend
                      </Button>
                    )}

                    <Button
                      size="sm"
                      variant="secondary"
                      iconLeft="verified"
                      disabled={busy || !isAdmin}
                      title={isAdmin ? undefined : 'Admins only — the RPC enforces it too.'}
                      onClick={() => void toggleVerified(selected)}
                    >
                      {selected.is_verified ? 'Unverify' : 'Verify'}
                    </Button>
                  </div>
                ) : null}

                {/* Role grants are superadmin-only, so the control is not rendered
                    for anyone else — and `admin_set_role` refuses regardless. */}
                {isSuperadmin && selected ? (
                  <fieldset className="flex flex-col gap-1.5">
                    <legend className="text-micro uppercase text-ink-3">Roles</legend>
                    <div className="flex flex-wrap gap-1.5">
                      {GRANTABLE_ROLES.map((role) => {
                        const held = (roles[selected.id] ?? detail.detail?.roles ?? []).includes(role);
                        return (
                          <button
                            key={role}
                            type="button"
                            disabled={busy}
                            aria-pressed={held}
                            onClick={() =>
                              setIntent({ kind: 'role', user: selected, role, grant: !held })
                            }
                            className={cn(
                              'focus-ring inline-flex items-center gap-1 rounded-xs border px-2 py-1 text-caption',
                              'transition-colors dur-fast ease-standard',
                              'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
                              held
                                ? 'border-accent bg-accent-subtle text-accent'
                                : 'border-line bg-surface-2 text-ink-2 hover:text-ink',
                            )}
                          >
                            <Icon name={held ? 'check' : 'plus'} size="xs" />
                            {role}
                          </button>
                        );
                      })}
                    </div>
                  </fieldset>
                ) : null}

                <DossierStats detail={detail.detail} />

                <div>
                  <p className="mb-1 text-micro uppercase text-ink-3">Moderation history</p>
                  <DossierHistory detail={detail.detail} limit={8} />
                </div>

                <div>
                  <p className="mb-1 text-micro uppercase text-ink-3">Recent items</p>
                  <DossierContent detail={detail.detail} limit={8} />
                </div>
              </div>
            ) : null}
          </Panel>
        </aside>
      </div>

      <ResolveDialog
        open={intent !== null}
        spec={intent ? intentSpec(intent) : null}
        subject={intent ? handle(intent.user.username) : ''}
        note="Recorded in the audit log with you as the actor."
        onCancel={() => setIntent(null)}
        onConfirm={async (payload) => {
          const current = intent;
          setIntent(null);
          if (current) await runIntent(current, payload);
        }}
      />
    </AdminPage>
  );
}

function intentSpec(intent: UserIntent): ResolveIntent {
  if (intent.kind === 'suspend') {
    return {
      label: 'Suspend',
      icon: 'lock',
      tone: 'danger',
      duration: true,
      blurb:
        'Blocks the account from every write RPC and routes it to the suspension screen until the term expires.',
    };
  }
  if (intent.kind === 'unsuspend') {
    return {
      label: 'Lift suspension',
      icon: 'check',
      tone: 'success',
      duration: false,
      blurb: 'Restores full access immediately and clears the stored suspension reason.',
    };
  }
  return {
    label: intent.grant ? `Grant ${intent.role}` : `Revoke ${intent.role}`,
    icon: 'shield',
    tone: intent.grant ? 'accent' : 'warning',
    duration: false,
    blurb: intent.grant
      ? `Gives this account the ${intent.role} role. ${intent.role === 'superadmin' ? 'A superadmin can grant and revoke every other role, including yours.' : 'It gains the console immediately.'}`
      : `Removes the ${intent.role} role. Any console session it holds stops working on the next request.`,
  };
}
