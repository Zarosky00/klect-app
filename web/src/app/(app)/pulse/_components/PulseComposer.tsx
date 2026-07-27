'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Avatar } from '@/components/ui/Avatar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Button, IconButton } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { TextArea } from '@/components/ui/TextField';
import type { EntitySummary } from '@/components/social/queries';
import {
  ACCEPT_ATTRIBUTE,
  assertWithinBucketLimit,
  prepareImage,
  releasePreview,
  uploadObject,
  type PreparedImage,
} from '@/components/social/media';
import { createPost, type PostMediaDescriptor } from '@/lib/api';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, type EntityType } from '@/lib/entities';
import { mediaUrl } from '@/lib/storage';
import type { PulseEntry } from '@/lib/types';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { EntityPickerSheet } from './EntityPickerSheet';

/**
 * The Pulse composer.
 *
 * Posts go through `create_post` — migration 0018 revoked direct INSERT on
 * `posts`, and the RPC is the only path that can also write `post_media` rows
 * and validate the attached target. It returns the post's full pulse envelope,
 * which is handed to the stream verbatim so the new post appears (media, quoted
 * card and all) without a refetch. On failure the draft is kept, never cleared.
 *
 * Photos ride the same client pipeline as item media: downscale → WebP →
 * blurhash on-device, then upload to the `media` bucket under
 * `{uid}/posts/{draftId}/{uuid}.webp` (the 0018 storage convention) while the
 * words are still being typed.
 */

export const MAX_POST_LENGTH = 500;
export const MAX_POST_PHOTOS = 4;

/** What the composer is aimed at: a quoted post, or a shared entity. */
export interface ComposerSubject {
  type: EntityType;
  id: string;
  title: string | null;
  subtitle: string | null;
  body?: string | null;
  authorUsername?: string | null;
  coverPath: string | null;
  coverBlurhash: string | null;
}

export function subjectFromEntitySummary(entity: EntitySummary): ComposerSubject {
  return {
    type: entity.type,
    id: entity.id,
    title: entity.title,
    subtitle: entity.subtitle,
    coverPath: entity.coverPath,
    coverBlurhash: entity.coverBlurhash,
  };
}

interface ComposerPhoto {
  id: string;
  /** Bucket key, fixed before the upload starts. */
  path: string;
  prepared: PreparedImage | null;
  progress: number;
  status: 'preparing' | 'uploading' | 'done' | 'failed';
  error: string | null;
}

export interface PulseComposerProps {
  /** Receives the full envelope `create_post` returned — prepend it verbatim. */
  onPosted: (entry: PulseEntry) => void;
  /** Quote mode: set from the repost chooser. The composer shows the subject. */
  quote?: ComposerSubject | null;
  onClearQuote?: () => void;
  className?: string;
}

export function PulseComposer({ onPosted, quote = null, onClearQuote, className }: PulseComposerProps) {
  const { supabase, user, profile } = useSession();
  const { fromError, success } = useToast();

  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [photos, setPhotos] = useState<ComposerPhoto[]>([]);
  const [attachment, setAttachment] = useState<ComposerSubject | null>(null);
  const [picking, setPicking] = useState(false);
  /** Post id namespace for uploads; a fresh one per composed post. */
  const [draftId, setDraftId] = useState(() => crypto.randomUUID());

  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const fileInput = useRef<HTMLInputElement | null>(null);

  // Quote mode occupies the one target slot; entity share yields to it.
  const subject = quote ?? attachment;

  useEffect(() => {
    if (quote) textareaRef.current?.focus();
  }, [quote]);

  const uploadOne = useCallback(
    async (photo: ComposerPhoto) => {
      if (!photo.prepared) return;
      const {
        data: { session },
      } = await supabase.auth.getSession();
      const accessToken = session?.access_token;
      if (!accessToken) throw new Error('Your session expired. Sign in again.');

      setPhotos((current) =>
        current.map((entry) =>
          entry.id === photo.id
            ? { ...entry, status: 'uploading', progress: 0, error: null }
            : entry,
        ),
      );

      try {
        await uploadObject({
          accessToken,
          bucket: 'media',
          path: photo.path,
          body: photo.prepared.blob,
          contentType: photo.prepared.mimeType,
          upsert: true,
          onProgress: (fraction) =>
            setPhotos((current) =>
              current.map((entry) =>
                entry.id === photo.id ? { ...entry, progress: fraction } : entry,
              ),
            ),
        });
        setPhotos((current) =>
          current.map((entry) =>
            entry.id === photo.id
              ? { ...entry, status: 'done', progress: 1, error: null }
              : entry,
          ),
        );
      } catch (thrown) {
        setPhotos((current) =>
          current.map((entry) =>
            entry.id === photo.id
              ? {
                  ...entry,
                  status: 'failed',
                  error: thrown instanceof Error ? thrown.message : 'Upload failed',
                }
              : entry,
          ),
        );
      }
    },
    [supabase],
  );

  const addFiles = useCallback(
    async (files: FileList | File[]) => {
      if (!user) return;
      const room = MAX_POST_PHOTOS - photos.length;
      const list = [...files].slice(0, Math.max(0, room));
      for (const file of list) {
        const id = crypto.randomUUID();
        const path = `${user.id}/posts/${draftId}/${crypto.randomUUID()}.webp`;

        setPhotos((current) =>
          current.length >= MAX_POST_PHOTOS
            ? current
            : [
                ...current,
                { id, path, prepared: null, progress: 0, status: 'preparing', error: null },
              ],
        );

        try {
          assertWithinBucketLimit('media', file.size);
          const prepared = await prepareImage(file);
          const staged: ComposerPhoto = {
            id,
            path,
            prepared,
            progress: 0,
            status: 'uploading',
            error: null,
          };
          setPhotos((current) => current.map((entry) => (entry.id === id ? staged : entry)));
          await uploadOne(staged);
        } catch (thrown) {
          setPhotos((current) => current.filter((entry) => entry.id !== id));
          fromError(thrown);
        }
      }
    },
    [draftId, fromError, photos.length, uploadOne, user],
  );

  const removePhoto = useCallback((id: string) => {
    setPhotos((current) => {
      const target = current.find((entry) => entry.id === id);
      if (target?.prepared) releasePreview(target.prepared);
      return current.filter((entry) => entry.id !== id);
    });
  }, []);

  const trimmed = body.trim();
  const photosSettled = photos.every((photo) => photo.status === 'done');
  const hasContent = trimmed.length > 0 || subject !== null || photos.length > 0;
  const canPost = !busy && hasContent && photosSettled;

  const submit = useCallback(async () => {
    if (!user || busy) return;
    const text = body.trim();
    const target = quote ?? attachment;
    const ready = photos.filter((photo) => photo.status === 'done');
    if (!text && !target && ready.length === 0) return;
    if (!photos.every((photo) => photo.status === 'done')) return;

    const media: PostMediaDescriptor[] = ready.map((photo, index) => ({
      storage_path: photo.path,
      width: photo.prepared?.width ?? null,
      height: photo.prepared?.height ?? null,
      blurhash: photo.prepared?.blurhash ?? null,
      dominant_color: photo.prepared?.dominantColor ?? null,
      mime_type: photo.prepared?.mimeType ?? null,
      bytes: photo.prepared?.bytes ?? null,
      position: index,
    }));

    setBusy(true);
    try {
      const envelope = await createPost(supabase, {
        body: text,
        ...(target === null ? {} : { entityType: target.type, entityId: target.id }),
        ...(media.length === 0 ? {} : { media }),
      });

      // Clean slate for the next post; previews are freed, draft id rotates.
      for (const photo of photos) {
        if (photo.prepared) releasePreview(photo.prepared);
      }
      setBody('');
      setPhotos([]);
      setAttachment(null);
      setDraftId(crypto.randomUUID());
      if (quote) onClearQuote?.();
      success('Posted');
      onPosted(envelope);
    } catch (error) {
      // The words stay in the box. Losing a draft to a network blip is the one
      // thing a composer must never do.
      fromError(error, { retry: () => void submit() });
    } finally {
      setBusy(false);
    }
  }, [attachment, body, busy, fromError, onClearQuote, onPosted, photos, quote, success, supabase, user]);

  if (!user) return null;

  return (
    <form
      className={cn('flex gap-3 border-b border-line-subtle px-4 py-4 sm:px-6', className)}
      onSubmit={(event) => {
        event.preventDefault();
        void submit();
      }}
    >
      <Avatar
        path={profile?.avatar_path}
        name={profile?.display_name}
        username={profile?.username}
        size="md"
        verified={profile?.is_verified ?? false}
      />

      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <TextArea
          ref={textareaRef}
          label="What are you collecting?"
          labelHidden
          rows={2}
          value={body}
          maxLength={MAX_POST_LENGTH}
          showCount
          placeholder={
            subject && subject.type === 'post'
              ? 'Add your words to this…'
              : 'What did you just add to the shelf?'
          }
          onChange={(event) => setBody(event.target.value)}
          onKeyDown={(event) => {
            if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
              event.preventDefault();
              void submit();
            }
          }}
        />

        {photos.length > 0 ? (
          <ul className="flex flex-wrap gap-2" aria-label="Attached photos">
            {photos.map((photo) => (
              <li
                key={photo.id}
                className="relative size-20 overflow-hidden rounded-md border border-line-subtle bg-surface-2"
              >
                {photo.prepared ? (
                  /* eslint-disable-next-line @next/next/no-img-element -- local
                     object URL for a Blob prepared in this tab. */
                  <img
                    src={photo.prepared.previewUrl}
                    alt=""
                    className={cn(
                      'size-full object-cover transition-opacity dur-fast ease-standard',
                      photo.status === 'done'
                        ? 'opacity-100'
                        : 'opacity-[var(--k-opacity-disabled)]',
                    )}
                  />
                ) : (
                  <span className="grid size-full place-items-center text-ink-3">
                    <Icon name="spinner" size="md" className="k-spin" />
                  </span>
                )}

                {photo.status === 'uploading' ? (
                  <span
                    aria-hidden
                    className="absolute inset-x-0 bottom-0 h-1 bg-surface-2"
                  >
                    <span
                      className="block h-full bg-accent transition-[width] dur-fast ease-standard"
                      style={{ width: `${Math.round(photo.progress * 100)}%` }}
                    />
                  </span>
                ) : null}

                {photo.status === 'failed' ? (
                  <button
                    type="button"
                    onClick={() => {
                      void uploadOne(photo);
                    }}
                    className="focus-ring absolute inset-0 grid place-items-center bg-scrim text-micro text-ink"
                  >
                    <span className="inline-flex items-center gap-1">
                      <Icon name="alert" size="xs" />
                      Retry
                    </span>
                  </button>
                ) : null}

                <button
                  type="button"
                  aria-label="Remove photo"
                  title="Remove photo"
                  onClick={() => removePhoto(photo.id)}
                  className={cn(
                    'k-pressable focus-ring absolute right-1 top-1 grid size-6 place-items-center',
                    'rounded-full bg-scrim text-ink transition-colors dur-fast ease-standard',
                    'hover:bg-surface-3',
                  )}
                >
                  <Icon name="close" size="xs" />
                </button>
              </li>
            ))}
          </ul>
        ) : null}

        {subject ? (
          <ComposerSubjectCard
            subject={subject}
            onRemove={quote ? (onClearQuote ?? (() => {})) : () => setAttachment(null)}
          />
        ) : null}

        <div className="flex flex-wrap items-center gap-1">
          <Button
            iconLeft="image"
            size="sm"
            variant="ghost"
            disabled={photos.length >= MAX_POST_PHOTOS || busy}
            onClick={() => fileInput.current?.click()}
          >
            {photos.length >= MAX_POST_PHOTOS ? `${MAX_POST_PHOTOS} photos` : 'Add photo'}
          </Button>
          <Button
            iconLeft="grid"
            size="sm"
            variant="ghost"
            disabled={quote !== null || busy}
            onClick={() => setPicking(true)}
          >
            {attachment ? 'Change item' : 'Add collection'}
          </Button>
          <input
            ref={fileInput}
            type="file"
            accept={ACCEPT_ATTRIBUTE}
            multiple
            className="sr-only"
            onChange={(event) => {
              if (event.target.files) void addFiles(event.target.files);
              event.target.value = '';
            }}
          />

          <span className="flex-1" />
          <span className="hidden text-caption text-ink-3 sm:inline">⌘/Ctrl + Enter</span>
          <Button type="submit" size="sm" loading={busy} disabled={!canPost}>
            {quote ? 'Quote' : 'Post'}
          </Button>
        </div>
      </div>

      <EntityPickerSheet
        open={picking}
        onClose={() => setPicking(false)}
        onPick={(entity) => {
          setAttachment(subjectFromEntitySummary(entity));
          setPicking(false);
        }}
      />
    </form>
  );
}

/** The card under the textarea: what this post will quote or share. */
function ComposerSubjectCard({
  subject,
  onRemove,
}: {
  subject: ComposerSubject;
  onRemove: () => void;
}) {
  const isQuote = subject.type === 'post';
  return (
    <div className="flex items-center gap-3 rounded-lg border border-line bg-surface-1 p-2">
      {subject.coverPath ? (
        <span className="w-14 shrink-0 overflow-hidden rounded-md border border-line-subtle">
          <BlurhashImage
            src={mediaUrl(subject.coverPath)}
            alt=""
            width={null}
            height={null}
            blurhash={subject.coverBlurhash}
            fallbackAspect={1}
            sizes="56px"
          />
        </span>
      ) : null}

      <div className="min-w-0 flex-1">
        <p className="text-micro uppercase tracking-widest text-ink-3">
          {isQuote
            ? `Quoting ${subject.authorUsername ? `@${subject.authorUsername}` : 'a post'}`
            : ENTITY_LABEL[subject.type]}
        </p>
        <p className="truncate text-callout text-ink">
          {subject.body ?? subject.title ?? 'Post'}
        </p>
        {subject.subtitle ? (
          <p className="truncate text-caption text-ink-3">{subject.subtitle}</p>
        ) : null}
      </div>

      <IconButton
        icon="close"
        label={isQuote ? 'Remove quote' : 'Remove attachment'}
        size="sm"
        variant="ghost"
        onClick={onRemove}
      />
    </div>
  );
}
