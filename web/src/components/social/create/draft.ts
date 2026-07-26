import type { CropPresetId, CropRect } from './crop';

/**
 * One photo in the create draft, from pick to upload. Nothing leaves the tab
 * until save: the FRAME edits live here as data, and the bytes are only
 * cropped/encoded/uploaded when the user commits — which is what makes
 * re-cropping free and retries safe (the bucket path never changes, and the
 * upload is an upsert).
 */
export type DraftPhotoStatus =
  /** Still decoding the picked file for its dimensions. */
  | 'decoding'
  /** Decoded and editable; nothing uploaded yet (or an edit invalidated it). */
  | 'ready'
  /** Save is cropping/encoding this photo. */
  | 'processing'
  /** Save is uploading this photo's bytes. */
  | 'uploading'
  /** Bytes are in the bucket and describe the current edit. */
  | 'done'
  /** The last save attempt failed on this photo; saving again retries it. */
  | 'failed';

/** What `prepareImage` measured on the uploaded (cropped) payload. */
export interface UploadedMeta {
  width: number;
  height: number;
  blurhash: string;
  dominantColor: string | null;
  bytes: number;
  mimeType: string;
}

export interface DraftPhoto {
  id: string;
  file: File;
  /** Object URL of the original file — previews only, revoked on removal. */
  url: string;
  /** Decoded element used for canvas drawing; null while `decoding`. */
  image: HTMLImageElement | null;
  /** Oriented source size (EXIF baked), before any quarter turns. */
  baseWidth: number;
  baseHeight: number;
  /** FRAME edits, in turned-frame pixel space. */
  quarterTurns: number;
  crop: CropRect | null;
  preset: CropPresetId;
  altText: string;
  /** Bucket key, fixed at pick time so retries upsert the same object. */
  path: string;
  status: DraftPhotoStatus;
  progress: number;
  error: string | null;
  uploaded: UploadedMeta | null;
}
