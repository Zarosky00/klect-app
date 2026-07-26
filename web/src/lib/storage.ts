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

/**
 * Public object URL. `storage_path` values in the database are bucket-relative
 * (`{user_id}/{uuid}.webp`) — the first segment must be the uploader's id or the
 * storage policy rejects the write.
 */
export function publicUrl(bucket: PublicBucket, path: string | null | undefined): string | null {
  if (!path) return null;
  if (/^https?:\/\//i.test(path)) return path;
  const clean = path.replace(/^\/+/, '');
  return `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${clean}`;
}

export const avatarUrl = (path: string | null | undefined) => publicUrl('avatars', path);
export const bannerUrl = (path: string | null | undefined) => publicUrl('banners', path);
export const mediaUrl = (path: string | null | undefined) => publicUrl('media', path);

/** Bucket-relative object key. The leading segment must be the uploader's id. */
export function objectKey(userId: string, filename: string, scope?: string): string {
  return scope ? `${userId}/${scope}/${filename}` : `${userId}/${filename}`;
}

export function fileTooLarge(bucket: Bucket, bytes: number): boolean {
  return bytes > BUCKET_MAX_BYTES[bucket];
}
