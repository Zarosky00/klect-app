'use client';

import { useCallback, useRef, useState } from 'react';
import { cn } from '@/lib/cn';
import { Icon } from '@/components/ui/Icon';
import { IconButton } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ProgressBar } from './ProfileEditor';
import { ACCEPT_ATTRIBUTE, releasePreview, type PreparedImage } from './media';

/**
 * Drag-and-drop multi-file upload with real per-file progress.
 *
 * The order of this list is the `position` written to `item_media`, and a
 * trigger copies position 0 onto the item's `cover_*` — so "the cover derives
 * from the first photo, and can be overridden" is just: move a photo to the
 * front. Reordering is available by drag *and* by button, because a drag-only
 * affordance is unreachable from a keyboard.
 */

export type StagedStatus = 'preparing' | 'uploading' | 'done' | 'failed';

export interface StagedPhoto {
  id: string;
  prepared: PreparedImage | null;
  /** Bucket key, known before the upload starts. */
  path: string;
  progress: number;
  status: StagedStatus;
  error: string | null;
  altText: string;
}

export interface UploadDropzoneProps {
  photos: StagedPhoto[];
  onAdd: (files: FileList | File[]) => void;
  onRemove: (id: string) => void;
  onMove: (id: string, direction: -1 | 1) => void;
  onAltText: (id: string, value: string) => void;
  onRetry: (id: string) => void;
  max?: number;
  disabled?: boolean;
}

export function UploadDropzone({
  photos,
  onAdd,
  onRemove,
  onMove,
  onAltText,
  onRetry,
  max = 12,
  disabled = false,
}: UploadDropzoneProps) {
  const [dragging, setDragging] = useState(false);
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const input = useRef<HTMLInputElement | null>(null);

  const drop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();
      setDragging(false);
      if (disabled) return;
      const files = [...event.dataTransfer.files].filter((file) =>
        file.type.startsWith('image/'),
      );
      if (files.length > 0) onAdd(files);
    },
    [disabled, onAdd],
  );

  const full = photos.length >= max;

  return (
    <div className="flex flex-col gap-4">
      <div
        onDragOver={(event) => {
          event.preventDefault();
          if (!disabled) setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={drop}
        className={cn(
          'rounded-xl border-2 border-dashed p-8 text-center',
          'transition-colors dur-fast ease-standard',
          dragging ? 'border-accent bg-accent-subtle' : 'border-line bg-surface-1',
          disabled && 'pointer-events-none opacity-[var(--k-opacity-disabled)]',
        )}
      >
        <span className="mx-auto grid size-12 place-items-center rounded-full bg-surface-2 text-ink-3">
          <Icon name="image" size="xl" />
        </span>
        <p className="mt-3 font-display text-title2 text-ink">Drop photos here</p>
        <p className="mt-1 text-caption text-ink-2">
          Downscaled, re-encoded to WebP and hashed on your device before anything is
          uploaded. Up to {max} photos.
        </p>
        <button
          type="button"
          onClick={() => input.current?.click()}
          disabled={full}
          className={cn(
            'k-pressable focus-ring mt-4 inline-flex items-center gap-2 rounded-md px-4 py-2.5',
            'bg-accent text-body-strong text-ink-on-accent transition-colors dur-fast hover:bg-accent-hover',
            'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
          )}
        >
          <Icon name="plus" size="md" />
          {full ? `Limit is ${max}` : 'Choose photos'}
        </button>
        <input
          ref={input}
          type="file"
          accept={ACCEPT_ATTRIBUTE}
          multiple
          className="sr-only"
          onChange={(event) => {
            if (event.target.files) onAdd(event.target.files);
            event.target.value = '';
          }}
        />
      </div>

      {photos.length > 0 ? (
        <ul className="grid gap-3 sm:grid-cols-2">
          {photos.map((photo, index) => (
            <li
              key={photo.id}
              draggable={!disabled}
              onDragStart={() => setDragIndex(index)}
              onDragOver={(event) => event.preventDefault()}
              onDrop={(event) => {
                event.preventDefault();
                event.stopPropagation();
                if (dragIndex === null || dragIndex === index) return;
                // One step at a time keeps `onMove` a single, testable primitive.
                const direction = dragIndex < index ? 1 : -1;
                const source = photos[dragIndex];
                if (source) {
                  for (let step = 0; step < Math.abs(index - dragIndex); step += 1) {
                    onMove(source.id, direction);
                  }
                }
                setDragIndex(null);
              }}
              className={cn(
                'flex gap-3 rounded-lg border p-3',
                index === 0 ? 'border-accent bg-accent-subtle' : 'border-line bg-surface-1',
              )}
            >
              <span className="relative size-24 shrink-0 overflow-hidden rounded-md border border-line-subtle">
                {photo.prepared ? (
                  /* eslint-disable-next-line @next/next/no-img-element -- local
                     object URL for a Blob prepared in this tab. */
                  <img
                    src={photo.prepared.previewUrl}
                    alt=""
                    className="size-full object-cover"
                  />
                ) : (
                  <span className="grid size-full place-items-center bg-skeleton text-ink-3">
                    <Icon name="spinner" size="md" />
                  </span>
                )}
                {index === 0 ? (
                  <span className="absolute inset-x-0 bottom-0 bg-scrim py-0.5 text-center text-micro text-ink">
                    Cover
                  </span>
                ) : null}
              </span>

              <div className="flex min-w-0 flex-1 flex-col gap-2">
                <div className="flex items-center gap-1">
                  <span className="min-w-0 flex-1 truncate text-caption text-ink-2">
                    {photo.prepared
                      ? `${photo.prepared.width}×${photo.prepared.height} · ${Math.round(photo.prepared.bytes / 1024)} KB`
                      : 'Preparing…'}
                  </span>
                  <IconButton
                    icon="chevron-left"
                    label="Move earlier"
                    size="sm"
                    disabled={index === 0 || disabled}
                    onClick={() => onMove(photo.id, -1)}
                  />
                  <IconButton
                    icon="chevron-right"
                    label="Move later"
                    size="sm"
                    disabled={index === photos.length - 1 || disabled}
                    onClick={() => onMove(photo.id, 1)}
                  />
                  <IconButton
                    icon="trash"
                    label="Remove photo"
                    size="sm"
                    disabled={disabled}
                    onClick={() => onRemove(photo.id)}
                  />
                </div>

                <TextField
                  label="Alt text"
                  labelHidden
                  value={photo.altText}
                  placeholder="Describe this photo"
                  onChange={(event) => onAltText(photo.id, event.target.value)}
                  maxLength={160}
                  fieldClassName="h-9 text-caption"
                />

                {photo.status === 'failed' ? (
                  <button
                    type="button"
                    onClick={() => onRetry(photo.id)}
                    className="focus-ring inline-flex items-center gap-1 self-start rounded-sm text-caption text-danger underline underline-offset-2"
                  >
                    <Icon name="alert" size="xs" />
                    {photo.error ?? 'Upload failed'} — retry
                  </button>
                ) : photo.status === 'done' ? (
                  <span className="inline-flex items-center gap-1 text-caption text-success">
                    <Icon name="check" size="xs" />
                    Uploaded
                  </span>
                ) : (
                  <ProgressBar
                    value={photo.progress}
                    label={`Uploading photo ${index + 1}`}
                  />
                )}
              </div>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

/** Frees every object URL a staged list is holding. */
export function releaseStaged(photos: readonly StagedPhoto[]): void {
  for (const photo of photos) {
    if (photo.prepared) releasePreview(photo.prepared);
  }
}
