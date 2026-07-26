'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { adminUserDetail } from '@/lib/api';
import { cn } from '@/lib/cn';
import { calendarDate, handle, longTimeAgo } from '@/lib/format';
import { itemHref, profileHref } from '@/lib/routes';
import type { AdminUserDetail } from '@/lib/types';
import { Avatar } from '@/components/ui/Avatar';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow, SkeletonText } from '@/components/ui/Skeleton';
import { useSupabase } from '@/providers/session-provider';
import { MOD_ACTION_LABELS } from './actions';
import { Badge, Field, Notice, TimeAgo, groupDigits } from './ui';

export interface UserDetailState {
  detail: AdminUserDetail | null;
  loading: boolean;
  error: unknown;
  reload: () => void;
}

/** `admin_user_detail(p_user)` — profile, roles, report counts, history, content. */
export function useUserDetail(userId: string | null): UserDetailState {
  const supabase = useSupabase();
  const [detail, setDetail] = useState<AdminUserDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    if (!userId) {
      setDetail(null);
      setError(null);
      setLoading(false);
      return;
    }

    let active = true;
    setLoading(true);
    setError(null);

    adminUserDetail(supabase, userId)
      .then((next) => {
        if (active) setDetail(next);
      })
      .catch((thrown: unknown) => {
        if (active) setError(thrown);
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [nonce, supabase, userId]);

  const reload = useCallback(() => setNonce((value) => value + 1), []);

  return { detail, loading, error, reload };
}

export function roleTone(role: string): 'accent' | 'info' | 'neutral' {
  if (role === 'superadmin') return 'accent';
  if (role === 'admin' || role === 'moderator') return 'info';
  return 'neutral';
}

/* ── identity strip ───────────────────────────────────────────────────────── */

export interface DossierHeaderProps {
  detail: AdminUserDetail;
  size?: 'sm' | 'lg';
}

export function DossierHeader({ detail, size = 'sm' }: DossierHeaderProps) {
  const profile = detail.profile;
  if (!profile) {
    return <Notice tone="warning" title="Profile unavailable">The account row could not be read.</Notice>;
  }

  return (
    <div className="flex min-w-0 items-start gap-3">
      <Avatar
        path={profile.avatar_path}
        name={profile.display_name}
        username={profile.username}
        size={size === 'lg' ? 'xl' : 'md'}
        verified={profile.is_verified}
      />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span
            className={cn(
              'min-w-0 truncate text-ink',
              size === 'lg' ? 'font-display text-title1' : 'text-body-strong',
            )}
          >
            {profile.display_name}
          </span>
          <Link
            href={profileHref(profile.username)}
            className="focus-ring rounded-xs text-caption text-ink-2 underline-offset-4 hover:text-accent hover:underline"
          >
            {handle(profile.username)}
          </Link>
        </div>

        <div className="mt-1 flex flex-wrap items-center gap-1">
          {profile.is_suspended ? (
            <Badge tone="danger" icon="lock">
              {profile.suspended_until ? `until ${calendarDate(profile.suspended_until)}` : 'banned'}
            </Badge>
          ) : null}
          {profile.is_verified ? (
            <Badge tone="accent" icon="verified">
              verified
            </Badge>
          ) : null}
          {detail.roles.map((role) => (
            <Badge key={role} tone={roleTone(role)} icon="shield">
              {role}
            </Badge>
          ))}
          {profile.account_visibility !== 'public' ? (
            <Badge tone="neutral" icon="lock">
              {profile.account_visibility}
            </Badge>
          ) : null}
        </div>

        {profile.is_suspended && profile.suspension_reason ? (
          <p className="mt-1.5 text-caption text-danger">{profile.suspension_reason}</p>
        ) : null}
      </div>
    </div>
  );
}

/* ── the numbers a moderator actually decides on ──────────────────────────── */

export function DossierStats({ detail }: { detail: AdminUserDetail }) {
  const profile = detail.profile;
  const hiddenCount = detail.recent_content.filter((row) => row.hidden_at !== null).length;

  return (
    <div className="grid grid-cols-2 gap-x-4 gap-y-2.5 sm:grid-cols-3">
      <Field label="Reports against">
        <span
          className={cn('tabular', detail.reports_against > 0 ? 'text-danger' : 'text-ink')}
        >
          {groupDigits(detail.reports_against)}
        </span>
      </Field>
      <Field label="Reports filed">
        <span className="tabular">{groupDigits(detail.reports_filed)}</span>
      </Field>
      <Field label="Hidden content">
        <span className={cn('tabular', hiddenCount > 0 ? 'text-warning' : 'text-ink')}>
          {groupDigits(hiddenCount)}
        </span>
      </Field>
      <Field label="Followers">
        <span className="tabular">{groupDigits(profile?.follower_count ?? 0)}</span>
      </Field>
      <Field label="Items">
        <span className="tabular">{groupDigits(profile?.item_count ?? 0)}</span>
      </Field>
      <Field label="Joined">
        <TimeAgo value={profile?.created_at ?? null} />
      </Field>
    </div>
  );
}

/* ── moderation history ───────────────────────────────────────────────────── */

export function DossierHistory({ detail, limit = 5 }: { detail: AdminUserDetail; limit?: number }) {
  const actions = detail.actions.slice(0, limit);

  if (actions.length === 0) {
    return <p className="text-caption text-ink-3">No moderation history.</p>;
  }

  return (
    <ul className="flex flex-col gap-1.5">
      {actions.map((entry, index) => (
        <li
          key={`${entry.created_at}-${index}`}
          className="flex min-w-0 items-baseline justify-between gap-3"
        >
          <span className="min-w-0">
            <span className="text-caption text-ink">
              {MOD_ACTION_LABELS[entry.action] ?? entry.action}
            </span>
            {entry.reason ? (
              <span className="ml-1.5 text-caption text-ink-3">— {entry.reason}</span>
            ) : null}
          </span>
          <span className="shrink-0 text-caption text-ink-3">
            <TimeAgo value={entry.created_at} />
          </span>
        </li>
      ))}
    </ul>
  );
}

/* ── recent content ───────────────────────────────────────────────────────── */

export function DossierContent({ detail, limit = 6 }: { detail: AdminUserDetail; limit?: number }) {
  const rows = detail.recent_content.slice(0, limit);

  if (rows.length === 0) {
    return <p className="text-caption text-ink-3">No items yet.</p>;
  }

  return (
    <ul className="flex flex-col gap-1">
      {rows.map((row) => (
        <li key={row.id}>
          <Link
            href={itemHref(row.id)}
            className="focus-ring flex min-w-0 items-center gap-2 rounded-xs px-1 py-1 transition-colors dur-fast ease-standard hover:bg-surface-2"
          >
            <Icon name="image" size="xs" />
            <span className="min-w-0 flex-1 truncate text-caption text-ink">{row.title}</span>
            {row.hidden_at ? (
              <Badge tone="warning" title={`Hidden ${longTimeAgo(row.hidden_at)}`}>
                hidden
              </Badge>
            ) : null}
            <span className="shrink-0 text-caption text-ink-3">
              <TimeAgo value={row.created_at} />
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

/* ── loading shape ────────────────────────────────────────────────────────── */

export function DossierSkeleton() {
  return (
    <div className="flex flex-col gap-3">
      <SkeletonRow />
      <SkeletonText lines={3} />
    </div>
  );
}
