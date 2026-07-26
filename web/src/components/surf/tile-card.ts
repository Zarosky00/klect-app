/**
 * One shape for every tile the product renders.
 *
 * The surf feed, a collection's item grid, a subcollection's items, an item's
 * siblings and the marketing preview are all the same visual object with the
 * same gesture contract — so they all become a `TileCard` first and the tile
 * component never learns where the data came from.
 *
 * Counts arrive as counter columns straight from the server (BACKEND_API §1);
 * nothing here computes one.
 */
import type { SurfaceEntityType } from '@/lib/entities';
import type {
  CloseupChildItem,
  CloseupChildSubcollection,
  SearchItem,
  SiblingRef,
  SurfCard,
} from '@/lib/types';

export interface TileOwner {
  username: string;
  displayName: string;
  avatarPath: string | null;
  isVerified: boolean;
}

export interface TileCounts {
  like: number;
  save: number;
  repost: number;
  comment: number;
  view: number;
  /** Items in a collection/subcollection, photos in an item. */
  child: number;
}

export interface TileViewer {
  liked: boolean;
  saved: boolean;
  reposted: boolean;
}

export interface TileCard {
  type: SurfaceEntityType;
  id: string;
  title: string;
  subtitle: string | null;
  coverPath: string | null;
  blurhash: string | null;
  /** Intrinsic cover pixels — the masonry reserves the tile with these. */
  width: number | null;
  height: number | null;
  accentColor: string | null;
  owner: TileOwner | null;
  counts: TileCounts;
  viewer: TileViewer;
}

const NO_VIEWER: TileViewer = { liked: false, saved: false, reposted: false };

const counts = (partial: Partial<TileCounts>): TileCounts => ({
  like: partial.like ?? 0,
  save: partial.save ?? 0,
  repost: partial.repost ?? 0,
  comment: partial.comment ?? 0,
  view: partial.view ?? 0,
  child: partial.child ?? 0,
});

/** A stable identity for React keys, dedupe sets and the interaction store. */
export const tileKey = (card: Pick<TileCard, 'type' | 'id'>): string =>
  `${card.type}:${card.id}`;

export function tileFromSurfCard(card: SurfCard): TileCard {
  return {
    type: card.entity_type,
    id: card.entity_id,
    title: card.title,
    subtitle: card.subtitle,
    coverPath: card.cover_path,
    blurhash: card.cover_blurhash,
    width: card.width,
    height: card.height,
    accentColor: card.accent_color,
    owner: {
      username: card.username,
      displayName: card.display_name,
      avatarPath: card.avatar_path,
      isVerified: card.is_verified,
    },
    counts: counts({
      like: card.like_count,
      save: card.save_count,
      repost: card.repost_count,
      comment: card.comment_count,
      view: card.view_count,
      child: card.child_count,
    }),
    viewer: {
      liked: card.viewer_liked,
      saved: card.viewer_saved,
      reposted: card.viewer_reposted,
    },
  };
}

/** `get_closeup` → `items[]` on a collection or subcollection. */
export function tileFromChildItem(
  item: CloseupChildItem,
  owner: TileOwner | null = null,
): TileCard {
  return {
    type: 'item',
    id: item.id,
    title: item.title,
    subtitle: null,
    coverPath: item.cover_path,
    blurhash: item.cover_blurhash,
    width: item.cover_width,
    height: item.cover_height,
    accentColor: null,
    owner,
    counts: counts({
      like: item.like_count,
      save: item.save_count ?? 0,
      comment: item.comment_count ?? 0,
      child: item.media_count,
    }),
    viewer: NO_VIEWER,
  };
}

/** `get_closeup` → `subcollections[]` on a collection. */
export function tileFromChildSubcollection(
  subcollection: CloseupChildSubcollection,
  owner: TileOwner | null = null,
): TileCard {
  return {
    type: 'subcollection',
    id: subcollection.id,
    title: subcollection.name,
    subtitle: null,
    coverPath: subcollection.cover_path,
    blurhash: subcollection.cover_blurhash,
    width: null,
    height: null,
    accentColor: null,
    owner,
    counts: counts({ child: subcollection.item_count }),
    viewer: NO_VIEWER,
  };
}

/** `get_closeup` → `siblings[]` on an item. */
export function tileFromSibling(
  sibling: SiblingRef,
  owner: TileOwner | null = null,
): TileCard {
  return {
    type: 'item',
    id: sibling.id,
    title: sibling.title,
    subtitle: null,
    coverPath: sibling.cover_path,
    blurhash: sibling.cover_blurhash,
    width: sibling.cover_width,
    height: sibling.cover_height,
    accentColor: null,
    owner,
    counts: counts({ like: sibling.like_count }),
    viewer: NO_VIEWER,
  };
}

/** `search_all` → `items[]`. */
export function tileFromSearchItem(item: SearchItem): TileCard {
  return {
    type: 'item',
    id: item.id,
    title: item.title,
    subtitle: item.brand,
    coverPath: item.cover_path,
    blurhash: item.cover_blurhash,
    width: item.cover_width,
    height: item.cover_height,
    accentColor: null,
    owner: {
      username: item.username,
      displayName: item.display_name,
      avatarPath: item.avatar_path,
      isVerified: false,
    },
    counts: counts({ like: item.like_count }),
    viewer: NO_VIEWER,
  };
}
