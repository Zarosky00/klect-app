'use client';

import { useCallback, useState } from 'react';
import { useRouter } from 'next/navigation';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { Icon, type IconName } from '@/components/ui/Icon';
import { ReportDialog } from '@/components/ui/ReportDialog';
import { Sheet } from '@/components/ui/Sheet';
import { blockUser, muteUser } from '@/lib/api';
import { cn } from '@/lib/cn';
import { entityHref, type EntityType } from '@/lib/entities';
import { SITE_URL } from '@/lib/env';
import { profileHref } from '@/lib/routes';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * The overflow. "The most common action is one gesture away, the rest are two,
 * nothing is three" — so the action bar stays to five controls and everything
 * rarer lives behind this sheet.
 */
export interface OverflowSheetProps {
  open: boolean;
  onClose: () => void;
  type: EntityType;
  id: string;
  title: string;
  owner: { id: string; username: string; displayName: string } | null;
  isOwner: boolean;
}

interface Row {
  key: string;
  icon: IconName;
  label: string;
  description?: string;
  danger?: boolean;
  run: () => void;
}

export function OverflowSheet({
  open,
  onClose,
  type,
  id,
  title,
  owner,
  isOwner,
}: OverflowSheetProps) {
  const router = useRouter();
  const { supabase, user } = useSession();
  const { success, fromError, toast } = useToast();
  const [reporting, setReporting] = useState(false);
  const [blocking, setBlocking] = useState(false);

  const url = `${SITE_URL}${entityHref(type, id)}`;

  const copyLink = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(url);
      success('Link copied');
    } catch (error) {
      fromError(error);
    }
    onClose();
  }, [fromError, onClose, success, url]);

  const requireAuth = useCallback((): boolean => {
    if (user) return true;
    toast({
      title: 'Sign in to do that',
      tone: 'accent',
      action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
    });
    return false;
  }, [toast, user]);

  const mute = useCallback(async () => {
    if (!owner) return;
    try {
      await muteUser(supabase, owner.id);
      success('Muted', `You will not see ${owner.displayName} in your feeds.`);
    } catch (error) {
      fromError(error);
    }
    onClose();
  }, [fromError, onClose, owner, success, supabase]);

  const block = useCallback(async () => {
    if (!owner) return;
    setBlocking(false);
    try {
      await blockUser(supabase, owner.id);
      success('Blocked', 'They can no longer see you, message you, or find your shelves.');
      router.refresh();
    } catch (error) {
      fromError(error);
    }
    onClose();
  }, [fromError, onClose, owner, router, success, supabase]);

  const rows: Row[] = [
    {
      key: 'copy',
      icon: 'link',
      label: 'Copy link',
      description: url.replace(/^https?:\/\//, ''),
      run: () => void copyLink(),
    },
    {
      key: 'open',
      icon: 'grid',
      label: 'Open the full page',
      run: () => {
        onClose();
        router.push(entityHref(type, id));
      },
    },
  ];

  if (owner && !isOwner) {
    rows.push({
      key: 'profile',
      icon: 'user',
      label: `View @${owner.username}`,
      run: () => {
        onClose();
        router.push(profileHref(owner.username));
      },
    });
    rows.push({
      key: 'mute',
      icon: 'eye',
      label: `Mute @${owner.username}`,
      description: 'Hides them from your feeds. They are never told.',
      run: () => {
        if (requireAuth()) void mute();
      },
    });
    rows.push({
      key: 'block',
      icon: 'shield',
      label: `Block @${owner.username}`,
      description: 'Bidirectional and immediate: content, DMs and notifications all stop.',
      danger: true,
      run: () => {
        if (requireAuth()) setBlocking(true);
      },
    });
  }

  if (!isOwner) {
    rows.push({
      key: 'report',
      icon: 'flag',
      label: 'Report',
      danger: true,
      run: () => {
        if (requireAuth()) setReporting(true);
      },
    });
  }

  return (
    <>
      <Sheet open={open} onClose={onClose} title={title} description="More actions">
        <ul className="flex flex-col">
          {rows.map((row) => (
            <li key={row.key}>
              <button
                type="button"
                onClick={row.run}
                className={cn(
                  'focus-ring flex w-full items-start gap-3 rounded-md px-2 py-3 text-left',
                  'transition-colors dur-fast ease-standard hover:bg-surface-2',
                  row.danger ? 'text-danger' : 'text-ink',
                )}
              >
                <span className="mt-0.5">
                  <Icon name={row.icon} size="md" />
                </span>
                <span className="min-w-0">
                  <span className="block text-body-strong">{row.label}</span>
                  {row.description ? (
                    <span className="block truncate text-caption text-ink-3">
                      {row.description}
                    </span>
                  ) : null}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </Sheet>

      <ReportDialog
        open={reporting}
        onClose={() => {
          setReporting(false);
          onClose();
        }}
        target={{ kind: 'entity', type, id }}
        subject={title}
      />

      <ConfirmDialog
        open={blocking}
        onCancel={() => setBlocking(false)}
        onConfirm={() => void block()}
        title={`Block @${owner?.username ?? ''}?`}
        description="Blocking is bidirectional and immediate. You can undo it in Settings → Blocked."
        confirmLabel="Block"
        destructive
      />
    </>
  );
}
