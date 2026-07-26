'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Icon } from '@/components/ui/Icon';
import { cn } from '@/lib/cn';
import { ACCEPT_ATTRIBUTE } from '../media';

/**
 * PICK — the full-bleed photo grid that opens the create flow; the web twin of
 * mobile's `pick/pick_grid.dart` with the web's own ways in: drag-and-drop
 * anywhere on the grid, the file picker, and paste from the clipboard.
 *
 * Each picked tile wears its selection order as a badge, and clicking a tile
 * removes it — the standard picker gesture on both clients.
 */
export interface PickPhotoTile {
  id: string;
  /** Object URL of the original file. */
  url: string;
  /** True while the photo is still decoding — the tile shimmers. */
  pending: boolean;
  /** True when the photo could not be decoded. */
  failed: boolean;
}

export interface PickGridProps {
  photos: readonly PickPhotoTile[];
  onAdd: (files: File[]) => void;
  onRemove: (id: string) => void;
  max: number;
  disabled?: boolean;
}

function imageFiles(list: FileList | File[] | null | undefined): File[] {
  return [...(list ?? [])].filter((file) => file.type.startsWith('image/'));
}

export function PickGrid({ photos, onAdd, onRemove, max, disabled = false }: PickGridProps) {
  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const full = photos.length >= max;

  /* Paste lands photos too — scoped to this beat because the grid only
     mounts while PICK is on screen. */
  useEffect(() => {
    if (disabled) return;
    const onPaste = (event: ClipboardEvent) => {
      const files = imageFiles(event.clipboardData?.files);
      if (files.length > 0) {
        event.preventDefault();
        onAdd(files);
      }
    };
    window.addEventListener('paste', onPaste);
    return () => window.removeEventListener('paste', onPaste);
  }, [disabled, onAdd]);

  const drop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();
      setDragging(false);
      if (disabled) return;
      const files = imageFiles(event.dataTransfer.files);
      if (files.length > 0) onAdd(files);
    },
    [disabled, onAdd],
  );

  return (
    <div
      onDragOver={(event) => {
        event.preventDefault();
        if (!disabled) setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={drop}
      className={cn(
        'rounded-xl border-2 border-dashed p-1 transition-colors dur-fast ease-standard',
        dragging ? 'border-accent bg-accent-subtle' : 'border-line bg-surface-1',
        disabled && 'pointer-events-none opacity-[var(--k-opacity-disabled)]',
      )}
    >
      <div className="grid grid-cols-3 gap-0.5 sm:grid-cols-4 lg:grid-cols-6">
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          disabled={disabled || full}
          className={cn(
            'k-pressable focus-ring flex aspect-square flex-col items-center justify-center gap-2',
            'rounded-md bg-accent-subtle text-accent transition-colors dur-fast hover:bg-surface-2',
            'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
          )}
        >
          <Icon name="plus" size="xl" />
          <span className="text-label">{full ? `Limit is ${max}` : 'Add photos'}</span>
        </button>

        {photos.map((photo, index) => (
          <button
            key={photo.id}
            type="button"
            onClick={() => onRemove(photo.id)}
            disabled={disabled}
            aria-label={`Remove photo ${index + 1}`}
            className="group focus-ring relative aspect-square overflow-hidden rounded-md bg-skeleton"
          >
            {photo.pending ? (
              <span className="grid size-full place-items-center text-ink-3">
                <Icon name="spinner" size="md" />
              </span>
            ) : (
              /* eslint-disable-next-line @next/next/no-img-element -- local
                 object URL for a file staged in this tab. */
              <img src={photo.url} alt="" className="size-full object-cover" />
            )}
            {photo.failed ? (
              <span className="absolute inset-0 grid place-items-center bg-scrim text-danger">
                <Icon name="alert" size="md" />
              </span>
            ) : null}
            <span
              aria-hidden
              className={cn(
                'absolute inset-0 grid place-items-center bg-scrim text-ink',
                'opacity-0 transition-opacity dur-fast group-hover:opacity-100 group-focus-visible:opacity-100',
              )}
            >
              <Icon name="trash" size="md" />
            </span>
            <span
              aria-hidden
              className={cn(
                'absolute right-1 top-1 grid size-6 place-items-center rounded-full',
                'border border-ink-on-accent bg-accent text-micro text-ink-on-accent',
              )}
            >
              {index + 1}
            </span>
          </button>
        ))}
      </div>

      <p className="px-3 py-3 text-center text-caption text-ink-3">
        Drag photos here, paste from the clipboard, or add up to {max}. Tap a photo to
        remove it. Filing comes last.
      </p>

      <input
        ref={inputRef}
        type="file"
        accept={ACCEPT_ATTRIBUTE}
        multiple
        className="sr-only"
        onChange={(event) => {
          const files = imageFiles(event.target.files);
          if (files.length > 0) onAdd(files);
          event.target.value = '';
        }}
      />
    </div>
  );
}
