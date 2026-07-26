'use client';

import Link from 'next/link';
import { useCallback, useState } from 'react';
import { unblockUser, unmuteUser } from '@/lib/api';
import { profileHref } from '@/lib/routes';
import type { ProfileRow } from '@/lib/types';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { Icon } from '@/components/ui/Icon';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * Blocked and muted, with plain-English copy about what each one actually does.
 * The difference matters and nobody reads a help centre.
 */
export function SettingsBlockedList({
  blocked,
  muted,
}: {
  blocked: ProfileRow[];
  muted: ProfileRow[];
}) {
  const { supabase } = useSession();
  const { success, fromError } = useToast();

  const [blockedList, setBlockedList] = useState(blocked);
  const [mutedList, setMutedList] = useState(muted);
  const [busy, setBusy] = useState<string | null>(null);

  const unblock = useCallback(
    async (profile: ProfileRow) => {
      setBusy(profile.id);
      const previous = blockedList;
      setBlockedList((current) => current.filter((entry) => entry.id !== profile.id));
      try {
        await unblockUser(supabase, profile.id);
        success(`Unblocked ${profile.display_name}`);
      } catch (error) {
        setBlockedList(previous);
        fromError(error);
      } finally {
        setBusy(null);
      }
    },
    [blockedList, fromError, success, supabase],
  );

  const unmute = useCallback(
    async (profile: ProfileRow) => {
      setBusy(profile.id);
      const previous = mutedList;
      setMutedList((current) => current.filter((entry) => entry.id !== profile.id));
      try {
        await unmuteUser(supabase, profile.id);
        success(`Unmuted ${profile.display_name}`);
      } catch (error) {
        setMutedList(previous);
        fromError(error);
      } finally {
        setBusy(null);
      }
    },
    [fromError, mutedList, success, supabase],
  );

  return (
    <section className="flex flex-col gap-10">
      <header>
        <h2 className="font-display text-title1 text-ink">Blocked and muted</h2>
        <p className="mt-1 text-callout text-ink-2">
          Two different tools. Blocking is a wall; muting is a curtain.
        </p>
      </header>

      <section>
        <h3 className="flex items-center gap-2 text-label uppercase tracking-widest text-ink-3">
          <Icon name="shield" size="sm" />
          Blocked
        </h3>
        <p className="mt-2 readable-max text-caption text-ink-2 md:mx-0">
          Blocking is bidirectional and immediate. Neither of you can see the other&apos;s
          collections, neither can message the other, and notifications between you stop.
          They are not told.
        </p>

        {blockedList.length === 0 ? (
          <EmptyState
            icon="shield"
            title="Nobody blocked"
            description="You can block someone from their profile's overflow menu."
            compact
          />
        ) : (
          <ul className="mt-4 flex flex-col gap-2">
            {blockedList.map((profile) => (
              <PersonRow
                key={profile.id}
                profile={profile}
                actionLabel="Unblock"
                busy={busy === profile.id}
                onAction={() => void unblock(profile)}
              />
            ))}
          </ul>
        )}
      </section>

      <section>
        <h3 className="flex items-center gap-2 text-label uppercase tracking-widest text-ink-3">
          <Icon name="eye" size="sm" />
          Muted
        </h3>
        <p className="mt-2 readable-max text-caption text-ink-2 md:mx-0">
          Muting is one-way and silent. Their collections stop appearing in your Surf and
          Pulse feeds and you stop getting notifications about them — but you stay
          followers, and they can still message you.
        </p>

        {mutedList.length === 0 ? (
          <EmptyState
            icon="eye"
            title="Nobody muted"
            description="Mute is on the same overflow menu as block, one item above it."
            compact
          />
        ) : (
          <ul className="mt-4 flex flex-col gap-2">
            {mutedList.map((profile) => (
              <PersonRow
                key={profile.id}
                profile={profile}
                actionLabel="Unmute"
                busy={busy === profile.id}
                onAction={() => void unmute(profile)}
              />
            ))}
          </ul>
        )}
      </section>
    </section>
  );
}

function PersonRow({
  profile,
  actionLabel,
  busy,
  onAction,
}: {
  profile: ProfileRow;
  actionLabel: string;
  busy: boolean;
  onAction: () => void;
}) {
  return (
    <li className="flex items-center gap-3 rounded-lg border border-line bg-surface-1 p-3">
      <Link
        href={profileHref(profile.username)}
        className="focus-ring flex min-w-0 flex-1 items-center gap-3 rounded-md"
      >
        <Avatar
          path={profile.avatar_path}
          name={profile.display_name}
          username={profile.username}
          verified={profile.is_verified}
        />
        <span className="min-w-0">
          <span className="block truncate text-body-strong text-ink">
            {profile.display_name}
          </span>
          <span className="block truncate text-caption text-ink-3">@{profile.username}</span>
        </span>
      </Link>
      <Button variant="secondary" size="sm" loading={busy} onClick={onAction}>
        {actionLabel}
      </Button>
    </li>
  );
}
