'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { sendMessage } from '@/lib/api';
import { cn } from '@/lib/cn';
import { entityHref, type EntityType } from '@/lib/entities';
import { SITE_URL } from '@/lib/env';
import { routes } from '@/lib/routes';
import { Icon, type IconName } from '@/components/ui/Icon';
import { Sheet } from '@/components/ui/Sheet';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { ConversationPicker } from './ConversationPicker';
import { conversationTitle, type ConversationSummary } from './queries';

/**
 * THE share chooser. Every share entry — the ActionBar share button (surf
 * tiles, closeup, pulse cards), the closeup overflow sheet, both long-press
 * peeks — routes here, so sharing feels identical everywhere:
 *
 *   Send to a friend  →  ConversationPicker, inserts the same `entity_share`
 *                        message shape `MessageThread.send` uses;
 *   Copy link         →  the canonical deep link on the clipboard;
 *   Share via system  →  `navigator.share`, offered only where it exists.
 *
 * Works for posts too — `entity_share` is polymorphic and the chat card
 * renders a post branch.
 */
export interface ShareMenuProps {
  open: boolean;
  onClose: () => void;
  type: EntityType;
  id: string;
  /** Handed to the system share sheet; falls back to the site name. */
  title?: string | undefined;
}

interface ShareRow {
  key: string;
  icon: IconName;
  label: string;
  description: string;
  run: () => void;
}

export function ShareMenu({ open, onClose, type, id, title }: ShareMenuProps) {
  const router = useRouter();
  const { supabase, user } = useSession();
  const { toast, success, fromError } = useToast();
  const [picking, setPicking] = useState(false);
  const [sendingTo, setSendingTo] = useState<string | null>(null);
  // `navigator.share` is read in an effect so the server render never branches
  // on a browser API (hydration must match).
  const [canSystemShare, setCanSystemShare] = useState(false);

  useEffect(() => {
    setCanSystemShare(typeof navigator !== 'undefined' && typeof navigator.share === 'function');
  }, []);

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

  const systemShare = useCallback(async () => {
    try {
      await navigator.share({ title: title ?? 'Klect', url });
      onClose();
    } catch (error) {
      // A cancelled share sheet throws AbortError; that is not a failure.
      if (error instanceof Error && error.name === 'AbortError') return;
      fromError(error);
    }
  }, [fromError, onClose, title, url]);

  const openPicker = useCallback(() => {
    if (!user) {
      toast({
        title: 'Sign in to do that',
        description: 'Sending to a friend needs an account.',
        tone: 'accent',
        action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
      });
      return;
    }
    setPicking(true);
  }, [toast, user]);

  const quoteInPulse = useCallback(() => {
    if (!user) {
      toast({
        title: 'Sign in to quote this',
        description: 'Add your take in Pulse after signing in.',
        tone: 'accent',
        action: { label: 'Sign in', onClick: () => window.location.assign(routes.signIn) },
      });
      return;
    }

    const params = new URLSearchParams({ quoteType: type, quoteId: id });
    onClose();
    router.push(`${routes.pulse}?${params.toString()}`);
  }, [id, onClose, router, toast, type, user]);

  const sendTo = useCallback(
    async (summary: ConversationSummary) => {
      if (!user) return;
      setSendingTo(summary.conversation.id);
      try {
        // The exact `entity_share` shape MessageThread.send inserts — triggers
        // handle the preview, unread bumps and notification fanout.
        await sendMessage(supabase, {
          conversation_id: summary.conversation.id,
          author_id: user.id,
          kind: 'entity_share',
          body: null,
          reply_to_id: null,
          attachments: [],
          shared_entity_type: type,
          shared_entity_id: id,
        });
        success('Sent', `Shared with ${conversationTitle(summary)}.`);
        setPicking(false);
        onClose();
      } catch (error) {
        fromError(error);
      } finally {
        setSendingTo(null);
      }
    },
    [fromError, id, onClose, success, supabase, type, user],
  );

  const rows: ShareRow[] = [
    {
      key: 'friend',
      icon: 'send',
      label: 'Send to a friend',
      description: 'Straight into a conversation, as a rich card.',
      run: openPicker,
    },
    ...(type !== 'comment'
      ? [
          {
            key: 'quote',
            icon: 'repost',
            label: 'Quote in Pulse',
            description: 'Add your take while keeping the original intact.',
            run: quoteInPulse,
          } satisfies ShareRow,
        ]
      : []),
    {
      key: 'copy',
      icon: 'link',
      label: 'Copy link',
      description: url.replace(/^https?:\/\//, ''),
      run: () => void copyLink(),
    },
    ...(canSystemShare
      ? [
          {
            key: 'system',
            icon: 'share',
            label: 'Share via…',
            description: 'Your device’s own share sheet.',
            run: () => void systemShare(),
          } satisfies ShareRow,
        ]
      : []),
  ];

  return (
    <>
      <Sheet open={open && !picking} onClose={onClose} title="Share" description={title ?? undefined}>
        <ul className="flex flex-col">
          {rows.map((row) => (
            <li key={row.key}>
              <button
                type="button"
                onClick={row.run}
                className={cn(
                  'focus-ring flex w-full items-start gap-3 rounded-md px-2 py-3 text-left text-ink',
                  'transition-colors dur-fast ease-standard hover:bg-surface-2',
                )}
              >
                <span className="mt-0.5">
                  <Icon name={row.icon} size="md" />
                </span>
                <span className="min-w-0">
                  <span className="block text-body-strong">{row.label}</span>
                  <span className="block truncate text-caption text-ink-3">
                    {row.description}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      </Sheet>

      <ConversationPicker
        open={picking}
        onClose={() => setPicking(false)}
        onPick={(summary) => void sendTo(summary)}
        busyId={sendingTo}
      />
    </>
  );
}
