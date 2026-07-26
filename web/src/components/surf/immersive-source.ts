import type { EntityType } from '@/lib/entities';
import { mediaUrl } from '@/lib/storage';
import type { CloseupMedia, CloseupPayload } from '@/lib/types';

/**
 * The immersive viewer's input types and payload mappers, split out of
 * `ImmersiveViewer.tsx` so callers (TileGrid, CloseupView) can build a source
 * without pulling the whole viewer — which is dynamic-imported and only lands
 * in the bundle on the first double-tap.
 */

export interface ImmersivePhoto {
  id: string;
  src: string | null;
  alt: string;
  width: number | null;
  height: number | null;
}

export interface ImmersiveSource {
  type: EntityType;
  id: string;
  title: string;
  /** Shown immediately, before the full set arrives. */
  cover: { path: string | null; width: number | null; height: number | null };
  /** Supplied by the closeup, which already holds the media array. */
  photos?: ImmersivePhoto[];
  startIndex?: number;
}

export function photosFromMedia(media: CloseupMedia[], title: string): ImmersivePhoto[] {
  return media.map((photo, index) => ({
    id: photo.id,
    src: mediaUrl(photo.storage_path),
    alt: photo.alt_text ?? `${title} — photo ${index + 1} of ${media.length}`,
    width: photo.width,
    height: photo.height,
  }));
}

/**
 * Mobile parity (`immersiveMediaOf`): an item pages through its own media; a
 * collection or subcollection opens as a multi-photo set — its **own** cover
 * first (that is what the tile showed, so the viewer lands on the right
 * picture), then subcollection covers, then item covers, deduped by path so a
 * double tap sweeps the whole shelf without repeats.
 */
export function photosFromPayload(payload: CloseupPayload, title: string): ImmersivePhoto[] {
  if (payload.entity_type === 'item') return photosFromMedia(payload.media, title);
  if (payload.entity_type !== 'collection' && payload.entity_type !== 'subcollection') {
    return [];
  }

  const photos: ImmersivePhoto[] = [];
  const seen = new Set<string>();
  const add = (photo: {
    id: string;
    path: string | null;
    alt: string;
    width?: number | null;
    height?: number | null;
  }): void => {
    if (!photo.path || seen.has(photo.path)) return;
    seen.add(photo.path);
    photos.push({
      id: photo.id,
      src: mediaUrl(photo.path),
      alt: photo.alt,
      width: photo.width ?? null,
      height: photo.height ?? null,
    });
  };

  const ownCover =
    payload.entity_type === 'collection'
      ? payload.collection.cover_path
      : payload.subcollection.cover_path;
  add({ id: `${payload.entity_type}:${payload.entity_id}`, path: ownCover, alt: title });

  if (payload.entity_type === 'collection') {
    for (const sub of payload.subcollections) {
      add({ id: `subcollection:${sub.id}`, path: sub.cover_path, alt: sub.name });
    }
  }
  for (const item of payload.items) {
    add({
      id: item.id,
      path: item.cover_path,
      alt: item.title,
      width: item.cover_width,
      height: item.cover_height,
    });
  }
  return photos;
}
