'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useMemo, useState } from 'react';
import { blockUser, muteUser, startDm, unblockUser, unmuteUser } from '@/lib/api';
import { SITE_URL } from '@/lib/env';
import { conversationHref, profileHref } from '@/lib/routes';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { Icon } from '@/components/ui/Icon';
import { ReportDialog } from '@/components/ui/ReportDialog';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { OverflowMenu, type OverflowItem } from './OverflowMenu';
import type { RelationshipState } from './queries';

/**
 * Everything you can do *to* a person: message, mute, block, report, copy link.
 *
 * Block is bidirectional and immediate server-side — content, DMs and
 * notifications all stop — so the confirm dialog says so plainly rather than
 * asking "Are you sure?" and leaving the user to guess.
 */
export interface UserActionsProps {
  userId: string;
  username: string;
  displayName: string;
  relationship: RelationshipState;
  /** Rendered before the overflow items, e.g. "Edit profile". */
  extraItems?: OverflowItem[];
  className?: string;
}

export function UserActions({
  userId,
  username,
  displayName,
  relationship,
  extraItems = [],
  className,
}: UserActionsProps) {
  const router = useRouter();
  const { supabase, user } = useSession();
  const { success, toast, fromError } = useToast();

  const [blocked, setBlocked] = useState(relationship.blocked);
  const [muted, setMuted] = useState(relationship.muted);
  const [reporting, setReporting] = useState(false);
  const [confirmingBlock, setConfirmingBlock] = useState(false);

  const isSelf = user?.id === userId;

  const requireAuth = useCallback((): boolean => {
    if (user) return true;
    toast({
      title: 'Sign in first',
      description: 'Messaging, muting and blocking need an account.',
      tone: 'accent',
      action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
    });
    return false;
  }, [toast, user]);

  const copyLink = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(`${SITE_URL}${profileHref(username)}`);
      success('Profile link copied');
    } catch (error) {
      fromError(error);
    }
  }, [fromError, success, username]);

  const message = useCallback(async () => {
    if (!requireAuth()) return;
    try {
      const conversationId = await startDm(supabase, userId);
      router.push(conversationHref(conversationId));
    } catch (error) {
      fromError(error);
    }
  }, [fromError, requireAuth, router, supabase, userId]);

  const toggleMute = useCallback(async () => {
    if (!requireAuth()) return;
    const next = !muted;
    setMuted(next);
    try {
      if (next) await muteUser(supabase, userId);
      else await unmuteUser(supabase, userId);
      success(next ? `Muted ${displayName}` : `Unmuted ${displayName}`);
    } catch (error) {
      setMuted(!next);
      fromError(error);
    }
  }, [displayName, fromError, muted, requireAuth, success, supabase, userId]);

  const applyBlock = useCallback(async () => {
    const next = !blocked;
    setBlocked(next);
    setConfirmingBlock(false);
    try {
      if (next) await blockUser(supabase, userId);
      else await unblockUser(supabase, userId);
      success(next ? `Blocked ${displayName}` : `Unblocked ${displayName}`);
      // Blocking changes what the server will render — re-run the RSC tree.
      router.refresh();
    } catch (error) {
      setBlocked(!next);
      fromError(error);
    }
  }, [blocked, displayName, fromError, router, success, supabase, userId]);

  const items = useMemo<OverflowItem[]>(() => {
    const list: OverflowItem[] = [...extraItems];

    list.push({ key: 'copy', label: 'Copy link to profile', icon: 'link', onSelect: () => void copyLink() });

    if (!isSelf) {
      list.push({ key: 'message', label: `Message ${displayName}`, icon: 'mail', onSelect: () => void message() });
      list.push({
        key: 'mute',
        label: muted ? 'Unmute' : 'Mute',
        icon: 'eye',
        onSelect: () => void toggleMute(),
      });
      list.push({
        key: 'block',
        label: blocked ? 'Unblock' : 'Block',
        icon: 'shield',
        destructive: !blocked,
        onSelect: () => {
          if (!requireAuth()) return;
          if (blocked) void applyBlock();
          else setConfirmingBlock(true);
        },
      });
      list.push({
        key: 'report',
        label: 'Report',
        icon: 'flag',
        destructive: true,
        onSelect: () => {
          if (requireAuth()) setReporting(true);
        },
      });
    }

    return list;
  }, [
    applyBlock,
    blocked,
    copyLink,
    displayName,
    extraItems,
    isSelf,
    message,
    muted,
    requireAuth,
    toggleMute,
  ]);

  return (
    <>
      <OverflowMenu items={items} label={`More options for ${displayName}`} className={className} />

      <ConfirmDialog
        open={confirmingBlock}
        onCancel={() => setConfirmingBlock(false)}
        onConfirm={applyBlock}
        title={`Block ${displayName}?`}
        description={`You will not see each other's collections, neither of you can message the other, and existing notifications between you stop. ${displayName} is not told.`}
        confirmLabel="Block"
        destructive
      />

      <ReportDialog
        open={reporting}
        onClose={() => setReporting(false)}
        target={{ kind: 'user', id: userId }}
        subject={`@${username}`}
      />
    </>
  );
}

/** The standalone "Message" button that sits next to Follow on a profile. */
export function MessageButton({
  userId,
  displayName,
  className,
}: {
  userId: string;
  displayName: string;
  className?: string;
}) {
  const router = useRouter();
  const { supabase, user } = useSession();
  const { toast, fromError } = useToast();
  const [busy, setBusy] = useState(false);

  if (user?.id === userId) return null;

  const open = async () => {
    if (!user) {
      toast({
        title: 'Sign in to message',
        tone: 'accent',
        action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
      });
      return;
    }
    setBusy(true);
    try {
      const conversationId = await startDm(supabase, userId);
      router.push(conversationHref(conversationId));
    } catch (error) {
      // `start_dm` enforces `allow_messages_from`; the error already says so.
      fromError(error);
      setBusy(false);
    }
  };

  return (
    <button
      type="button"
      onClick={() => void open()}
      disabled={busy}
      aria-label={`Message ${displayName}`}
      title={`Message ${displayName}`}
      className={
        'k-pressable focus-ring inline-flex size-11 items-center justify-center rounded-full ' +
        'border border-line bg-surface-2 text-ink-2 transition-colors dur-fast ' +
        'hover:bg-surface-3 hover:text-ink disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)] ' +
        (className ?? '')
      }
    >
      <Icon name="mail" size="lg" />
    </button>
  );
}
