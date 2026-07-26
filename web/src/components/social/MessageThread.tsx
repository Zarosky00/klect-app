'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { motion, useReducedMotion } from 'framer-motion';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { secs, duration } from '@/design/motion';
import {
  blockUser,
  deleteMessage,
  editMessage,
  markConversationRead,
  sendMessage,
} from '@/lib/api';
import { cn } from '@/lib/cn';
import { isEntityType, type EntityType } from '@/lib/entities';
import { calendarDate, clockTime, longTimeAgo } from '@/lib/format';
import { useCoarsePointer } from '@/lib/media-query';
import { profileHref } from '@/lib/routes';
import type { MessageRow, ProfileRow } from '@/lib/types';
import { Avatar } from '@/components/ui/Avatar';
import { Button, IconButton } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { EmptyState } from '@/components/ui/EmptyState';
import { Icon } from '@/components/ui/Icon';
import { ReportDialog } from '@/components/ui/ReportDialog';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { ImmersiveViewer, type ImmersivePhoto } from './ImmersiveViewer';
import { MessageComposer, type ComposerAttachment } from './MessageComposer';
import { OverflowMenu, type OverflowItem } from './OverflowMenu';
import { SharedEntityCard } from './SharedEntityCard';
import {
  conversationTitle,
  fetchSharedEntities,
  listMessageReactions,
  listMessageReceipts,
  recordMessageReceipts,
  toggleMessageReaction,
  updateConversationMembership,
  type ConversationMemberRow,
  type ConversationSummary,
  type EntitySummary,
  type MessageReactionRow,
  type MessageReceiptRow,
} from './queries';

/**
 * One conversation: realtime messages, typing over broadcast, presence,
 * reactions, replies, read receipts, photos and shared-entity cards.
 *
 * Two things worth knowing before editing this file:
 *
 *   · Typing and presence go over Realtime **broadcast/presence**, never a
 *     table (BACKEND_API §3). A `typing` row would be a write per keystroke.
 *   · Messages are sent by INSERT, not an RPC. Triggers then update the
 *     conversation preview, bump every other member's `unread_count`, and fan
 *     out notifications — so the client writes one row and nothing else.
 *
 * Calls are out of scope on web: the header offers a clear hand-off to mobile
 * rather than a button that cannot work.
 */

export const REACTION_CHOICES = ['❤️', '🔥', '😂', '👏', '😮', '😢'] as const;

/** How long a peer stays "typing" after their last keystroke broadcast. */
const TYPING_TTL_MS = 3200;

/** Mute horizon — mirrors mobile's "Mute for a week" (`Duration(days: 7)`). */
const MUTE_WEEK_MS = 7 * 24 * 60 * 60 * 1000;

interface Attachment {
  path: string;
  width: number | null;
  height: number | null;
  blurhash: string | null;
  mime: string;
  bytes: number;
}

function parseAttachments(value: unknown): Attachment[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== 'object') return [];
    const record = entry as Record<string, unknown>;
    const path = typeof record['path'] === 'string' ? record['path'] : null;
    if (!path) return [];
    return [
      {
        path,
        width: typeof record['width'] === 'number' ? record['width'] : null,
        height: typeof record['height'] === 'number' ? record['height'] : null,
        blurhash: typeof record['blurhash'] === 'string' ? record['blurhash'] : null,
        mime: typeof record['mime'] === 'string' ? record['mime'] : 'image/webp',
        bytes: typeof record['bytes'] === 'number' ? record['bytes'] : 0,
      },
    ];
  });
}

export interface MessageThreadProps {
  summary: ConversationSummary;
  viewerId: string;
  initialMessages: MessageRow[];
}

export function MessageThread({ summary, viewerId, initialMessages }: MessageThreadProps) {
  const { supabase } = useSession();
  const { fromError, success } = useToast();

  const conversationId = summary.conversation.id;
  const other = summary.others[0];
  const title = conversationTitle(summary);

  const [messages, setMessages] = useState<MessageRow[]>(initialMessages);
  const [reactions, setReactions] = useState<MessageReactionRow[]>([]);
  const [receipts, setReceipts] = useState<MessageReceiptRow[]>([]);
  const [shared, setShared] = useState<Map<string, EntitySummary>>(new Map());
  const [signed, setSigned] = useState<Map<string, string>>(new Map());
  const [typing, setTyping] = useState<Record<string, number>>({});
  const [online, setOnline] = useState<Set<string>>(new Set());
  const [replyTo, setReplyTo] = useState<MessageRow | null>(null);
  const [reportingMessage, setReportingMessage] = useState<MessageRow | null>(null);
  const [reportingUser, setReportingUser] = useState(false);
  const [blocking, setBlocking] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<MessageRow | null>(null);
  const [membership, setMembership] = useState<ConversationMemberRow | null>(summary.membership);
  const [viewer, setViewer] = useState<{ photos: ImmersivePhoto[]; index: number } | null>(null);
  const [sending, setSending] = useState(false);
  /** Optimistic rows awaiting their server echo — rendered as "Sending…". */
  const [pendingIds, setPendingIds] = useState<ReadonlySet<string>>(new Set());

  const bottomRef = useRef<HTMLDivElement | null>(null);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const knownIds = useRef(new Set(initialMessages.map((message) => message.id)));

  const byId = useMemo(
    () => new Map(messages.map((message) => [message.id, message])),
    [messages],
  );
  const profilesById = useMemo(() => {
    const map = new Map<string, ProfileRow>();
    for (const profile of summary.others) map.set(profile.id, profile);
    return map;
  }, [summary.others]);

  /* ── metadata hydration ─────────────────────────────────────────────────── */

  const hydrate = useCallback(
    async (list: MessageRow[]) => {
      const ids = list.map((message) => message.id);
      const [nextReactions, nextReceipts] = await Promise.all([
        listMessageReactions(supabase, ids),
        listMessageReceipts(supabase, ids),
      ]);
      setReactions(nextReactions);
      setReceipts(nextReceipts);

      const refs = list
        .filter(
          (message) =>
            isEntityType(message.shared_entity_type) && Boolean(message.shared_entity_id),
        )
        .map((message) => ({
          type: message.shared_entity_type as EntityType,
          id: message.shared_entity_id as string,
        }));
      if (refs.length > 0) setShared(await fetchSharedEntities(supabase, refs));

      const paths = list.flatMap((message) =>
        parseAttachments(message.attachments).map((attachment) => attachment.path),
      );
      const missing = [...new Set(paths)].filter((path) => !signed.has(path));
      if (missing.length > 0) {
        // The `chat` bucket is private, so every photo needs a signed URL.
        const { data } = await supabase.storage.from('chat').createSignedUrls(missing, 3600);
        if (data) {
          setSigned((current) => {
            const next = new Map(current);
            for (const entry of data) {
              if (entry.path && entry.signedUrl) next.set(entry.path, entry.signedUrl);
            }
            return next;
          });
        }
      }
    },
    [signed, supabase],
  );

  useEffect(() => {
    void hydrate(messages).catch(() => {
      // Metadata is additive; the messages themselves are already on screen.
    });
    // `hydrate` closes over `signed`, which it also sets — depend on messages only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages]);

  /* ── read state ─────────────────────────────────────────────────────────── */

  const markRead = useCallback(() => {
    void markConversationRead(supabase, conversationId).catch(() => {
      // Losing a read-marker is never worth interrupting the reader.
    });
    const unreadFromOthers = messages
      .filter((message) => message.author_id !== viewerId)
      .map((message) => message.id);
    void recordMessageReceipts(supabase, unreadFromOthers, viewerId).catch(() => {
      // Same: receipts are a courtesy, not a correctness requirement.
    });
  }, [conversationId, messages, supabase, viewerId]);

  useEffect(() => {
    markRead();
    // Re-mark whenever the tab regains focus with the thread open.
    const onFocus = () => markRead();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [markRead]);

  /* ── realtime ───────────────────────────────────────────────────────────── */

  useEffect(() => {
    const channel = supabase.channel(`conv:${conversationId}`, {
      config: { presence: { key: viewerId } },
    });
    channelRef.current = channel;

    channel
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages',
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          const row = payload.new as MessageRow;
          if (knownIds.current.has(row.id)) return;
          knownIds.current.add(row.id);
          setMessages((current) => [...current, row]);
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'messages',
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          const row = payload.new as MessageRow;
          setMessages((current) =>
            current.map((message) => (message.id === row.id ? row : message)),
          );
        },
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'message_reactions' },
        (payload) => {
          const row = (payload.new ?? payload.old) as MessageReactionRow | undefined;
          if (!row || !knownIds.current.has(row.message_id)) return;
          if (payload.eventType === 'DELETE') {
            setReactions((current) =>
              current.filter(
                (entry) =>
                  !(
                    entry.message_id === row.message_id &&
                    entry.user_id === row.user_id &&
                    entry.emoji === row.emoji
                  ),
              ),
            );
          } else {
            setReactions((current) =>
              current.some(
                (entry) =>
                  entry.message_id === row.message_id &&
                  entry.user_id === row.user_id &&
                  entry.emoji === row.emoji,
              )
                ? current
                : [...current, row],
            );
          }
        },
      )
      .on('broadcast', { event: 'typing' }, ({ payload }) => {
        const actor = (payload as { userId?: string }).userId;
        if (!actor || actor === viewerId) return;
        setTyping((current) => ({ ...current, [actor]: Date.now() }));
      })
      .on('presence', { event: 'sync' }, () => {
        setOnline(new Set(Object.keys(channel.presenceState())));
      })
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') void channel.track({ at: Date.now() });
      });

    return () => {
      channelRef.current = null;
      void supabase.removeChannel(channel);
    };
  }, [conversationId, supabase, viewerId]);

  // Expire stale typing markers rather than trusting a "stopped" broadcast that
  // may never arrive if the peer closes the tab mid-word.
  useEffect(() => {
    const timer = setInterval(() => {
      setTyping((current) => {
        const now = Date.now();
        const next: Record<string, number> = {};
        let changed = false;
        for (const [id, at] of Object.entries(current)) {
          if (now - at < TYPING_TTL_MS) next[id] = at;
          else changed = true;
        }
        return changed ? next : current;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  const broadcastTyping = useCallback(() => {
    void channelRef.current?.send({
      type: 'broadcast',
      event: 'typing',
      payload: { userId: viewerId },
    });
  }, [viewerId]);

  /* ── scrolling ──────────────────────────────────────────────────────────── */

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: 'end' });
  }, [messages.length]);

  /* ── sending ────────────────────────────────────────────────────────────── */

  const send = useCallback(
    async (input: {
      body: string;
      attachments: ComposerAttachment[];
      sharedEntity: EntitySummary | null;
    }) => {
      const trimmed = input.body.trim();
      if (!trimmed && input.attachments.length === 0 && !input.sharedEntity) return;

      const kind = input.sharedEntity
        ? 'entity_share'
        : input.attachments.length > 0
          ? 'image'
          : 'text';
      const attachments = input.attachments.map((attachment) => ({
        path: attachment.path,
        width: attachment.width,
        height: attachment.height,
        blurhash: attachment.blurhash,
        mime: attachment.mime,
        bytes: attachment.bytes,
      }));

      // Optimistic pending bubble (mobile parity): the message appears the
      // instant Send is pressed, marked "Sending…", and is reconciled against
      // the insert's return — or the realtime echo, whichever lands first.
      // A real UUID keeps the metadata hydrators (uuid columns) happy.
      const tempId = crypto.randomUUID();
      const stamp = new Date().toISOString();
      const optimistic: MessageRow = {
        id: tempId,
        conversation_id: conversationId,
        author_id: viewerId,
        kind,
        body: trimmed || null,
        call_id: null,
        reply_to_id: replyTo?.id ?? null,
        attachments,
        shared_entity_type: input.sharedEntity?.type ?? null,
        shared_entity_id: input.sharedEntity?.id ?? null,
        created_at: stamp,
        updated_at: stamp,
        edited_at: null,
        deleted_at: null,
      };
      if (input.sharedEntity) {
        // Seed the card immediately — no tombstone flash while hydrate runs.
        const entity = input.sharedEntity;
        setShared((current) => {
          const next = new Map(current);
          next.set(`${entity.type}:${entity.id}`, entity);
          return next;
        });
      }
      setPendingIds((current) => new Set(current).add(tempId));
      setMessages((current) => [...current, optimistic]);

      setSending(true);
      try {
        const row = await sendMessage(supabase, {
          conversation_id: conversationId,
          author_id: viewerId,
          kind,
          body: trimmed || null,
          reply_to_id: replyTo?.id ?? null,
          attachments,
          shared_entity_type: input.sharedEntity?.type ?? null,
          shared_entity_id: input.sharedEntity?.id ?? null,
        });

        if (knownIds.current.has(row.id)) {
          // The realtime echo beat the return — the row is already on screen.
          setMessages((current) => current.filter((message) => message.id !== tempId));
        } else {
          knownIds.current.add(row.id);
          setMessages((current) =>
            current.map((message) => (message.id === tempId ? row : message)),
          );
        }
        setReplyTo(null);
      } catch (error) {
        setMessages((current) => current.filter((message) => message.id !== tempId));
        // The composer keeps the draft — the caller never loses typed text.
        fromError(error);
        throw error;
      } finally {
        setPendingIds((current) => {
          const next = new Set(current);
          next.delete(tempId);
          return next;
        });
        setSending(false);
      }
    },
    [conversationId, fromError, replyTo, supabase, viewerId],
  );

  const react = useCallback(
    async (messageId: string, emoji: string) => {
      const active = !reactions.some(
        (entry) =>
          entry.message_id === messageId && entry.user_id === viewerId && entry.emoji === emoji,
      );
      // Optimistic: the bubble updates before the round trip.
      setReactions((current) =>
        active
          ? [...current, { message_id: messageId, user_id: viewerId, emoji, created_at: new Date().toISOString() }]
          : current.filter(
              (entry) =>
                !(
                  entry.message_id === messageId &&
                  entry.user_id === viewerId &&
                  entry.emoji === emoji
                ),
            ),
      );
      try {
        await toggleMessageReaction(supabase, messageId, viewerId, emoji, active);
      } catch (error) {
        setReactions((current) =>
          active
            ? current.filter(
                (entry) =>
                  !(
                    entry.message_id === messageId &&
                    entry.user_id === viewerId &&
                    entry.emoji === emoji
                  ),
              )
            : [...current, { message_id: messageId, user_id: viewerId, emoji, created_at: new Date().toISOString() }],
        );
        fromError(error);
      }
    },
    [fromError, reactions, supabase, viewerId],
  );

  /* ── own-message edit / delete (mobile semantics: edit stamps `edited_at`,
        delete soft-deletes for everyone) ─────────────────────────────────── */

  const submitEdit = useCallback(
    async (message: MessageRow, body: string) => {
      const trimmed = body.trim();
      setEditingId(null);
      if (!trimmed || trimmed === message.body) return;
      const stamp = new Date().toISOString();
      // Optimistic; the realtime UPDATE echo confirms it.
      setMessages((current) =>
        current.map((entry) =>
          entry.id === message.id ? { ...entry, body: trimmed, edited_at: stamp } : entry,
        ),
      );
      try {
        await editMessage(supabase, message.id, viewerId, trimmed);
      } catch (error) {
        setMessages((current) =>
          current.map((entry) => (entry.id === message.id ? message : entry)),
        );
        fromError(error);
      }
    },
    [fromError, supabase, viewerId],
  );

  const confirmDelete = useCallback(async () => {
    if (!deleting) return;
    const target = deleting;
    try {
      await deleteMessage(supabase, target.id, viewerId);
      const stamp = new Date().toISOString();
      setMessages((current) =>
        current.map((entry) =>
          entry.id === target.id ? { ...entry, deleted_at: stamp, body: null } : entry,
        ),
      );
      setDeleting(null);
    } catch (error) {
      fromError(error);
    }
  }, [deleting, fromError, supabase, viewerId]);

  /* ── per-viewer conversation flags ──────────────────────────────────────── */

  const patchMembership = useCallback(
    async (patch: Partial<Pick<ConversationMemberRow, 'pinned' | 'archived_at' | 'muted_until'>>) => {
      if (!membership) return;
      const previous = membership;
      setMembership({ ...membership, ...patch });
      try {
        await updateConversationMembership(supabase, conversationId, viewerId, patch);
      } catch (error) {
        setMembership(previous);
        fromError(error);
      }
    },
    [conversationId, fromError, membership, supabase, viewerId],
  );

  const isPinned = Boolean(membership?.pinned);
  const isArchived = Boolean(membership?.archived_at);
  const isMuted = membership?.muted_until
    ? new Date(membership.muted_until).getTime() > Date.now()
    : false;
  const isDm = summary.others.length === 1 && other !== undefined;

  const overflowItems: OverflowItem[] = [
    {
      key: 'profile',
      label: 'Open profile',
      icon: 'user',
      disabled: !other,
      onSelect: () => {
        if (other) window.location.assign(profileHref(other.username));
      },
    },
    {
      key: 'pin',
      label: isPinned ? 'Unpin' : 'Pin to top',
      icon: 'pin',
      disabled: !membership,
      onSelect: () => void patchMembership({ pinned: !isPinned }),
    },
    {
      key: 'mute',
      label: isMuted ? 'Unmute' : 'Mute for a week',
      icon: isMuted ? 'bell' : 'bell-off',
      disabled: !membership,
      onSelect: () =>
        void patchMembership({
          muted_until: isMuted ? null : new Date(Date.now() + MUTE_WEEK_MS).toISOString(),
        }),
    },
    {
      key: 'archive',
      label: isArchived ? 'Move to inbox' : 'Archive',
      icon: 'archive',
      disabled: !membership,
      onSelect: () =>
        void patchMembership({
          archived_at: isArchived ? null : new Date().toISOString(),
        }),
    },
    ...(isDm && other
      ? ([
          {
            key: 'report-user',
            label: `Report @${other.username}`,
            icon: 'flag',
            onSelect: () => setReportingUser(true),
          },
          {
            key: 'block',
            label: `Block @${other.username}`,
            icon: 'block',
            destructive: true,
            onSelect: () => setBlocking(true),
          },
        ] satisfies OverflowItem[])
      : []),
  ];

  const typingNames = Object.keys(typing)
    .map((id) => profilesById.get(id)?.display_name)
    .filter((name): name is string => Boolean(name));

  const isOnline = other ? online.has(other.id) : false;

  /* ── render ─────────────────────────────────────────────────────────────── */

  return (
    <>
      <header className="flex items-center gap-3 border-b border-line-subtle px-4 py-3">
        <Link
          href="/messages"
          aria-label="Back to conversations"
          className="focus-ring -ml-1 grid size-9 shrink-0 place-items-center rounded-full text-ink-2 hover:text-ink md:hidden"
        >
          <Icon name="arrow-left" size="lg" />
        </Link>

        {other ? (
          <Link
            href={profileHref(other.username)}
            className="focus-ring flex min-w-0 flex-1 items-center gap-3 rounded-md"
          >
            <span className="relative">
              <Avatar
                path={other.avatar_path}
                name={other.display_name}
                username={other.username}
                verified={other.is_verified}
              />
              {isOnline ? (
                <span
                  className="absolute -bottom-0.5 -right-0.5 size-3 rounded-full bg-success ring-2 ring-base"
                  title="Online now"
                  aria-label="Online now"
                />
              ) : null}
            </span>
            <span className="min-w-0">
              <span className="block truncate text-body-strong text-ink">{title}</span>
              <span className="block truncate text-caption text-ink-3">
                {typingNames.length > 0
                  ? 'typing…'
                  : isOnline
                    ? 'Online'
                    : `@${other.username}`}
              </span>
            </span>
          </Link>
        ) : (
          <span className="min-w-0 flex-1 truncate text-body-strong text-ink">{title}</span>
        )}

        <CallHandoff name={other?.display_name ?? title} />

        <OverflowMenu label="Conversation options" items={overflowItems} />
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">
        {messages.length === 0 ? (
          <EmptyState
            icon="send"
            title="Say something"
            description={`This is the beginning of your conversation with ${other?.display_name ?? title}.`}
            compact
          />
        ) : (
          <ol className="flex flex-col gap-1">
            {messages.map((message, index) => {
              const previous = messages[index - 1];
              const newDay =
                !previous ||
                new Date(previous.created_at).toDateString() !==
                  new Date(message.created_at).toDateString();
              const mine = message.author_id === viewerId;
              const author = profilesById.get(message.author_id) ?? null;
              const grouped =
                !newDay &&
                previous?.author_id === message.author_id &&
                new Date(message.created_at).getTime() -
                  new Date(previous.created_at).getTime() <
                  5 * 60 * 1000;

              return (
                <li key={message.id}>
                  {newDay ? (
                    <div className="my-4 flex items-center gap-3" role="separator">
                      <span className="h-px flex-1 bg-line-subtle" />
                      <span className="text-micro uppercase tracking-widest text-ink-3">
                        {calendarDate(message.created_at)}
                      </span>
                      <span className="h-px flex-1 bg-line-subtle" />
                    </div>
                  ) : null}

                  <MessageBubble
                    message={message}
                    mine={mine}
                    grouped={grouped}
                    author={author}
                    replyTarget={message.reply_to_id ? (byId.get(message.reply_to_id) ?? null) : null}
                    replyAuthor={
                      message.reply_to_id
                        ? (profilesById.get(byId.get(message.reply_to_id)?.author_id ?? '') ?? null)
                        : null
                    }
                    reactions={reactions.filter((entry) => entry.message_id === message.id)}
                    viewerId={viewerId}
                    readByOthers={receipts.some(
                      (receipt) =>
                        receipt.message_id === message.id && receipt.user_id !== viewerId,
                    )}
                    pending={pendingIds.has(message.id)}
                    sharedEntity={
                      message.shared_entity_type && message.shared_entity_id
                        ? (shared.get(
                            `${message.shared_entity_type}:${message.shared_entity_id}`,
                          ) ?? null)
                        : undefined
                    }
                    signedUrls={signed}
                    editing={editingId === message.id}
                    onReply={() => setReplyTo(message)}
                    onReact={(emoji) => void react(message.id, emoji)}
                    onReport={() => setReportingMessage(message)}
                    onEdit={() => setEditingId(message.id)}
                    onEditCancel={() => setEditingId(null)}
                    onEditSave={(body) => void submitEdit(message, body)}
                    onDelete={() => setDeleting(message)}
                    onOpenPhoto={(photos, at) => setViewer({ photos, index: at })}
                  />
                </li>
              );
            })}
          </ol>
        )}

        {typingNames.length > 0 ? (
          <p aria-live="polite" className="mt-3 flex items-center gap-2 text-caption text-ink-3">
            <span className="flex gap-1" aria-hidden>
              <TypingDot delay={0} />
              <TypingDot delay={0.15} />
              <TypingDot delay={0.3} />
            </span>
            {typingNames.join(', ')} {typingNames.length === 1 ? 'is' : 'are'} typing
          </p>
        ) : null}

        <div ref={bottomRef} />
      </div>

      <MessageComposer
        conversationId={conversationId}
        viewerId={viewerId}
        sending={sending}
        replyTo={replyTo}
        replyAuthorName={
          replyTo ? (profilesById.get(replyTo.author_id)?.display_name ?? 'You') : null
        }
        onCancelReply={() => setReplyTo(null)}
        onTyping={broadcastTyping}
        onSend={send}
      />

      <ReportDialog
        open={reportingMessage !== null}
        onClose={() => setReportingMessage(null)}
        target={{ kind: 'message', id: reportingMessage?.id ?? '' }}
        subject={reportingMessage?.body ?? 'a message'}
      />

      <ReportDialog
        open={reportingUser}
        onClose={() => setReportingUser(false)}
        target={{ kind: 'user', id: other?.id ?? '' }}
        subject={other ? `@${other.username}` : 'this account'}
      />

      <ConfirmDialog
        open={blocking}
        onCancel={() => setBlocking(false)}
        destructive
        title={other ? `Block @${other.username}?` : 'Block?'}
        description="They can no longer message you or interact with your content. You can unblock them any time in Settings → Blocked."
        confirmLabel="Block"
        onConfirm={async () => {
          if (!other) return;
          try {
            await blockUser(supabase, other.id);
            setBlocking(false);
            success('Blocked', `@${other.username} can no longer reach you.`);
          } catch (error) {
            fromError(error);
          }
        }}
      />

      <ConfirmDialog
        open={deleting !== null}
        onCancel={() => setDeleting(null)}
        destructive
        title="Delete message?"
        description="It disappears for everyone in the conversation. This cannot be undone."
        confirmLabel="Delete"
        onConfirm={confirmDelete}
      />

      <ImmersiveViewer
        open={viewer !== null}
        onClose={() => setViewer(null)}
        photos={viewer?.photos ?? []}
        initialIndex={viewer?.index ?? 0}
        title={title}
      />
    </>
  );
}

/** Three dots that breathe. Reduced motion drops the travel, keeps the dots. */
function TypingDot({ delay }: { delay: number }) {
  const reduced = useReducedMotion();
  if (reduced) return <span className="size-1.5 rounded-full bg-ink-3" />;
  return (
    <motion.span
      className="size-1.5 rounded-full bg-ink-3"
      animate={{ opacity: [0.3, 1, 0.3], y: [0, -2, 0] }}
      transition={{
        duration: secs(duration.deliberate * 2),
        ease: 'easeInOut',
        repeat: Infinity,
        delay,
      }}
    />
  );
}

/** Calls are mobile-only; say so plainly instead of shipping a dead button. */
function CallHandoff({ name }: { name: string }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <IconButton
        icon="activity"
        label="Call"
        size="sm"
        variant="ghost"
        onClick={() => setOpen((current) => !current)}
      />
      {open ? (
        <div
          role="status"
          className="absolute right-0 top-11 z-raised w-64 rounded-lg border border-line bg-surface-2 p-4 shadow-high"
        >
          <p className="text-body-strong text-ink">Calls live on mobile</p>
          <p className="mt-1 text-caption text-ink-2">
            Audio and video calls with {name} run in the Klect app, where the microphone,
            camera and background audio all work properly.
          </p>
          <Button
            variant="ghost"
            size="sm"
            className="mt-3"
            onClick={() => setOpen(false)}
          >
            Got it
          </Button>
        </div>
      ) : null}
    </div>
  );
}

/* ── one bubble ───────────────────────────────────────────────────────────── */

interface MessageBubbleProps {
  message: MessageRow;
  mine: boolean;
  grouped: boolean;
  author: ProfileRow | null;
  replyTarget: MessageRow | null;
  replyAuthor: ProfileRow | null;
  reactions: MessageReactionRow[];
  viewerId: string;
  readByOthers: boolean;
  /** Optimistic — inserted locally, still awaiting the server echo. */
  pending?: boolean;
  /** `undefined` = nothing shared. `null` = shared but no longer visible. */
  sharedEntity: EntitySummary | null | undefined;
  signedUrls: Map<string, string>;
  /** This bubble is in inline-edit mode. */
  editing: boolean;
  onReply: () => void;
  onReact: (emoji: string) => void;
  onReport: () => void;
  onEdit: () => void;
  onEditCancel: () => void;
  onEditSave: (body: string) => void;
  onDelete: () => void;
  onOpenPhoto: (photos: ImmersivePhoto[], index: number) => void;
}

function MessageBubble({
  message,
  mine,
  grouped,
  author,
  replyTarget,
  replyAuthor,
  reactions,
  viewerId,
  readByOthers,
  pending = false,
  sharedEntity,
  signedUrls,
  editing,
  onReply,
  onReact,
  onReport,
  onEdit,
  onEditCancel,
  onEditSave,
  onDelete,
  onOpenPhoto,
}: MessageBubbleProps) {
  const [pickerOpen, setPickerOpen] = useState(false);
  // Hover cannot reveal the action cluster on touch — a tap on the bubble
  // (anywhere that is not itself a control) toggles it instead.
  const coarse = useCoarsePointer();
  const [touchRevealed, setTouchRevealed] = useState(false);
  const attachments = parseAttachments(message.attachments);

  const photos: ImmersivePhoto[] = attachments.map((attachment, index) => ({
    id: `${message.id}:${index}`,
    src: signedUrls.get(attachment.path) ?? null,
    alt: message.body ?? `Photo ${index + 1}`,
    width: attachment.width,
    height: attachment.height,
  }));

  const reactionGroups = reactions.reduce<Record<string, string[]>>((accumulator, entry) => {
    const bucket = accumulator[entry.emoji] ?? [];
    bucket.push(entry.user_id);
    accumulator[entry.emoji] = bucket;
    return accumulator;
  }, {});

  if (message.deleted_at) {
    return (
      <div className={cn('flex px-1 py-1', mine ? 'justify-end' : 'justify-start')}>
        <span className="rounded-lg border border-line-subtle px-3 py-1.5 text-caption italic text-ink-3">
          Message deleted
        </span>
      </div>
    );
  }

  if (message.kind === 'system' || message.kind === 'call_event') {
    return (
      <div className="flex justify-center py-2">
        <span className="rounded-full bg-surface-2 px-3 py-1 text-caption text-ink-3">
          {message.body ?? 'Call'}
        </span>
      </div>
    );
  }

  return (
    <div
      className={cn(
        'group/message flex items-end gap-2',
        mine ? 'flex-row-reverse' : 'flex-row',
        grouped ? 'mt-0.5' : 'mt-3',
      )}
      onClick={
        coarse
          ? (event) => {
              // A tap on a real control (photo, reaction, the actions
              // themselves) must not also toggle the cluster.
              if ((event.target as HTMLElement).closest('button, a, textarea')) return;
              setTouchRevealed((current) => !current);
            }
          : undefined
      }
    >
      <span className={cn('w-8 shrink-0', grouped && 'invisible')}>
        {!mine ? (
          <Avatar path={author?.avatar_path} name={author?.display_name} size="sm" />
        ) : null}
      </span>

      <div
        className={cn(
          'flex min-w-0 max-w-[min(36rem,78%)] flex-col',
          mine && 'items-end',
          // The pending bubble reads as "on its way" without layout shift.
          pending && 'opacity-[var(--k-opacity-disabled)]',
        )}
      >
        {replyTarget ? (
          <span
            className={cn(
              'mb-1 max-w-full truncate rounded-md border-l-2 border-accent bg-surface-2 px-2 py-1 text-caption text-ink-3',
            )}
          >
            <span className="text-ink-2">{replyAuthor?.display_name ?? 'Someone'}</span>{' '}
            {replyTarget.body ?? 'a photo'}
          </span>
        ) : null}

        {sharedEntity !== undefined ? (
          <SharedEntityCard summary={sharedEntity} className="mb-1" />
        ) : null}

        {photos.length > 0 ? (
          <div className={cn('mb-1 grid gap-1', photos.length > 1 ? 'grid-cols-2' : 'grid-cols-1')}>
            {photos.map((photo, index) => (
              <button
                key={photo.id}
                type="button"
                onClick={() => onOpenPhoto(photos, index)}
                aria-label={`Open photo ${index + 1} of ${photos.length}`}
                className="focus-ring k-pressable overflow-hidden rounded-lg border border-line-subtle"
              >
                {photo.src ? (
                  /* eslint-disable-next-line @next/next/no-img-element -- signed
                     Storage URL, host varies per environment. */
                  <img
                    src={photo.src}
                    alt={photo.alt}
                    className="max-h-80 w-full object-cover"
                    loading="lazy"
                    decoding="async"
                  />
                ) : (
                  <span className="grid h-40 w-full place-items-center bg-skeleton text-ink-3">
                    <Icon name="image" size="lg" />
                  </span>
                )}
              </button>
            ))}
          </div>
        ) : null}

        {editing ? (
          <MessageEditBox
            initial={message.body ?? ''}
            onCancel={onEditCancel}
            onSave={onEditSave}
          />
        ) : message.body ? (
          <span
            className={cn(
              'whitespace-pre-wrap break-words rounded-2xl px-3.5 py-2 text-body',
              mine
                ? 'bg-accent text-ink-on-accent'
                : 'border border-line-subtle bg-surface-2 text-ink',
            )}
          >
            {message.body}
          </span>
        ) : null}

        <span className="mt-1 flex items-center gap-2 text-micro text-ink-3">
          <time dateTime={message.created_at} title={longTimeAgo(message.created_at)}>
            {clockTime(message.created_at)}
          </time>
          {message.edited_at ? <span>· edited</span> : null}
          {mine ? (
            pending ? (
              <span className="inline-flex items-center gap-1" aria-label="Sending">
                <Icon name="spinner" size="xs" />
                Sending…
              </span>
            ) : (
              <span
                className={cn('inline-flex items-center', readByOthers && 'text-accent')}
                title={readByOthers ? 'Read' : 'Sent'}
                aria-label={readByOthers ? 'Read' : 'Sent'}
              >
                <Icon name="check" size="xs" />
                {readByOthers ? <Icon name="check" size="xs" className="-ml-1.5" /> : null}
              </span>
            )
          ) : null}
        </span>

        {Object.keys(reactionGroups).length > 0 ? (
          <span className="mt-1 flex flex-wrap gap-1">
            {Object.entries(reactionGroups).map(([emoji, users]) => (
              <button
                key={emoji}
                type="button"
                onClick={() => onReact(emoji)}
                aria-pressed={users.includes(viewerId)}
                aria-label={`${emoji} ${users.length}`}
                className={cn(
                  'k-pressable focus-ring inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-micro',
                  users.includes(viewerId)
                    ? 'border-accent bg-accent-subtle text-ink'
                    : 'border-line bg-surface-2 text-ink-2',
                )}
              >
                <span aria-hidden>{emoji}</span>
                <span className="tabular">{users.length}</span>
              </button>
            ))}
          </span>
        ) : null}
      </div>

      <span
        className={cn(
          'relative flex shrink-0 items-center gap-0.5 self-center',
          'transition-opacity dur-fast ease-standard',
          touchRevealed
            ? 'opacity-100'
            : cn(
                'pointer-events-none opacity-0',
                'group-hover/message:pointer-events-auto group-hover/message:opacity-100',
                'group-focus-within/message:pointer-events-auto group-focus-within/message:opacity-100',
              ),
        )}
      >
        <IconButton
          icon="comment"
          label="Reply"
          size="sm"
          variant="ghost"
          onClick={onReply}
        />
        <IconButton
          icon="heart"
          label="React"
          size="sm"
          variant="ghost"
          onClick={() => setPickerOpen((current) => !current)}
        />
        {mine && message.body ? (
          <IconButton icon="pencil" label="Edit message" size="sm" variant="ghost" onClick={onEdit} />
        ) : null}
        {mine ? (
          <IconButton icon="trash" label="Delete message" size="sm" variant="ghost" onClick={onDelete} />
        ) : null}
        {!mine ? (
          <IconButton icon="flag" label="Report message" size="sm" variant="ghost" onClick={onReport} />
        ) : null}

        {pickerOpen ? (
          <span className="glass absolute bottom-10 right-0 z-raised flex gap-1 rounded-full border border-line p-1 shadow-mid">
            {REACTION_CHOICES.map((emoji) => (
              <button
                key={emoji}
                type="button"
                aria-label={`React ${emoji}`}
                onClick={() => {
                  onReact(emoji);
                  setPickerOpen(false);
                }}
                className="k-pressable focus-ring grid size-8 place-items-center rounded-full text-body hover:bg-surface-3"
              >
                <span aria-hidden>{emoji}</span>
              </button>
            ))}
          </span>
        ) : null}
      </span>
    </div>
  );
}

/** Inline editor a bubble swaps to. Enter saves, Shift+Enter breaks, Esc bails. */
function MessageEditBox({
  initial,
  onCancel,
  onSave,
}: {
  initial: string;
  onCancel: () => void;
  onSave: (body: string) => void;
}) {
  const [draft, setDraft] = useState(initial);
  const canSave = draft.trim().length > 0;

  return (
    <span className="flex w-full min-w-56 flex-col gap-2">
      <textarea
        value={draft}
        rows={2}
        autoFocus
        aria-label="Edit message"
        onChange={(event) => setDraft(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            if (canSave) onSave(draft);
          } else if (event.key === 'Escape') {
            event.stopPropagation();
            onCancel();
          }
        }}
        className={cn(
          'focus-ring w-full resize-none rounded-2xl border border-line bg-surface-2',
          'px-3.5 py-2 text-body text-ink',
          'transition-colors dur-fast ease-standard focus:border-line-strong',
        )}
      />
      <span className="flex items-center justify-end gap-2">
        <Button variant="ghost" size="sm" onClick={onCancel}>
          Cancel
        </Button>
        <Button size="sm" disabled={!canSave} onClick={() => onSave(draft)}>
          Save
        </Button>
      </span>
    </span>
  );
}
