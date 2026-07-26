'use client';

/**
 * The upload pipeline: downscale → WebP re-encode → blurhash → intrinsic size →
 * bucket, with real per-file progress.
 *
 * Why re-encode in the browser: a 12 MP phone original is ~6 MB and the grid
 * only ever renders it a few hundred pixels wide. Shipping the original wastes
 * the user's data and the bucket's quota for no visible gain.
 *
 * Why blurhash + intrinsic width/height are computed here: `surf_card` and every
 * grid tile reserve their box from those numbers *before* the image loads. If
 * they are missing the masonry reflows, which is the one thing DESIGN_SYSTEM §5
 * says must never happen.
 *
 * The numbers below are upload policy, not design values — they describe how
 * many pixels are worth storing, not how the UI looks. Colour, spacing, radius,
 * duration and easing all still come from the token modules.
 */
import { encode } from 'blurhash';
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/lib/env';
import { toKlectError } from '@/lib/errors';
import { BUCKET_MAX_BYTES, type Bucket } from '@/lib/storage';

/** Longest edge kept for gallery media. Comfortably above any tile's CSS size. */
export const MAX_MEDIA_EDGE = 2048;
/** Avatars and banners never render large; a smaller ceiling keeps them snappy. */
export const MAX_AVATAR_EDGE = 512;
export const MAX_BANNER_EDGE = 1600;
/** WebP quality. Above ~0.9 the file grows fast for no perceptible gain. */
export const WEBP_QUALITY = 0.86;
/** Blurhash components. 4×3 is the usual sweet spot for landscape-ish photos. */
const BLURHASH_X = 4;
const BLURHASH_Y = 3;
/** Blurhash is computed from a tiny thumbnail — it is a 20-byte string either way. */
const BLURHASH_SAMPLE = 32;

export const ACCEPTED_IMAGE_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/avif',
  'image/gif',
  'image/heic',
  'image/heif',
] as const;

export const ACCEPT_ATTRIBUTE = 'image/*';

export interface PreparedImage {
  /** The re-encoded WebP ready to upload. */
  blob: Blob;
  /** Intrinsic pixels of `blob`, after downscaling. */
  width: number;
  height: number;
  blurhash: string;
  /** Average colour, used as the paint under the blurhash while it decodes. */
  dominantColor: string;
  bytes: number;
  mimeType: string;
  /** Object URL for the local preview. Revoke it with `releasePreview`. */
  previewUrl: string;
  originalName: string;
}

export function releasePreview(prepared: Pick<PreparedImage, 'previewUrl'>): void {
  URL.revokeObjectURL(prepared.previewUrl);
}

function loadBitmap(file: Blob): Promise<ImageBitmap | HTMLImageElement> {
  if (typeof createImageBitmap === 'function') {
    return createImageBitmap(file);
  }
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('That file could not be read as an image.'));
    };
    image.src = url;
  });
}

function bitmapSize(source: ImageBitmap | HTMLImageElement): { width: number; height: number } {
  if ('naturalWidth' in source) {
    return { width: source.naturalWidth, height: source.naturalHeight };
  }
  return { width: source.width, height: source.height };
}

function scaleTo(
  width: number,
  height: number,
  maxEdge: number,
): { width: number; height: number } {
  const longest = Math.max(width, height);
  if (longest <= maxEdge) return { width, height };
  const factor = maxEdge / longest;
  return {
    width: Math.max(1, Math.round(width * factor)),
    height: Math.max(1, Math.round(height * factor)),
  };
}

function toHex(value: number): string {
  return Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0');
}

function averageColor(data: Uint8ClampedArray): string {
  let r = 0;
  let g = 0;
  let b = 0;
  let n = 0;
  for (let index = 0; index < data.length; index += 4) {
    r += data[index] ?? 0;
    g += data[index + 1] ?? 0;
    b += data[index + 2] ?? 0;
    n += 1;
  }
  if (n === 0) return '#000000';
  return `#${toHex(r / n)}${toHex(g / n)}${toHex(b / n)}`;
}

function canvasToBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (blob) resolve(blob);
        else reject(new Error('The browser refused to encode that image.'));
      },
      'image/webp',
      quality,
    );
  });
}

export interface PrepareOptions {
  maxEdge?: number;
  quality?: number;
}

/**
 * One pass over the file: decode, downscale, encode WebP, and derive the
 * blurhash + dominant colour from a 32px sample of the same canvas.
 */
export async function prepareImage(
  file: File,
  options: PrepareOptions = {},
): Promise<PreparedImage> {
  const maxEdge = options.maxEdge ?? MAX_MEDIA_EDGE;
  const quality = options.quality ?? WEBP_QUALITY;

  const source = await loadBitmap(file);
  const intrinsic = bitmapSize(source);
  if (intrinsic.width === 0 || intrinsic.height === 0) {
    throw new Error('That image has no pixels.');
  }
  const target = scaleTo(intrinsic.width, intrinsic.height, maxEdge);

  const canvas = document.createElement('canvas');
  canvas.width = target.width;
  canvas.height = target.height;
  const context = canvas.getContext('2d', { alpha: false });
  if (!context) throw new Error('This browser cannot process images.');
  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = 'high';
  context.drawImage(source as CanvasImageSource, 0, 0, target.width, target.height);

  const blob = await canvasToBlob(canvas, quality);

  // Blurhash wants a tiny sample; encoding the full canvas is pure waste.
  const sample = scaleTo(target.width, target.height, BLURHASH_SAMPLE);
  const sampleCanvas = document.createElement('canvas');
  sampleCanvas.width = sample.width;
  sampleCanvas.height = sample.height;
  const sampleContext = sampleCanvas.getContext('2d', { alpha: false });
  if (!sampleContext) throw new Error('This browser cannot process images.');
  sampleContext.drawImage(canvas, 0, 0, sample.width, sample.height);
  const pixels = sampleContext.getImageData(0, 0, sample.width, sample.height);

  const blurhash = encode(pixels.data, sample.width, sample.height, BLURHASH_X, BLURHASH_Y);
  const dominantColor = averageColor(pixels.data);

  if ('close' in source && typeof source.close === 'function') source.close();

  return {
    blob,
    width: target.width,
    height: target.height,
    blurhash,
    dominantColor,
    bytes: blob.size,
    mimeType: 'image/webp',
    previewUrl: URL.createObjectURL(blob),
    originalName: file.name,
  };
}

/* ── upload ───────────────────────────────────────────────────────────────── */

export interface UploadParams {
  accessToken: string;
  bucket: Bucket;
  /** Bucket-relative key. The first segment MUST be the uploader's user id. */
  path: string;
  body: Blob;
  contentType: string;
  upsert?: boolean;
  onProgress?: (fraction: number) => void;
  signal?: AbortSignal;
}

/**
 * Uploads straight to the Storage REST endpoint with `XMLHttpRequest`.
 *
 * `supabase-js@2`'s `storage.upload()` goes through `fetch`, which cannot report
 * request progress — and "per-file progress" is a hard requirement here
 * (CHECKLIST A). This is the same endpoint and the same auth the SDK uses, so
 * the bucket policy still applies: the object key's first segment must be the
 * uploader's id or the server rejects it.
 */
export function uploadObject(params: UploadParams): Promise<void> {
  return new Promise((resolve, reject) => {
    const url = `${SUPABASE_URL}/storage/v1/object/${params.bucket}/${params.path
      .split('/')
      .map(encodeURIComponent)
      .join('/')}`;

    const request = new XMLHttpRequest();
    request.open('POST', url, true);
    request.setRequestHeader('authorization', `Bearer ${params.accessToken}`);
    request.setRequestHeader('apikey', SUPABASE_PUBLISHABLE_KEY);
    request.setRequestHeader('x-upsert', params.upsert ? 'true' : 'false');
    request.setRequestHeader('content-type', params.contentType);
    request.setRequestHeader('cache-control', 'max-age=3600');

    request.upload.onprogress = (event) => {
      if (!event.lengthComputable) return;
      params.onProgress?.(event.total > 0 ? event.loaded / event.total : 0);
    };

    request.onload = () => {
      if (request.status >= 200 && request.status < 300) {
        params.onProgress?.(1);
        resolve();
        return;
      }
      let message = `Upload failed (${request.status}).`;
      try {
        const parsed = JSON.parse(request.responseText) as { message?: string; error?: string };
        message = parsed.message ?? parsed.error ?? message;
      } catch {
        // A non-JSON body means the gateway failed; the status is enough.
      }
      reject(toKlectError({ message, code: String(request.status) }));
    };

    request.onerror = () =>
      reject(toKlectError(new TypeError('Network error during upload.')));
    request.onabort = () => reject(toKlectError(new DOMException('Aborted', 'AbortError')));

    if (params.signal) {
      if (params.signal.aborted) {
        request.abort();
        return;
      }
      params.signal.addEventListener('abort', () => request.abort(), { once: true });
    }

    request.send(params.body);
  });
}

/** Mirrors the bucket ceiling client-side so a doomed upload never starts. */
export function assertWithinBucketLimit(bucket: Bucket, bytes: number): void {
  if (bytes > BUCKET_MAX_BYTES[bucket]) {
    const mb = Math.round(BUCKET_MAX_BYTES[bucket] / (1024 * 1024));
    throw new Error(`That file is over the ${mb} MB limit for ${bucket}.`);
  }
}

/** `{user_id}/{uuid}.webp` — or `{user_id}/{scope}/{uuid}.webp` when scoped. */
export function mediaObjectKey(userId: string, scope?: string): string {
  const name = `${crypto.randomUUID()}.webp`;
  return scope ? `${userId}/${scope}/${name}` : `${userId}/${name}`;
}
