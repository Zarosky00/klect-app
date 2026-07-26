'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { cn } from '@/lib/cn';
import type { MessageRow } from '@/lib/types';
import { Icon } from '@/components/ui/Icon';
import { IconButton } from '@/components/ui/Button';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { EntitySharePicker } from './EntitySharePicker';
import { ProgressBar } from './ProfileEditor';
import { SharedEntityCard } from './SharedEntityCard';
import type { EntitySummary } from './queries';
import {
  ACCEPT_ATTRIBUTE,
  assertWithinBucketLimit,
  mediaObjectKey,
  prepareImage,
  releasePreview,
  uploadObject,
} from './media';

/**
 * The composer. Text, photos, a shared collection or item, and replies.
 *
 * Photos upload the moment they are picked, so pressing send is a single row
 * insert and never a multi-second wait. If the send itself fails the draft is
 * left exactly as typed — losing text is the one unforgivable chat bug.
 */

export interface ComposerAttachment {
  id: string;
  /** Bucket-relative key inside `chat`. Empty until the upload finishes. */
  path: string;
  width: number;
  height: number;
  blurhash: string;
  mime: string;
  bytes: number;
  previewUrl: string;
  progress: number;
  uploading: boolean;
}

/** A typing broadcast at most this often — one per keystroke would be silly. */
const TYPING_THROTTLE_MS = 1500;
const MAX_ATTACHMENTS = 4;

export interface MessageComposerProps {
  conversationId: string;
  viewerId: string;
  sending: boolean;
  replyTo: MessageRow | null;
  replyAuthorName: string | null;
  onCancelReply: () => void;
  onTyping: () => void;
  onSend: (input: {
    body: string;
    attachments: ComposerAttachment[];
    sharedEntity: EntitySummary | null;
  }) => Promise<void>;
}

export function MessageComposer({
  conversationId,
  viewerId,
  sending,
  replyTo,
  replyAuthorName,
  onCancelReply,
  onTyping,
  onSend,
}: MessageComposerProps) {
  const { supabase } = useSession();
  const { fromError } = useToast();

  const [body, setBody] = useState('');
  const [attachments, setAttachments] = useState<ComposerAttachment[]>([]);
  const [sharedEntity, setSharedEntity] = useState<EntitySummary | null>(null);
  const [picking, setPicking] = useState(false);

  const fileInput = useRef<HTMLInputElement | null>(null);
  const textarea = useRef<HTMLTextAreaElement | null>(null);
  const lastTypingAt = useRef(0);

  // Auto-grow, capped so the composer never eats the thread.
  useEffect(() => {
    const node = textarea.current;
    if (!node) return;
    node.style.height = 'auto';
    node.style.height = `${Math.min(node.scrollHeight, 160)}px`;
  }, [body]);

  useEffect(() => {
    if (replyTo) textarea.current?.focus();
  }, [replyTo]);

  const attach = useCallback(
    async (files: FileList | null) => {
      if (!files || files.length === 0) return;
      const room = MAX_ATTACHMENTS - attachments.length;
      if (room <= 0) {
        fromError(new Error(`Up to ${MAX_ATTACHMENTS} photos per message.`));
        return;
      }

      const {
        data: { session },
      } = await supabase.auth.getSession();
      const accessToken = session?.access_token;
      if (!accessToken) {
        fromError(new Error('Your session expired. Sign in again.'));
        return;
      }

      for (const file of [...files].slice(0, room)) {
        const id = crypto.randomUUID();
        try {
          assertWithinBucketLimit('chat', file.size);
          const prepared = await prepareImage(file);
          const path = mediaObjectKey(viewerId, conversationId);

          setAttachments((current) => [
            ...current,
            {
              id,
              path,
              width: prepared.width,
              height: prepared.height,
              blurhash: prepared.blurhash,
              mime: prepared.mimeType,
              bytes: prepared.bytes,
              previewUrl: prepared.previewUrl,
              progress: 0,
              uploading: true,
            },
          ]);

          await uploadObject({
            accessToken,
            bucket: 'chat',
            path,
            body: prepared.blob,
            contentType: prepared.mimeType,
            onProgress: (fraction) =>
              setAttachments((current) =>
                current.map((entry) =>
                  entry.id === id
                    ? { ...entry, progress: fraction, uploading: fraction < 1 }
                    : entry,
                ),
              ),
          });

          setAttachments((current) =>
            current.map((entry) =>
              entry.id === id ? { ...entry, progress: 1, uploading: false } : entry,
            ),
          );
        } catch (error) {
          setAttachments((current) => current.filter((entry) => entry.id !== id));
          fromError(error);
        }
      }
    },
    [attachments.length, conversationId, fromError, supabase, viewerId],
  );

  const removeAttachment = useCallback((id: string) => {
    setAttachments((current) => {
      const target = current.find((entry) => entry.id === id);
      if (target) releasePreview(target);
      return current.filter((entry) => entry.id !== id);
    });
  }, []);

  const uploading = attachments.some((entry) => entry.uploading);
  const canSend =
    !sending && !uploading && (body.trim().length > 0 || attachments.length > 0 || sharedEntity !== null);

  const submit = useCallback(async () => {
    if (!canSend) return;
    const snapshot = { body, attachments, sharedEntity };
    try {
      await onSend(snapshot);
      // Only clear once the row exists — a failed send keeps the draft.
      for (const entry of attachments) releasePreview(entry);
      setBody('');
      setAttachments([]);
      setSharedEntity(null);
    } catch {
      // `onSend` already surfaced the error; the draft stays put.
    }
  }, [attachments, body, canSend, onSend, sharedEntity]);

  const onChange = (value: string) => {
    setBody(value);
    const now = Date.now();
    if (now - lastTypingAt.current > TYPING_THROTTLE_MS) {
      lastTypingAt.current = now;
      onTyping();
    }
  };

  return (
    <div className="shrink-0 border-t border-line-subtle bg-base px-3 pb-3 pt-2">
      {replyTo ? (
        <div className="mb-2 flex items-center gap-2 rounded-md border-l-2 border-accent bg-surface-2 px-3 py-2">
          <span className="min-w-0 flex-1 truncate text-caption text-ink-2">
            Replying to <strong className="text-ink">{replyAuthorName ?? 'them'}</strong>:{' '}
            {replyTo.body ?? 'a photo'}
          </span>
          <IconButton icon="close" label="Cancel reply" size="sm" onClick={onCancelReply} />
        </div>
      ) : null}

      {sharedEntity ? (
        <div className="mb-2 flex items-start gap-2">
          <SharedEntityCard summary={sharedEntity} />
          <IconButton
            icon="close"
            label="Remove shared card"
            size="sm"
            onClick={() => setSharedEntity(null)}
          />
        </div>
      ) : null}

      {attachments.length > 0 ? (
        <ul className="mb-2 flex flex-wrap gap-2">
          {attachments.map((entry) => (
            <li key={entry.id} className="relative">
              <span className="block size-20 overflow-hidden rounded-md border border-line">
                {/* eslint-disable-next-line @next/next/no-img-element -- local
                    object URL for a Blob the user just picked. */}
                <img src={entry.previewUrl} alt="" className="size-full object-cover" />
              </span>
              {entry.uploading ? (
                <span className="absolute inset-x-1 bottom-1">
                  <ProgressBar value={entry.progress} label="Photo upload" />
                </span>
              ) : null}
              <button
                type="button"
                aria-label="Remove photo"
                onClick={() => removeAttachment(entry.id)}
                className="focus-ring absolute -right-1.5 -top-1.5 grid size-6 place-items-center rounded-full border border-line bg-surface-2 text-ink-2 hover:text-ink"
              >
                <Icon name="close" size="xs" />
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      <div className="flex items-end gap-2">
        <IconButton
          icon="image"
          label="Attach a photo"
          size="sm"
          onClick={() => fileInput.current?.click()}
          disabled={attachments.length >= MAX_ATTACHMENTS}
        />
        <IconButton
          icon="grid"
          label="Share a collection or item"
          size="sm"
          onClick={() => setPicking(true)}
        />

        <label className="min-w-0 flex-1">
          <span className="sr-only">Message</span>
          <textarea
            ref={textarea}
            value={body}
            rows={1}
            onChange={(event) => onChange(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                void submit();
              }
            }}
            placeholder="Write a message…"
            className={cn(
              'focus-ring max-h-40 w-full resize-none rounded-2xl border border-line bg-surface-2',
              'px-4 py-2.5 text-body text-ink placeholder:text-ink-3',
              'transition-colors dur-fast ease-standard focus:border-line-strong',
            )}
          />
        </label>

        <button
          type="button"
          onClick={() => void submit()}
          disabled={!canSend}
          aria-label="Send message"
          title="Send (Enter)"
          className={cn(
            'k-pressable focus-ring grid size-11 shrink-0 place-items-center rounded-full',
            'transition-colors dur-fast ease-standard',
            canSend
              ? 'bg-accent text-ink-on-accent hover:bg-accent-hover'
              : 'bg-surface-3 text-ink-disabled',
          )}
        >
          <Icon name={sending || uploading ? 'spinner' : 'send'} size="lg" />
        </button>
      </div>

      <input
        ref={fileInput}
        type="file"
        accept={ACCEPT_ATTRIBUTE}
        multiple
        className="sr-only"
        onChange={(event) => {
          void attach(event.target.files);
          event.target.value = '';
        }}
      />

      <EntitySharePicker
        open={picking}
        onClose={() => setPicking(false)}
        onPick={setSharedEntity}
      />
    </div>
  );
}
