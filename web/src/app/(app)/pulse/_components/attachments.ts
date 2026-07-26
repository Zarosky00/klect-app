/**
 * Isomorphic on purpose — no `'use client'`. The Pulse page resolves the first
 * page's attachments on the server; the stream resolves later pages in the
 * browser. Both call the same function with their own Supabase client.
 *
 * `pulse_feed` returns the *reference* to an attached entity — `target_type` and
 * `target_id` — not the entity itself. This resolves a whole page of those
 * references in at most three batched reads (one per entity type), so a shared
 * collection can render as a rich card instead of a bare link.
 *
 * Counter columns are read, never recomputed.
 */
import type { Client } from '@/lib/api';
import type { EntityType } from '@/lib/entities';
import { entityKey } from '@/lib/entities';
import type { PulseEntry } from '@/lib/types';

export interface PulseAttachment {
  type: EntityType;
  id: string;
  title: string;
  subtitle: string | null;
  coverPath: string | null;
  blurhash: string | null;
  width: number | null;
  height: number | null;
  childCount: number;
  likeCount: number;
}

export type AttachmentMap = Map<string, PulseAttachment>;

async function fetchCollections(client: Client, ids: string[]) {
  if (ids.length === 0) return [];
  const { data } = await client
    .from('collections')
    .select('id, name, description, cover_path, cover_blurhash, item_count, like_count')
    .in('id', ids);
  return data ?? [];
}

async function fetchSubcollections(client: Client, ids: string[]) {
  if (ids.length === 0) return [];
  const { data } = await client
    .from('subcollections')
    .select('id, name, description, cover_path, cover_blurhash, item_count, like_count')
    .in('id', ids);
  return data ?? [];
}

async function fetchItems(client: Client, ids: string[]) {
  if (ids.length === 0) return [];
  const { data } = await client
    .from('items')
    .select(
      'id, title, brand, cover_path, cover_blurhash, cover_width, cover_height, media_count, like_count',
    )
    .in('id', ids);
  return data ?? [];
}

export async function loadAttachments(
  client: Client,
  entries: readonly PulseEntry[],
  known?: AttachmentMap,
): Promise<AttachmentMap> {
  const resolved: AttachmentMap = new Map(known ?? []);

  const wanted: Record<'collection' | 'subcollection' | 'item', Set<string>> = {
    collection: new Set(),
    subcollection: new Set(),
    item: new Set(),
  };

  for (const entry of entries) {
    const type = entry.target_type;
    const id = entry.target_id;
    if (!type || !id) continue;
    if (type === 'post' || type === 'comment') continue;
    if (resolved.has(entityKey(type, id))) continue;
    wanted[type].add(id);
  }

  const [collections, subcollections, items] = await Promise.all([
    fetchCollections(client, [...wanted.collection]),
    fetchSubcollections(client, [...wanted.subcollection]),
    fetchItems(client, [...wanted.item]),
  ]);

  for (const row of collections) {
    resolved.set(entityKey('collection', row.id), {
      type: 'collection',
      id: row.id,
      title: row.name,
      subtitle: row.description,
      coverPath: row.cover_path,
      blurhash: row.cover_blurhash,
      width: null,
      height: null,
      childCount: row.item_count,
      likeCount: row.like_count,
    });
  }

  for (const row of subcollections) {
    resolved.set(entityKey('subcollection', row.id), {
      type: 'subcollection',
      id: row.id,
      title: row.name,
      subtitle: row.description,
      coverPath: row.cover_path,
      blurhash: row.cover_blurhash,
      width: null,
      height: null,
      childCount: row.item_count,
      likeCount: row.like_count,
    });
  }

  for (const row of items) {
    resolved.set(entityKey('item', row.id), {
      type: 'item',
      id: row.id,
      title: row.title,
      subtitle: row.brand,
      coverPath: row.cover_path,
      blurhash: row.cover_blurhash,
      width: row.cover_width,
      height: row.cover_height,
      childCount: row.media_count,
      likeCount: row.like_count,
    });
  }

  return resolved;
}
