'use client';

import { useState } from 'react';
import { IconButton } from '@/components/ui/Button';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { Icon } from '@/components/ui/Icon';
import { cn } from '@/lib/cn';
import {
  CROP_PRESETS,
  clampGridAspect,
  cropAspect,
  turnedSize,
  type CropPresetId,
  type CropRect,
} from './crop';
import { CropEditor } from './CropEditor';
import { CroppedPreview } from './CroppedPreview';
import type { DraftPhoto } from './draft';

/**
 * FRAME — the second beat of the create flow, mirroring mobile's
 * `frame/frame_beat.dart`: one photo at a time, pinch/drag crop with preset
 * chips driven by the grid tokens, quarter rotation, and a live "this is your
 * card on Surf" preview proportioned exactly as the masonry will draw it.
 */
export interface FrameBeatProps {
  photos: readonly DraftPhoto[];
  currentId: string | null;
  onSelect: (id: string) => void;
  onCropChange: (id: string, rect: CropRect) => void;
  onPreset: (id: string, preset: CropPresetId) => void;
  onRotate: (id: string) => void;
  disabled?: boolean;
}

export function FrameBeat({
  photos,
  currentId,
  onSelect,
  onCropChange,
  onPreset,
  onRotate,
  disabled = false,
}: FrameBeatProps) {
  const [showPreview, setShowPreview] = useState(true);

  if (photos.length === 0) {
    return (
      <div className="grid min-h-64 place-items-center rounded-xl border border-line bg-surface-1 p-8 text-center">
        <div>
          <p className="font-display text-title2 text-ink">Nothing to frame</p>
          <p className="mt-1 text-caption text-ink-2">
            Go back a step and pick a photo or two first.
          </p>
        </div>
      </div>
    );
  }

  const current = photos.find((photo) => photo.id === currentId) ?? photos[0]!;
  const ready = current.image !== null && current.baseWidth > 0;
  const { width: tw, height: th } = turnedSize(
    current.baseWidth,
    current.baseHeight,
    current.quarterTurns,
  );
  const preset = CROP_PRESETS.find((entry) => entry.id === current.preset) ?? CROP_PRESETS[0]!;
  const previewAspect = clampGridAspect(cropAspect(current.crop, tw, th));

  return (
    <div className="flex flex-col gap-3">
      <div className="relative h-[min(60dvh,540px)] overflow-hidden rounded-xl border border-line bg-surface-1">
        {ready && current.image ? (
          <>
            <CropEditor
              image={current.image}
              baseWidth={current.baseWidth}
              baseHeight={current.baseHeight}
              quarterTurns={current.quarterTurns}
              crop={current.crop}
              lockedAspect={preset.aspect}
              onCropChange={(rect) => onCropChange(current.id, rect)}
              className="p-3"
            />
            {showPreview ? (
              <button
                type="button"
                onClick={() => setShowPreview(false)}
                aria-label="Hide the Surf card preview"
                className="focus-ring absolute bottom-3 right-3 flex flex-col items-end gap-1"
              >
                <span className="rounded-full bg-scrim px-2 py-0.5 text-micro text-ink">
                  Your card on Surf
                </span>
                <CroppedPreview
                  image={current.image}
                  baseWidth={current.baseWidth}
                  baseHeight={current.baseHeight}
                  quarterTurns={current.quarterTurns}
                  crop={current.crop}
                  className="w-24 rounded-md border border-line-strong shadow-mid"
                  // The masonry clamps extreme ratios; the preview clamps the
                  // same way, so what you frame is what Surf shows.
                  style={{ aspectRatio: String(previewAspect) }}
                />
              </button>
            ) : null}
          </>
        ) : (
          <div className="grid size-full place-items-center text-ink-3">
            <Icon name="spinner" size="xl" />
          </div>
        )}
      </div>

      <div className="flex items-center gap-2">
        <ChipGroup label="Crop shape" className="min-w-0 flex-1 flex-nowrap overflow-x-auto">
          {CROP_PRESETS.map((entry) => (
            <Chip
              key={entry.id}
              selected={current.preset === entry.id}
              disabled={disabled || !ready}
              onClick={() => onPreset(current.id, entry.id)}
            >
              {entry.label}
            </Chip>
          ))}
        </ChipGroup>
        <IconButton
          icon="rotate"
          label="Rotate a quarter turn"
          disabled={disabled || !ready}
          onClick={() => onRotate(current.id)}
        />
        <IconButton
          icon="eye"
          label={showPreview ? 'Hide the Surf card preview' : 'Show the Surf card preview'}
          filled={showPreview}
          onClick={() => setShowPreview((value) => !value)}
        />
      </div>

      {photos.length > 1 ? (
        <ul className="flex gap-2 overflow-x-auto pb-1">
          {photos.map((photo) => (
            <li key={photo.id} className="shrink-0">
              <button
                type="button"
                onClick={() => onSelect(photo.id)}
                aria-label={`Frame photo ${photos.indexOf(photo) + 1}`}
                aria-current={photo.id === current.id || undefined}
                className={cn(
                  'focus-ring block size-14 overflow-hidden rounded-sm border transition-colors dur-fast',
                  photo.id === current.id
                    ? 'border-accent ring-1 ring-accent'
                    : 'border-line hover:border-line-strong',
                )}
              >
                {photo.image ? (
                  <CroppedPreview
                    image={photo.image}
                    baseWidth={photo.baseWidth}
                    baseHeight={photo.baseHeight}
                    quarterTurns={photo.quarterTurns}
                    crop={photo.crop}
                    className="size-full"
                  />
                ) : (
                  <span className="grid size-full place-items-center bg-skeleton text-ink-3">
                    <Icon name="spinner" size="sm" />
                  </span>
                )}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
