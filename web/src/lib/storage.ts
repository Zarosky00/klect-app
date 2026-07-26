import { SUPABASE_URL } from '@/lib/env';

export type PublicBucket = 'avatars' | 'banners' | 'media';
export type PrivateBucket = 'chat';
export type Bucket = PublicBucket | PrivateBucket;

/** Byte ceilings enforced by the bucket policy — mirror them client-side. */
export const BUCKET_MAX_BYTES: Record<Bucket, number> = {
  avatars: 5 * 1024 * 1024,
  banners: 10 * 1024 * 1024,
  media: 25 * 1024 * 1024,
  chat: 25 * 1024 * 1024,
};

const PUBLIC_BUCKETS = ['avatars', 'banners', 'media'] as const satisfies readonly PublicBucket[];

/**
 * Public object URL. Accepts the same three shapes as mobile
 * (`KlectApi.publicUrl`):
 *   · an absolute URL — returned unchanged;
 *   · a bucket-prefixed path (`media/{user_id}/…`) — the leading segment is
 *     stripped and resolved against *that* bucket;
 *   · a bare bucket-relative key (`{user_id}/{uuid}.webp`) — resolved against
 *     `bucket`. The first segment must be the uploader's id or the storage
 *     policy rejects the write.
 */
export function publicUrl(bucket: PublicBucket, path: string | null | undefined): string | null {
  if (!path) return null;
  if (/^https?:\/\//i.test(path)) return path;
  let resolved: PublicBucket = bucket;
  let key = path.replace(/^\/+/, '');
  const slash = key.indexOf('/');
  if (slash > 0) {
    const prefix = key.slice(0, slash);
    if ((PUBLIC_BUCKETS as readonly string[]).includes(prefix)) {
      resolved = prefix as PublicBucket;
      key = key.slice(slash + 1);
    }
  }
  return `${SUPABASE_URL}/storage/v1/object/public/${resolved}/${key}`;
}

export const avatarUrl = (path: string | null | undefined) => publicUrl('avatars', path);
export const bannerUrl = (path: string | null | undefined) => publicUrl('banners', path);
export const mediaUrl = (path: string | null | undefined) => publicUrl('media', path);

/**
 * Hosts the next/image optimizer is allowed to fetch from — must mirror
 * `images.remotePatterns` in `next.config.ts`. Anything else (a user pasted an
 * arbitrary absolute URL somewhere) renders `unoptimized` rather than throwing
 * next/image's unconfigured-host error at runtime.
 */
const OPTIMIZED_IMAGE_HOSTS = new Set([
  new URL(SUPABASE_URL).hostname,
  'picsum.photos',
  'fastly.picsum.photos',
]);

export function isOptimizableImageSrc(src: string): boolean {
  if (src.startsWith('/')) return true;
  try {
    return OPTIMIZED_IMAGE_HOSTS.has(new URL(src).hostname);
  } catch {
    return false;
  }
}

/** Bucket-relative object key. The leading segment must be the uploader's id. */
export function objectKey(userId: string, filename: string, scope?: string): string {
  return scope ? `${userId}/${scope}/${filename}` : `${userId}/${filename}`;
}

export function fileTooLarge(bucket: Bucket, bytes: number): boolean {
  return bytes > BUCKET_MAX_BYTES[bucket];
}
