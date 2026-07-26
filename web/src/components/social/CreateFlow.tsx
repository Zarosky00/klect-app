'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { VISIBILITY_LABELS, type Visibility } from '@/lib/entities';
import { cn } from '@/lib/cn';
import { collectionHref, itemHref, subcollectionHref } from '@/lib/routes';
import { Button, IconButton } from '@/components/ui/Button';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { Icon } from '@/components/ui/Icon';
import { TextArea, TextField } from '@/components/ui/TextField';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { SelectField } from './Field';
import { ProgressBar } from './ProfileEditor';
import {
  ACCEPT_ATTRIBUTE,
  assertWithinBucketLimit,
  prepareImage,
  releasePreview,
  uploadObject,
} from './media';
import {
  attachTags,
  collectionSummary,
  createCollection,
  createItem,
  createSubcollection,
  insertItemMedia,
  listSubcollectionSummaries,
  subcollectionSummary,
  type EntitySummary,
} from './queries';
import {
  maxCenteredCrop,
  presetById,
  rotateCropRect,
  turnedSize,
  type CropPresetId,
  type CropRect,
} from './create/crop';
import { CroppedPreview } from './create/CroppedPreview';
import type { DraftPhoto, UploadedMeta } from './create/draft';
import { FrameBeat } from './create/FrameBeat';
import { PickGrid } from './create/PickGrid';

/**
 * Create — the media-first three-beat flow, mirroring mobile's
 * `create_item_flow_screen.dart`: **PICK → FRAME → FILE**.
 *
 * The old form asked for a title before it would show a photo. This flow
 * inverts it: photos first (drag-drop, file picker or paste), then the
 * crop/rotate pass with the live "your card on Surf" preview, and only then
 * one compact filing step — title, destination (with inline shelf/group
 * creation that never leaves the flow), visibility, details behind a fold.
 *
 * Nothing uploads until save. The item's UUID is generated here, every
 * photo's bucket key is fixed at pick time, and the upload is an upsert — so
 * a failed save retries the exact same objects, a re-crop simply overwrites
 * them, and the `items` + `item_media` rows are only written once every byte
 * has landed. Kill the tab mid-save and you leave a few unreferenced objects
 * in a bucket; you never leave a broken row. (CHECKLIST A.)
 */

type Mode = 'collection' | 'subcollection' | 'item';
type Beat = 'pick' | 'frame' | 'file';

const MODE_ORDER: readonly Mode[] = ['item', 'collection', 'subcollection'];

const MODE_LABELS: Record<Mode, string> = {
  collection: 'Collection',
  subcollection: 'Subcollection',
  item: 'Item',
};

const MODE_BLURB: Record<Mode, string> = {
  collection: 'A shelf you own — "Anime", "Resin", "Cameras".',
  subcollection: 'A themed group inside a collection — "JJK", "One Piece".',
  item: 'A thing, with one to many photos. Photos first; filing comes last.',
};

const BEAT_TITLES: Record<Beat, string> = {
  pick: 'Pick photos',
  frame: 'Frame your shots',
  file: 'File it away',
};

const BEAT_INDEX: Record<Beat, number> = { pick: 0, frame: 1, file: 2 };

const VISIBILITIES: readonly Visibility[] = ['public', 'followers', 'private'];
const MAX_PHOTOS = 12;

export interface CreateFlowProps {
  collections: EntitySummary[];
  /** Preselects a parent when arriving from a collection page. */
  initialCollectionId?: string | null;
  initialMode?: Mode;
}

export function CreateFlow({
  collections,
  initialCollectionId = null,
  initialMode = 'item',
}: CreateFlowProps) {
  const router = useRouter();
  const { supabase, user } = useSession();
  const { success, fromError, error: errorToast } = useToast();

  const [mode, setMode] = useState<Mode>(initialMode);
  const [beat, setBeat] = useState<Beat>('pick');
  const [busy, setBusy] = useState(false);
  const [inlineError, setInlineError] = useState<string | null>(null);

  /* destination — shelves grow when one is created inline */
  const [shelves, setShelves] = useState<EntitySummary[]>(collections);
  const [collectionId, setCollectionId] = useState(
    initialCollectionId ?? collections[0]?.id ?? '',
  );
  const [groups, setGroups] = useState<EntitySummary[]>([]);
  const [subcollectionId, setSubcollectionId] = useState('');
  const [newShelfOpen, setNewShelfOpen] = useState(false);
  const [newShelfName, setNewShelfName] = useState('');
  const [newShelfBusy, setNewShelfBusy] = useState(false);
  const [newGroupOpen, setNewGroupOpen] = useState(false);
  const [newGroupName, setNewGroupName] = useState('');
  const [newGroupBusy, setNewGroupBusy] = useState(false);

  /* shared fields */
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [visibility, setVisibility] = useState<Visibility>('public');
  /** Item visibility; empty string = inherit from the group/shelf. */
  const [itemVisibility, setItemVisibility] = useState<Visibility | ''>('');
  const [showDetails, setShowDetails] = useState(false);

  /* item details, folded behind "Add details" */
  const [brand, setBrand] = useState('');
  const [model, setModel] = useState('');
  const [year, setYear] = useState('');
  const [condition, setCondition] = useState('');
  const [rarity, setRarity] = useState('');
  const [acquisitionPlace, setAcquisitionPlace] = useState('');
  const [acquisitionDate, setAcquisitionDate] = useState('');
  const [purchasePrice, setPurchasePrice] = useState('');
  const [currency, setCurrency] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [tagDraft, setTagDraft] = useState('');

  /* photos — the draft */
  const [itemId, setItemId] = useState(() => crypto.randomUUID());
  const [createdItemId, setCreatedItemId] = useState<string | null>(null);
  const [photos, setPhotos] = useState<DraftPhoto[]>([]);
  const [frameId, setFrameId] = useState<string | null>(null);

  const photosRef = useRef(photos);
  photosRef.current = photos;
  const trayInput = useRef<HTMLInputElement | null>(null);

  /* Revoke every preview URL when the flow unmounts. */
  useEffect(
    () => () => {
      for (const photo of photosRef.current) URL.revokeObjectURL(photo.url);
    },
    [],
  );

  useEffect(() => {
    if (!collectionId) {
      setGroups([]);
      return;
    }
    let active = true;
    void listSubcollectionSummaries(supabase, collectionId)
      .then((rows) => {
        if (active) setGroups(rows);
      })
      .catch(() => {
        if (active) setGroups([]);
      });
    return () => {
      active = false;
    };
  }, [collectionId, supabase]);

  /* ── photo staging (nothing uploads here) ───────────────────────────────── */

  const patchPhoto = useCallback((id: string, patch: Partial<DraftPhoto>) => {
    setPhotos((current) =>
      current.map((photo) => (photo.id === id ? { ...photo, ...patch } : photo)),
    );
  }, []);

  /** A FRAME edit invalidates any bytes a previous save already uploaded. */
  const applyEdit = useCallback((id: string, patch: Partial<DraftPhoto>) => {
    setPhotos((current) =>
      current.map((photo) =>
        photo.id === id
          ? {
              ...photo,
              ...patch,
              uploaded: null,
              progress: 0,
              error: null,
              status: photo.status === 'decoding' ? 'decoding' : 'ready',
            }
          : photo,
      ),
    );
  }, []);

  const addFiles = useCallback(
    (files: File[]) => {
      if (!user) return;
      const room = MAX_PHOTOS - photosRef.current.length;
      if (room <= 0) {
        errorToast(`That is ${MAX_PHOTOS} photos — the ceiling for one item.`);
        return;
      }
      for (const file of files.slice(0, room)) {
        try {
          assertWithinBucketLimit('media', file.size);
        } catch (thrown) {
          fromError(thrown);
          continue;
        }
        const id = crypto.randomUUID();
        const url = URL.createObjectURL(file);
        const draft: DraftPhoto = {
          id,
          file,
          url,
          image: null,
          baseWidth: 0,
          baseHeight: 0,
          quarterTurns: 0,
          crop: null,
          preset: 'original',
          altText: '',
          path: `${user.id}/${itemId}/${crypto.randomUUID()}.webp`,
          status: 'decoding',
          progress: 0,
          error: null,
          uploaded: null,
        };
        setPhotos((current) => (current.length >= MAX_PHOTOS ? current : [...current, draft]));

        const image = new Image();
        image.src = url;
        image
          .decode()
          .then(() =>
            patchPhoto(id, {
              image,
              baseWidth: image.naturalWidth,
              baseHeight: image.naturalHeight,
              status: 'ready',
            }),
          )
          .catch(() => {
            URL.revokeObjectURL(url);
            setPhotos((current) => current.filter((photo) => photo.id !== id));
            errorToast('That file could not be read as an image.');
          });
      }
    },
    [errorToast, fromError, itemId, patchPhoto, user],
  );

  const removePhoto = useCallback((id: string) => {
    setPhotos((current) => {
      const target = current.find((photo) => photo.id === id);
      if (target) URL.revokeObjectURL(target.url);
      return current.filter((photo) => photo.id !== id);
    });
    setFrameId((current) => (current === id ? null : current));
  }, []);

  /* ── FRAME edits ────────────────────────────────────────────────────────── */

  const setCrop = useCallback(
    (id: string, rect: CropRect) => applyEdit(id, { crop: rect }),
    [applyEdit],
  );

  const applyPreset = useCallback(
    (id: string, presetId: CropPresetId) => {
      const photo = photosRef.current.find((entry) => entry.id === id);
      if (!photo || photo.baseWidth <= 0) return;
      const preset = presetById(presetId);
      const { width: tw, height: th } = turnedSize(
        photo.baseWidth,
        photo.baseHeight,
        photo.quarterTurns,
      );
      applyEdit(id, {
        preset: presetId,
        crop: preset.aspect === null ? null : maxCenteredCrop(tw, th, preset.aspect),
      });
    },
    [applyEdit],
  );

  const rotatePhoto = useCallback(
    (id: string) => {
      const photo = photosRef.current.find((entry) => entry.id === id);
      if (!photo || photo.baseWidth <= 0) return;
      const oldTurnedHeight = turnedSize(
        photo.baseWidth,
        photo.baseHeight,
        photo.quarterTurns,
      ).height;
      // Tall becomes wide (and back) when the frame turns with the photo.
      const preset: CropPresetId =
        photo.preset === 'tall' ? 'wide' : photo.preset === 'wide' ? 'tall' : photo.preset;
      applyEdit(id, {
        quarterTurns: (photo.quarterTurns + 1) % 4,
        crop: photo.crop ? rotateCropRect(photo.crop, oldTurnedHeight) : null,
        preset,
      });
    },
    [applyEdit],
  );

  /* ── inline destination creation (never leaves the flow) ────────────────── */

  const quickCreateShelf = async () => {
    const trimmed = newShelfName.trim();
    if (!trimmed || !user) return;
    setNewShelfBusy(true);
    try {
      const row = await createCollection(supabase, {
        userId: user.id,
        name: trimmed,
        description: null,
        visibility: 'public',
      });
      setShelves((current) => [...current, collectionSummary(row)]);
      setCollectionId(row.id);
      setSubcollectionId('');
      setNewShelfName('');
      setNewShelfOpen(false);
      success('Shelf created', 'Public by default — change that any time from the shelf page.');
    } catch (thrown) {
      fromError(thrown);
    } finally {
      setNewShelfBusy(false);
    }
  };

  const quickCreateGroup = async () => {
    const trimmed = newGroupName.trim();
    if (!trimmed || !user || !collectionId) return;
    setNewGroupBusy(true);
    try {
      const row = await createSubcollection(supabase, {
        userId: user.id,
        collectionId,
        name: trimmed,
        description: null,
        visibility: null,
      });
      setGroups((current) => [...current, subcollectionSummary(row)]);
      setSubcollectionId(row.id);
      setNewGroupName('');
      setNewGroupOpen(false);
      success('Group created');
    } catch (thrown) {
      fromError(thrown);
    } finally {
      setNewGroupBusy(false);
    }
  };

  /* ── tags ───────────────────────────────────────────────────────────────── */

  const commitTag = () => {
    const value = tagDraft.trim().replace(/^#/, '');
    if (!value) return;
    setTags((current) => (current.includes(value) ? current : [...current, value].slice(0, 12)));
    setTagDraft('');
  };

  /* ── reset ──────────────────────────────────────────────────────────────── */

  const resetDraft = () => {
    for (const photo of photosRef.current) URL.revokeObjectURL(photo.url);
    setPhotos([]);
    setFrameId(null);
    setBeat('pick');
    setItemId(crypto.randomUUID());
    setCreatedItemId(null);
    setName('');
    setDescription('');
    setItemVisibility('');
    setShowDetails(false);
    setBrand('');
    setModel('');
    setYear('');
    setCondition('');
    setRarity('');
    setAcquisitionPlace('');
    setAcquisitionDate('');
    setPurchasePrice('');
    setCurrency('');
    setTags([]);
    setTagDraft('');
    setInlineError(null);
  };

  /* ── save ───────────────────────────────────────────────────────────────── */

  const decoding = photos.some((photo) => photo.status === 'decoding');
  const doneCount = photos.filter((photo) => photo.status === 'done').length;
  const overallProgress =
    photos.length === 0
      ? 0
      : photos.reduce((sum, photo) => sum + (photo.status === 'done' ? 1 : photo.progress), 0) /
        photos.length;

  const canSaveItem =
    !busy && !decoding && photos.length > 0 && name.trim().length > 0 && collectionId.length > 0;

  /**
   * The deferred pipeline: crop → encode → upload each photo (per-photo
   * progress), and only when every byte has landed write `items`,
   * `item_media` and tags. Failed photos stay in the draft marked `failed`;
   * saving again retries exactly them (the bucket upsert makes that safe).
   */
  const saveItem = async () => {
    if (!user) return;
    const list = photosRef.current;
    if (list.length === 0) {
      setInlineError('Add at least one photo.');
      setBeat('pick');
      return;
    }
    if (!name.trim()) {
      setInlineError('Give the item a title.');
      return;
    }
    if (!collectionId) {
      setInlineError('Choose a shelf.');
      return;
    }
    if (list.some((photo) => photo.status === 'decoding')) {
      setInlineError('Still reading a photo — give it a beat, then save again.');
      return;
    }

    setBusy(true);
    setInlineError(null);
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();
      const accessToken = session?.access_token;
      if (!accessToken) throw new Error('Your session expired. Sign in again.');

      const uploadedMeta = new Map<string, UploadedMeta>();
      let failed = 0;

      for (const photo of list) {
        if (photo.status === 'done' && photo.uploaded) {
          uploadedMeta.set(photo.id, photo.uploaded);
          continue;
        }
        try {
          patchPhoto(photo.id, { status: 'processing', progress: 0, error: null });
          const prepared = await prepareImage(photo.file, {
            quarterTurns: photo.quarterTurns,
            cropRect: photo.crop,
          });
          releasePreview(prepared);
          patchPhoto(photo.id, { status: 'uploading', progress: 0 });
          await uploadObject({
            accessToken,
            bucket: 'media',
            path: photo.path,
            body: prepared.blob,
            contentType: prepared.mimeType,
            upsert: true,
            onProgress: (fraction) => patchPhoto(photo.id, { progress: fraction }),
          });
          const meta: UploadedMeta = {
            width: prepared.width,
            height: prepared.height,
            blurhash: prepared.blurhash,
            dominantColor: prepared.dominantColor,
            bytes: prepared.bytes,
            mimeType: prepared.mimeType,
          };
          uploadedMeta.set(photo.id, meta);
          patchPhoto(photo.id, { status: 'done', progress: 1, uploaded: meta });
        } catch (thrown) {
          failed += 1;
          patchPhoto(photo.id, {
            status: 'failed',
            error: thrown instanceof Error ? thrown.message : 'Upload failed',
          });
        }
      }

      if (failed > 0) {
        setInlineError(
          `${failed} photo(s) did not upload. Nothing was filed yet — save again to retry.`,
        );
        return;
      }

      // Every byte is in the bucket. Now — and only now — the rows.
      let rowId = createdItemId;
      if (!rowId) {
        const row = await createItem(supabase, {
          id: itemId,
          userId: user.id,
          collectionId,
          subcollectionId: subcollectionId || null,
          title: name.trim(),
          description: description.trim() || null,
          brand: brand.trim() || null,
          model: model.trim() || null,
          year: year ? Number(year) : null,
          condition: condition.trim() || null,
          rarity: rarity.trim() || null,
          acquisitionPlace: acquisitionPlace.trim() || null,
          acquisitionDate: acquisitionDate || null,
          purchasePrice: purchasePrice ? Number(purchasePrice) : null,
          currency: currency.trim().toUpperCase() || null,
          visibility: itemVisibility || null,
        });
        rowId = row.id;
        setCreatedItemId(rowId);
      }
      const finalId = rowId;

      await insertItemMedia(
        supabase,
        list.map((photo, index) => {
          const meta = uploadedMeta.get(photo.id);
          return {
            itemId: finalId,
            userId: user.id,
            storagePath: photo.path,
            width: meta?.width ?? 0,
            height: meta?.height ?? 0,
            blurhash: meta?.blurhash ?? '',
            dominantColor: meta?.dominantColor ?? null,
            mimeType: meta?.mimeType ?? 'image/webp',
            bytes: meta?.bytes ?? 0,
            altText: photo.altText.trim() || null,
            position: index,
          };
        }),
      );

      await safeTags(supabase, 'item', finalId, user.id, tags, fromError);
      success('Item added', `${list.length} photo(s) attached.`);
      for (const photo of photosRef.current) URL.revokeObjectURL(photo.url);
      router.push(itemHref(finalId));
    } catch (thrown) {
      fromError(thrown);
    } finally {
      setBusy(false);
    }
  };

  const saveEntity = async () => {
    if (!user) return;
    if (!name.trim()) {
      setInlineError('Give it a name first.');
      return;
    }
    if (mode === 'subcollection' && !collectionId) {
      setInlineError('Pick a collection to put this in.');
      return;
    }
    setBusy(true);
    setInlineError(null);
    try {
      if (mode === 'collection') {
        const row = await createCollection(supabase, {
          userId: user.id,
          name: name.trim(),
          description: description.trim() || null,
          visibility,
        });
        await safeTags(supabase, 'collection', row.id, user.id, tags, fromError);
        success('Collection created');
        router.push(collectionHref(row.id));
        return;
      }
      const row = await createSubcollection(supabase, {
        userId: user.id,
        collectionId,
        name: name.trim(),
        description: description.trim() || null,
        visibility: null,
      });
      await safeTags(supabase, 'subcollection', row.id, user.id, tags, fromError);
      success('Subcollection created');
      router.push(subcollectionHref(row.id));
    } catch (thrown) {
      fromError(thrown);
    } finally {
      setBusy(false);
    }
  };

  /* ── shared fragments ───────────────────────────────────────────────────── */

  const shelfPicker = (
    <div>
      <ChipGroup label="Shelf">
        {shelves.map((shelf) => (
          <Chip
            key={shelf.id}
            selected={collectionId === shelf.id}
            disabled={busy}
            onClick={() => {
              setCollectionId(shelf.id);
              setSubcollectionId('');
            }}
          >
            {shelf.title}
          </Chip>
        ))}
        {!newShelfOpen ? (
          <Chip icon="plus" disabled={busy} onClick={() => setNewShelfOpen(true)}>
            New shelf
          </Chip>
        ) : null}
      </ChipGroup>
      {shelves.length === 0 && !newShelfOpen ? (
        <p className="mt-2 text-caption text-ink-3">
          Everything has to live on a shelf. Make one right here — it takes a name and
          nothing else.
        </p>
      ) : null}
      {newShelfOpen ? (
        <div className="mt-2 flex items-center gap-2">
          <TextField
            label="New shelf name"
            labelHidden
            autoFocus
            value={newShelfName}
            maxLength={80}
            placeholder="Anime"
            disabled={newShelfBusy}
            onChange={(event) => setNewShelfName(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                event.preventDefault();
                void quickCreateShelf();
              }
            }}
            className="flex-1"
          />
          <Button
            loading={newShelfBusy}
            disabled={!newShelfName.trim()}
            onClick={() => void quickCreateShelf()}
          >
            Add
          </Button>
          <Button
            variant="ghost"
            disabled={newShelfBusy}
            onClick={() => {
              setNewShelfOpen(false);
              setNewShelfName('');
            }}
          >
            Cancel
          </Button>
        </div>
      ) : null}
    </div>
  );

  const tagsSection = (
    <div>
      <h3 className="text-label uppercase tracking-widest text-ink-3">Tags</h3>
      <p className="mb-3 mt-1 text-caption text-ink-2">
        Tags are how taste matching finds people like you.
      </p>
      <TextField
        label="Add a tag"
        labelHidden
        value={tagDraft}
        onChange={(event) => setTagDraft(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === 'Enter' || event.key === ',') {
            event.preventDefault();
            commitTag();
          }
        }}
        onBlur={commitTag}
        iconLeft="search"
        placeholder="Type a tag and press Enter"
        maxLength={32}
      />
      {tags.length > 0 ? (
        <ChipGroup className="mt-3">
          {tags.map((tag) => (
            <Chip
              key={tag}
              selected
              onRemove={() => setTags((current) => current.filter((entry) => entry !== tag))}
            >
              #{tag}
            </Chip>
          ))}
        </ChipGroup>
      ) : null}
    </div>
  );

  const selectedGroupName = groups.find((group) => group.id === subcollectionId)?.title ?? null;

  /* ── render ─────────────────────────────────────────────────────────────── */

  return (
    <div className="content-max px-4 py-8 sm:px-6">
      <header>
        <h1 className="font-display text-display2 text-ink">Create</h1>
        {mode !== 'item' || beat === 'pick' ? (
          <div className="mt-4">
            <ChipGroup label="What to create">
              {MODE_ORDER.map((value) => (
                <Chip
                  key={value}
                  selected={mode === value}
                  disabled={busy}
                  onClick={() => {
                    setMode(value);
                    setInlineError(null);
                  }}
                >
                  {MODE_LABELS[value]}
                </Chip>
              ))}
            </ChipGroup>
            <p className="mt-2 text-caption text-ink-3">{MODE_BLURB[mode]}</p>
          </div>
        ) : null}
      </header>

      {mode === 'item' ? (
        <section className="mt-6">
          <div className="flex items-center justify-between gap-3">
            <div className="flex min-w-0 items-center gap-1">
              {beat !== 'pick' ? (
                <IconButton
                  icon="arrow-left"
                  label="Back a step"
                  size="sm"
                  disabled={busy}
                  onClick={() => setBeat(beat === 'file' ? 'frame' : 'pick')}
                />
              ) : null}
              <h2 className="truncate font-display text-title1 text-ink">{BEAT_TITLES[beat]}</h2>
            </div>
            <span className="shrink-0 text-caption text-ink-3">
              {BEAT_INDEX[beat] + 1} / 3 · {photos.length}/{MAX_PHOTOS}
            </span>
          </div>

          <div className="mt-4">
            {beat === 'pick' ? (
              <PickGrid
                photos={photos.map((photo) => ({
                  id: photo.id,
                  url: photo.url,
                  pending: photo.status === 'decoding',
                  failed: photo.status === 'failed',
                }))}
                onAdd={addFiles}
                onRemove={removePhoto}
                max={MAX_PHOTOS}
                disabled={busy}
              />
            ) : null}

            {beat === 'frame' ? (
              <FrameBeat
                photos={photos}
                currentId={frameId}
                onSelect={setFrameId}
                onCropChange={setCrop}
                onPreset={applyPreset}
                onRotate={rotatePhoto}
                disabled={busy}
              />
            ) : null}

            {beat === 'file' ? (
              <div className="flex flex-col gap-5">
                {/* Photo tray — tap a thumb to go reframe it. */}
                <div className="flex items-center gap-2 overflow-x-auto pb-1">
                  {photos.map((photo, index) => (
                    <button
                      key={photo.id}
                      type="button"
                      disabled={busy}
                      aria-label={`Reframe photo ${index + 1}`}
                      onClick={() => {
                        setFrameId(photo.id);
                        setBeat('frame');
                      }}
                      className="focus-ring relative size-16 shrink-0 overflow-hidden rounded-md border border-line"
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
                      {photo.status === 'processing' || photo.status === 'uploading' ? (
                        <span className="absolute inset-x-1 bottom-1">
                          <ProgressBar
                            value={photo.status === 'processing' ? 0 : photo.progress}
                            label={`Uploading photo ${index + 1}`}
                          />
                        </span>
                      ) : photo.status === 'done' ? (
                        <span className="absolute bottom-1 right-1 grid size-5 place-items-center rounded-full bg-scrim text-success">
                          <Icon name="check" size="xs" />
                        </span>
                      ) : photo.status === 'failed' ? (
                        <span
                          className="absolute bottom-1 right-1 grid size-5 place-items-center rounded-full bg-scrim text-danger"
                          title={photo.error ?? 'Upload failed'}
                        >
                          <Icon name="alert" size="xs" />
                        </span>
                      ) : null}
                    </button>
                  ))}
                  <button
                    type="button"
                    disabled={busy || photos.length >= MAX_PHOTOS}
                    onClick={() => trayInput.current?.click()}
                    aria-label="Add more photos"
                    className={cn(
                      'focus-ring grid size-16 shrink-0 place-items-center rounded-md',
                      'border-2 border-dashed border-line text-ink-3 hover:text-ink',
                      'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
                    )}
                  >
                    <Icon name="plus" size="lg" />
                  </button>
                  <input
                    ref={trayInput}
                    type="file"
                    accept={ACCEPT_ATTRIBUTE}
                    multiple
                    className="sr-only"
                    onChange={(event) => {
                      const files = [...(event.target.files ?? [])].filter((file) =>
                        file.type.startsWith('image/'),
                      );
                      if (files.length > 0) addFiles(files);
                      event.target.value = '';
                    }}
                  />
                </div>

                <TextField
                  label="Title"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  required
                  maxLength={120}
                  placeholder="Gojo — Vol.11 cover"
                  disabled={busy}
                />

                <div>
                  <h3 className="text-label uppercase tracking-widest text-ink-3">Destination</h3>
                  <p className="mb-2 mt-1 text-caption text-ink-2">
                    Shelf first, then a group inside it. Items can sit directly on a shelf.
                  </p>
                  {shelfPicker}
                  {collectionId ? (
                    <div className="mt-4">
                      <ChipGroup label="Group">
                        <Chip
                          selected={subcollectionId === ''}
                          disabled={busy}
                          onClick={() => setSubcollectionId('')}
                        >
                          No group
                        </Chip>
                        {groups.map((group) => (
                          <Chip
                            key={group.id}
                            selected={subcollectionId === group.id}
                            disabled={busy}
                            onClick={() => setSubcollectionId(group.id)}
                          >
                            {group.title}
                          </Chip>
                        ))}
                        {!newGroupOpen ? (
                          <Chip icon="plus" disabled={busy} onClick={() => setNewGroupOpen(true)}>
                            New group
                          </Chip>
                        ) : null}
                      </ChipGroup>
                      {newGroupOpen ? (
                        <div className="mt-2 flex items-center gap-2">
                          <TextField
                            label="New group name"
                            labelHidden
                            autoFocus
                            value={newGroupName}
                            maxLength={80}
                            placeholder="JJK"
                            disabled={newGroupBusy}
                            onChange={(event) => setNewGroupName(event.target.value)}
                            onKeyDown={(event) => {
                              if (event.key === 'Enter') {
                                event.preventDefault();
                                void quickCreateGroup();
                              }
                            }}
                            className="flex-1"
                          />
                          <Button
                            loading={newGroupBusy}
                            disabled={!newGroupName.trim()}
                            onClick={() => void quickCreateGroup()}
                          >
                            Add
                          </Button>
                          <Button
                            variant="ghost"
                            disabled={newGroupBusy}
                            onClick={() => {
                              setNewGroupOpen(false);
                              setNewGroupName('');
                            }}
                          >
                            Cancel
                          </Button>
                        </div>
                      ) : null}
                    </div>
                  ) : null}
                </div>

                <SelectField
                  label="Visibility"
                  value={itemVisibility}
                  disabled={busy}
                  onChange={(event) => setItemVisibility(event.target.value as Visibility | '')}
                  hint="Inheriting follows the group (or the shelf) wherever it goes."
                >
                  <option value="">
                    {selectedGroupName ? `Same as ${selectedGroupName}` : 'Same as the shelf'}
                  </option>
                  {VISIBILITIES.map((value) => (
                    <option key={value} value={value}>
                      {VISIBILITY_LABELS[value]}
                    </option>
                  ))}
                </SelectField>

                <button
                  type="button"
                  onClick={() => setShowDetails((value) => !value)}
                  aria-expanded={showDetails}
                  className={cn(
                    'focus-ring flex items-center gap-3 rounded-md border border-line',
                    'bg-surface-1 px-4 py-3 text-left transition-colors dur-fast hover:bg-surface-2',
                  )}
                >
                  <Icon name="sliders" size="md" className="text-ink-2" />
                  <span className="flex-1 text-body-strong text-ink">
                    {showDetails ? 'Details' : 'Add details'}
                  </span>
                  <Icon
                    name="chevron-down"
                    size="md"
                    className={cn(
                      'text-ink-3 transition-transform dur-fast',
                      showDetails && 'rotate-180',
                    )}
                  />
                </button>

                {showDetails ? (
                  <div className="flex flex-col gap-5">
                    <TextArea
                      label="Description"
                      value={description}
                      onChange={(event) => setDescription(event.target.value)}
                      maxLength={1000}
                      showCount
                      rows={3}
                      placeholder="Condition is honest — some shelf wear, no cracks."
                      disabled={busy}
                    />
                    <fieldset className="grid gap-4 sm:grid-cols-2">
                      <legend className="mb-2 text-label uppercase tracking-widest text-ink-3">
                        Details
                      </legend>
                      <TextField
                        label="Brand or maker"
                        value={brand}
                        onChange={(event) => setBrand(event.target.value)}
                        maxLength={80}
                        disabled={busy}
                      />
                      <TextField
                        label="Model"
                        value={model}
                        onChange={(event) => setModel(event.target.value)}
                        maxLength={80}
                        disabled={busy}
                      />
                      <TextField
                        label="Year"
                        type="number"
                        inputMode="numeric"
                        value={year}
                        onChange={(event) => setYear(event.target.value)}
                        min={1000}
                        max={new Date().getFullYear() + 1}
                        disabled={busy}
                      />
                      <TextField
                        label="Condition"
                        value={condition}
                        onChange={(event) => setCondition(event.target.value)}
                        placeholder="Mint, near mint, played…"
                        maxLength={40}
                        disabled={busy}
                      />
                      <TextField
                        label="Rarity"
                        value={rarity}
                        onChange={(event) => setRarity(event.target.value)}
                        placeholder="1 of 500, chase, common…"
                        maxLength={40}
                        disabled={busy}
                      />
                      <TextField
                        label="Where you got it"
                        value={acquisitionPlace}
                        onChange={(event) => setAcquisitionPlace(event.target.value)}
                        maxLength={80}
                        disabled={busy}
                      />
                      <TextField
                        label="When you got it"
                        type="date"
                        value={acquisitionDate}
                        onChange={(event) => setAcquisitionDate(event.target.value)}
                        disabled={busy}
                      />
                      <div className="grid grid-cols-[1fr_auto] gap-2">
                        <TextField
                          label="Price paid"
                          type="number"
                          inputMode="decimal"
                          step="0.01"
                          min={0}
                          value={purchasePrice}
                          onChange={(event) => setPurchasePrice(event.target.value)}
                          disabled={busy}
                        />
                        <TextField
                          label="Currency"
                          value={currency}
                          onChange={(event) => setCurrency(event.target.value.toUpperCase())}
                          maxLength={3}
                          placeholder="AUD"
                          fieldClassName="w-20 uppercase"
                          disabled={busy}
                        />
                      </div>
                    </fieldset>

                    {photos.length > 0 ? (
                      <div>
                        <h3 className="text-label uppercase tracking-widest text-ink-3">
                          Alt text
                        </h3>
                        <p className="mb-3 mt-1 text-caption text-ink-2">
                          Describe each photo for people who cannot see it.
                        </p>
                        <ul className="flex flex-col gap-2">
                          {photos.map((photo, index) => (
                            <li key={photo.id} className="flex items-center gap-3">
                              <span className="size-10 shrink-0 overflow-hidden rounded-sm border border-line-subtle">
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
                                  <span className="block size-full bg-skeleton" />
                                )}
                              </span>
                              <TextField
                                label={`Alt text for photo ${index + 1}`}
                                labelHidden
                                value={photo.altText}
                                placeholder={`Describe photo ${index + 1}`}
                                maxLength={160}
                                disabled={busy}
                                onChange={(event) =>
                                  patchPhoto(photo.id, { altText: event.target.value })
                                }
                                className="flex-1"
                                fieldClassName="h-9 text-caption"
                              />
                            </li>
                          ))}
                        </ul>
                      </div>
                    ) : null}

                    {tagsSection}
                  </div>
                ) : null}

                <p className="text-caption text-ink-3">
                  Photos are cropped, slimmed down and hashed in your browser when you save —
                  nothing uploads until then.
                </p>
              </div>
            ) : null}
          </div>

          {inlineError ? (
            <p
              role="alert"
              className="mt-4 flex items-center gap-2 rounded-md border border-danger/40 bg-danger-subtle px-4 py-3 text-callout text-danger"
            >
              <Icon name="alert" size="sm" />
              {inlineError}
            </p>
          ) : null}

          {/* Save bar — one primary action per beat, like mobile's CreateSaveBar. */}
          <div
            className={cn(
              'sticky z-10 mt-6 -mx-4 border-t border-line bg-surface-1 px-4 py-3 sm:-mx-6 sm:px-6',
              'bottom-[calc(var(--k-bottombar-h)+env(safe-area-inset-bottom))] md:bottom-0',
            )}
          >
            {busy ? (
              <div className="mb-2">
                <ProgressBar value={overallProgress} label="Overall upload progress" />
              </div>
            ) : null}
            <div className="flex flex-wrap items-center gap-3">
              {beat === 'pick' ? (
                <>
                  <Button
                    disabled={photos.length === 0 || decoding}
                    iconRight="chevron-right"
                    onClick={() => {
                      setFrameId((current) => current ?? photos[0]?.id ?? null);
                      setBeat('frame');
                    }}
                  >
                    {photos.length === 0
                      ? 'Pick a photo to start'
                      : `Frame ${photos.length} photo${photos.length === 1 ? '' : 's'}`}
                  </Button>
                  {photos.length === 0 ? (
                    <span className="text-caption text-ink-3">
                      An item needs at least one photo.
                    </span>
                  ) : null}
                </>
              ) : beat === 'frame' ? (
                <Button iconRight="chevron-right" onClick={() => setBeat('file')}>
                  Next: file it
                </Button>
              ) : (
                <>
                  <Button
                    loading={busy}
                    disabled={!canSaveItem}
                    iconLeft="plus"
                    onClick={() => void saveItem()}
                  >
                    {createdItemId ? 'Finish uploading' : 'Add item'}
                  </Button>
                  <Button variant="ghost" onClick={resetDraft} disabled={busy}>
                    Clear
                  </Button>
                  {busy ? (
                    <span className="text-caption text-ink-3">
                      {doneCount} of {photos.length} uploaded
                    </span>
                  ) : null}
                </>
              )}
            </div>
          </div>
        </section>
      ) : (
        <form
          className="mt-6 flex max-w-xl flex-col gap-5"
          onSubmit={(event) => {
            event.preventDefault();
            void saveEntity();
          }}
        >
          {mode === 'subcollection' ? (
            <div>
              <h3 className="text-label uppercase tracking-widest text-ink-3">Collection</h3>
              <p className="mb-2 mt-1 text-caption text-ink-2">
                Visibility inherits down from the shelf unless you override it.
              </p>
              {shelfPicker}
            </div>
          ) : null}

          <TextField
            label="Name"
            value={name}
            onChange={(event) => setName(event.target.value)}
            required
            maxLength={120}
            placeholder={mode === 'collection' ? 'Anime' : 'Jujutsu Kaisen'}
            disabled={busy}
          />

          <TextArea
            label="Description"
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            maxLength={1000}
            showCount
            rows={3}
            placeholder="What is it, and why does it matter to you?"
            disabled={busy}
          />

          {mode === 'collection' ? (
            <SelectField
              label="Visibility"
              value={visibility}
              disabled={busy}
              onChange={(event) => setVisibility(event.target.value as Visibility)}
              hint="Subcollections and items inherit this unless they set their own."
            >
              {VISIBILITIES.map((value) => (
                <option key={value} value={value}>
                  {VISIBILITY_LABELS[value]}
                </option>
              ))}
            </SelectField>
          ) : null}

          {tagsSection}

          {inlineError ? (
            <p role="alert" className="flex items-center gap-2 text-callout text-danger">
              <Icon name="alert" size="sm" />
              {inlineError}
            </p>
          ) : null}

          <div className="flex flex-wrap items-center gap-3 border-t border-line-subtle pt-5">
            <Button type="submit" loading={busy} iconLeft="plus">
              Create {MODE_LABELS[mode].toLowerCase()}
            </Button>
          </div>
        </form>
      )}
    </div>
  );
}

/**
 * Tags are secondary metadata: a tag failure must never undo a create that has
 * already succeeded, so it degrades to a warning.
 */
async function safeTags(
  client: Parameters<typeof attachTags>[0],
  entityType: 'collection' | 'subcollection' | 'item',
  entityId: string,
  userId: string,
  tags: string[],
  onError: (error: unknown) => void,
): Promise<void> {
  if (tags.length === 0) return;
  try {
    await attachTags(client, { entityType, entityId, userId, tags });
  } catch (error) {
    onError(error);
  }
}
