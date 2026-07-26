'use client';

import { useState } from 'react';
import { VISIBILITY_LABELS } from '@/lib/entities';
import type { ProfileRow } from '@/lib/types';
import { Button } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { Modal } from '@/components/ui/Modal';
import { TextField } from '@/components/ui/TextField';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { eraseAccountContent } from './queries';

/**
 * Sign out, and the account-deletion path.
 *
 * Honest about its limit: this client holds only the publishable key
 * (AGENTS.md §2), so it can erase everything you own — every collection and,
 * by cascade, its subcollections, items, media and polymorphic
 * likes/saves/comments/views — and blank the profile, but it cannot remove the
 * `auth.users` row. That needs a service-role call, and there is no edge
 * function for it yet. The dialog says so rather than implying otherwise.
 */
export function DangerZone({ profile }: { profile: ProfileRow }) {
  const { signOut, supabase } = useSession();
  const { success, fromError } = useToast();

  const [confirming, setConfirming] = useState(false);
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  const armed = typed.trim().toLowerCase() === profile.username.toLowerCase();

  const erase = async () => {
    if (!armed) return;
    setBusy(true);
    try {
      await eraseAccountContent(supabase, profile.id);
      success('Your collections and profile have been erased');
      setConfirming(false);
      await signOut();
    } catch (error) {
      fromError(error);
      setBusy(false);
    }
  };

  return (
    <section className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-line bg-surface-1 p-5">
        <div>
          <h3 className="text-body-strong text-ink">Sign out</h3>
          <p className="mt-1 text-caption text-ink-2">
            Ends the session on this device only.
          </p>
        </div>
        <Button
          variant="secondary"
          loading={signingOut}
          onClick={async () => {
            setSigningOut(true);
            await signOut();
            setSigningOut(false);
          }}
        >
          Sign out
        </Button>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-danger/40 bg-danger-subtle p-5">
        <div className="min-w-0">
          <h3 className="flex items-center gap-2 text-body-strong text-danger">
            <Icon name="alert" size="sm" />
            Delete account
          </h3>
          <p className="mt-1 readable-max text-caption text-ink-2 md:mx-0">
            Erases every collection you own and everything under it, blanks your profile,
            and locks the account to {VISIBILITY_LABELS.private.toLowerCase()}. This cannot
            be undone.
          </p>
        </div>
        <Button variant="danger" onClick={() => setConfirming(true)}>
          Delete account
        </Button>
      </div>

      <Modal
        open={confirming}
        onClose={() => setConfirming(false)}
        title="Delete your account?"
        description="Read this before you type anything."
        size="sm"
        dismissOnBackdrop={!busy}
        footer={
          <>
            <Button variant="ghost" onClick={() => setConfirming(false)} disabled={busy}>
              Keep my account
            </Button>
            <Button variant="danger" onClick={() => void erase()} loading={busy} disabled={!armed}>
              Erase everything
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-4 px-6 py-4">
          <ul className="flex flex-col gap-2 text-callout text-ink-2">
            <li className="flex items-start gap-2">
              <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-danger" />
              Every collection, subcollection, item and photo you own is deleted, along
              with the likes, saves, comments and views attached to them.
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-danger" />
              Your display name, bio, avatar, banner, location and website are cleared, and
              the account is set to private and closed to messages.
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-danger" />
              Your sign-in record itself is removed by support, not from this page — the
              web app never holds the key that can do it. Email us and it goes with the
              rest.
            </li>
          </ul>

          <TextField
            label={`Type ${profile.username} to confirm`}
            value={typed}
            onChange={(event) => setTyped(event.target.value)}
            autoComplete="off"
            placeholder={profile.username}
          />
        </div>
      </Modal>
    </section>
  );
}
