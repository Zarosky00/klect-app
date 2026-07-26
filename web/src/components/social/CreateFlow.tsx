'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { VISIBILITY_LABELS, type Visibility } from '@/lib/entities';
import { collectionHref, itemHref, subcollectionHref } from '@/lib/routes';
import { Button } from '@/components/ui/Button';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { Icon } from '@/components/ui/Icon';
import { TextArea, TextField } from '@/components/ui/TextField';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { SelectField } from './Field';
import { UploadDropzone, releaseStaged, type StagedPhoto } from './UploadDropzone';
import {
  assertWithinBucketLimit,
  prepareImage,
  releasePreview,
  uploadObject,
} from './media';
import {
  attachTags,
  createCollection,
  createItem,
  createSubcollection,
  insertItemMedia,
  listSubcollectionSummaries,
  type EntitySummary,
} from './queries';

/**
 * Create: a collection, a subcollection inside one, or an item with photos.
 *
 * The ordering that makes this safe: the item's UUID is generated **here**, so
 * photos can upload to `{user_id}/{item_id}/{uuid}.webp` while the form is
 * still being filled in — and the `items` row plus its `item_media` rows are
 * only written once every byte has landed. Kill the tab mid-upload and you
 * leave a few unreferenced objects in a bucket; you never leave a broken row.
 * (CHECKLIST A: "app kill mid-upload doesn't orphan rows".)
 */

type Mode = 'collection' | 'subcollection' | 'item';

const MODE_LABELS: Record<Mode, string> = {
  collection: 'Collection',
  subcollection: 'Subcollection',
  item: 'Item',
};

const MODE_BLURB: Record<Mode, string> = {
  collection: 'A shelf you own — "Anime", "Resin", "Cameras".',
  subcollection: 'A themed group inside a collection — "JJK", "One Piece".',
  item: 'A thing, with one to many photos.',
};

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

  const [mode, setMode] = useState<Mode>(collections.length === 0 ? 'collection' : initialMode);
  const [busy, setBusy] = useState(false);

  /* shared fields */
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [visibility, setVisibility] = useState<Visibility>('public');
  const [collectionId, setCollectionId] = useState(
    initialCollectionId ?? collections[0]?.id ?? '',
  );
  const [subcollections, setSubcollections] = useState<EntitySummary[]>([]);
  const [subcollectionId, setSubcollectionId] = useState('');

  /* item-only fields */
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

  /* photos */
  const [itemId, setItemId] = useState(() => crypto.randomUUID());
  const [photos, setPhotos] = useState<StagedPhoto[]>([]);

  useEffect(() => {
    if (mode !== 'item' && mode !== 'subcollection') return;
    if (!collectionId) {
      setSubcollections([]);
      return;
    }
    let active = true;
    void listSubcollectionSummaries(supabase, collectionId)
      .then((rows) => {
        if (active) setSubcollections(rows);
      })
      .catch(() => {
        if (active) setSubcollections([]);
      });
    return () => {
      active = false;
    };
  }, [collectionId, mode, supabase]);

  /* ── photo staging ──────────────────────────────────────────────────────── */

  const uploadOne = useCallback(
    async (photo: StagedPhoto) => {
      if (!photo.prepared || !user) return;
      const {
        data: { session },
      } = await supabase.auth.getSession();
      const accessToken = session?.access_token;
      if (!accessToken) throw new Error('Your session expired. Sign in again.');

      setPhotos((current) =>
        current.map((entry) =>
          entry.id === photo.id
            ? { ...entry, status: 'uploading', progress: 0, error: null }
            : entry,
        ),
      );

      try {
        await uploadObject({
          accessToken,
          bucket: 'media',
          path: photo.path,
          body: photo.prepared.blob,
          contentType: photo.prepared.mimeType,
          upsert: true,
          onProgress: (fraction) =>
            setPhotos((current) =>
              current.map((entry) =>
                entry.id === photo.id ? { ...entry, progress: fraction } : entry,
              ),
            ),
        });
        setPhotos((current) =>
          current.map((entry) =>
            entry.id === photo.id
              ? { ...entry, status: 'done', progress: 1, error: null }
              : entry,
          ),
        );
      } catch (thrown) {
        setPhotos((current) =>
          current.map((entry) =>
            entry.id === photo.id
              ? {
                  ...entry,
                  status: 'failed',
                  error: thrown instanceof Error ? thrown.message : 'Upload failed',
                }
              : entry,
          ),
        );
      }
    },
    [supabase, user],
  );

  const addFiles = useCallback(
    async (files: FileList | File[]) => {
      if (!user) return;
      const list = [...files];
      for (const file of list) {
        const id = crypto.randomUUID();
        const path = `${user.id}/${itemId}/${crypto.randomUUID()}.webp`;

        setPhotos((current) =>
          current.length >= MAX_PHOTOS
            ? current
            : [
                ...current,
                {
                  id,
                  prepared: null,
                  path,
                  progress: 0,
                  status: 'preparing',
                  error: null,
                  altText: '',
                },
              ],
        );

        try {
          assertWithinBucketLimit('media', file.size);
          const prepared = await prepareImage(file);
          const staged: StagedPhoto = {
            id,
            prepared,
            path,
            progress: 0,
            status: 'uploading',
            error: null,
            altText: '',
          };
          setPhotos((current) =>
            current.map((entry) => (entry.id === id ? staged : entry)),
          );
          await uploadOne(staged);
        } catch (thrown) {
          setPhotos((current) => current.filter((entry) => entry.id !== id));
          fromError(thrown);
        }
      }
    },
    [fromError, itemId, uploadOne, user],
  );

  const removePhoto = useCallback((id: string) => {
    setPhotos((current) => {
      const target = current.find((entry) => entry.id === id);
      if (target?.prepared) releasePreview(target.prepared);
      return current.filter((entry) => entry.id !== id);
    });
  }, []);

  const movePhoto = useCallback((id: string, direction: -1 | 1) => {
    setPhotos((current) => {
      const index = current.findIndex((entry) => entry.id === id);
      const next = index + direction;
      if (index < 0 || next < 0 || next >= current.length) return current;
      const copy = [...current];
      const a = copy[index];
      const b = copy[next];
      if (!a || !b) return current;
      copy[index] = b;
      copy[next] = a;
      return copy;
    });
  }, []);

  const setAltText = useCallback((id: string, value: string) => {
    setPhotos((current) =>
      current.map((entry) => (entry.id === id ? { ...entry, altText: value } : entry)),
    );
  }, []);

  const retryPhoto = useCallback(
    (id: string) => {
      const photo = photos.find((entry) => entry.id === id);
      if (photo) void uploadOne(photo);
    },
    [photos, uploadOne],
  );

  /* ── tags ───────────────────────────────────────────────────────────────── */

  const commitTag = useCallback(() => {
    const value = tagDraft.trim().replace(/^#/, '');
    if (!value) return;
    setTags((current) => (current.includes(value) ? current : [...current, value].slice(0, 12)));
    setTagDraft('');
  }, [tagDraft]);

  /* ── submit ─────────────────────────────────────────────────────────────── */

  const uploading = photos.some(
    (photo) => photo.status === 'uploading' || photo.status === 'preparing',
  );
  const failed = photos.filter((photo) => photo.status === 'failed');

  const resetDraft = useCallback(() => {
    releaseStaged(photos);
    setPhotos([]);
    setItemId(crypto.randomUUID());
    setName('');
    setDescription('');
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
  }, [photos]);

  const submit = useCallback(async () => {
    if (!user) return;
    if (!name.trim()) {
      errorToast('Give it a name first');
      return;
    }
    if (mode !== 'collection' && !collectionId) {
      errorToast('Pick a collection to put this in');
      return;
    }
    if (failed.length > 0) {
      errorToast(`${failed.length} photo(s) failed to upload`, 'Retry or remove them first.');
      return;
    }

    setBusy(true);
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
        resetDraft();
        router.push(collectionHref(row.id));
        return;
      }

      if (mode === 'subcollection') {
        const row = await createSubcollection(supabase, {
          userId: user.id,
          collectionId,
          name: name.trim(),
          description: description.trim() || null,
          visibility: null,
        });
        await safeTags(supabase, 'subcollection', row.id, user.id, tags, fromError);
        success('Subcollection created');
        resetDraft();
        router.push(subcollectionHref(row.id));
        return;
      }

      // Item: every byte is already in the bucket by this point.
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
        visibility: null,
      });

      const uploaded = photos.filter((photo) => photo.status === 'done' && photo.prepared);
      if (uploaded.length > 0) {
        await insertItemMedia(
          supabase,
          uploaded.map((photo, index) => ({
            itemId: row.id,
            userId: user.id,
            storagePath: photo.path,
            width: photo.prepared?.width ?? 0,
            height: photo.prepared?.height ?? 0,
            blurhash: photo.prepared?.blurhash ?? '',
            dominantColor: photo.prepared?.dominantColor ?? null,
            mimeType: photo.prepared?.mimeType ?? 'image/webp',
            bytes: photo.prepared?.bytes ?? 0,
            altText: photo.altText.trim() || null,
            position: index,
          })),
        );
      }

      await safeTags(supabase, 'item', row.id, user.id, tags, fromError);
      success('Item added', uploaded.length > 0 ? `${uploaded.length} photo(s) attached.` : undefined);
      resetDraft();
      router.push(itemHref(row.id));
    } catch (thrown) {
      fromError(thrown);
    } finally {
      setBusy(false);
    }
  }, [
    acquisitionDate,
    acquisitionPlace,
    brand,
    collectionId,
    condition,
    currency,
    description,
    errorToast,
    failed.length,
    fromError,
    itemId,
    mode,
    model,
    name,
    photos,
    purchasePrice,
    rarity,
    resetDraft,
    router,
    subcollectionId,
    success,
    supabase,
    tags,
    user,
    visibility,
    year,
  ]);

  const nameLabel = mode === 'item' ? 'Title' : 'Name';
  const parentOptions = useMemo(() => collections, [collections]);

  return (
    <div className="content-max px-4 py-8 sm:px-6">
      <header>
        <h1 className="font-display text-display2 text-ink">Create</h1>
        <p className="mt-1 readable-max text-callout text-ink-2 md:mx-0">
          Collection, then subcollection, then item. Every level is independently
          likeable, saveable and repostable — so it is worth putting things in the right
          one.
        </p>
      </header>

      <div
        role="tablist"
        aria-label="What to create"
        className="mt-6 flex flex-wrap gap-2"
      >
        {(Object.keys(MODE_LABELS) as Mode[]).map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={mode === value}
            disabled={value !== 'collection' && collections.length === 0}
            onClick={() => setMode(value)}
            className={
              mode === value
                ? 'focus-ring rounded-lg border border-accent bg-accent-subtle px-4 py-3 text-left'
                : 'focus-ring rounded-lg border border-line bg-surface-1 px-4 py-3 text-left transition-colors dur-fast hover:bg-surface-2 disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]'
            }
          >
            <span className="block text-body-strong text-ink">{MODE_LABELS[value]}</span>
            <span className="block text-caption text-ink-3">{MODE_BLURB[value]}</span>
          </button>
        ))}
      </div>

      {collections.length === 0 && mode !== 'collection' ? (
        <p className="mt-4 flex items-center gap-2 rounded-md border border-line bg-surface-2 px-4 py-3 text-callout text-ink-2">
          <Icon name="alert" size="sm" />
          Create a collection first — subcollections and items need a shelf to live on.
        </p>
      ) : null}

      <form
        className="mt-8 flex flex-col gap-6"
        onSubmit={(event) => {
          event.preventDefault();
          void submit();
        }}
      >
        {mode !== 'collection' ? (
          <SelectField
            label="Collection"
            value={collectionId}
            required
            onChange={(event) => {
              setCollectionId(event.target.value);
              setSubcollectionId('');
            }}
            hint="Visibility inherits down from here unless you override it."
          >
            {parentOptions.map((collection) => (
              <option key={collection.id} value={collection.id}>
                {collection.title}
              </option>
            ))}
          </SelectField>
        ) : null}

        {mode === 'item' ? (
          <SelectField
            label="Subcollection"
            value={subcollectionId}
            onChange={(event) => setSubcollectionId(event.target.value)}
            hint={
              subcollections.length === 0
                ? 'This collection has no subcollections yet — that is fine.'
                : 'Optional. Items can sit directly on a collection.'
            }
          >
            <option value="">No subcollection</option>
            {subcollections.map((subcollection) => (
              <option key={subcollection.id} value={subcollection.id}>
                {subcollection.title}
              </option>
            ))}
          </SelectField>
        ) : null}

        <TextField
          label={nameLabel}
          value={name}
          onChange={(event) => setName(event.target.value)}
          required
          maxLength={120}
          placeholder={
            mode === 'collection' ? 'Anime' : mode === 'subcollection' ? 'Jujutsu Kaisen' : 'Gojo — Vol.11 cover'
          }
        />

        <TextArea
          label="Description"
          value={description}
          onChange={(event) => setDescription(event.target.value)}
          maxLength={1000}
          showCount
          rows={3}
          placeholder="What is it, and why does it matter to you?"
        />

        {mode === 'collection' ? (
          <SelectField
            label="Visibility"
            value={visibility}
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

        {mode === 'item' ? (
          <>
            <fieldset className="grid gap-4 sm:grid-cols-2">
              <legend className="mb-2 text-label uppercase tracking-widest text-ink-3">
                Details
              </legend>
              <TextField
                label="Brand or maker"
                value={brand}
                onChange={(event) => setBrand(event.target.value)}
                maxLength={80}
              />
              <TextField
                label="Model"
                value={model}
                onChange={(event) => setModel(event.target.value)}
                maxLength={80}
              />
              <TextField
                label="Year"
                type="number"
                inputMode="numeric"
                value={year}
                onChange={(event) => setYear(event.target.value)}
                min={1000}
                max={new Date().getFullYear() + 1}
              />
              <TextField
                label="Condition"
                value={condition}
                onChange={(event) => setCondition(event.target.value)}
                placeholder="Mint, near mint, played…"
                maxLength={40}
              />
              <TextField
                label="Rarity"
                value={rarity}
                onChange={(event) => setRarity(event.target.value)}
                placeholder="1 of 500, chase, common…"
                maxLength={40}
              />
              <TextField
                label="Where you got it"
                value={acquisitionPlace}
                onChange={(event) => setAcquisitionPlace(event.target.value)}
                maxLength={80}
              />
              <TextField
                label="When you got it"
                type="date"
                value={acquisitionDate}
                onChange={(event) => setAcquisitionDate(event.target.value)}
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
                />
                <TextField
                  label="Currency"
                  value={currency}
                  onChange={(event) => setCurrency(event.target.value.toUpperCase())}
                  maxLength={3}
                  placeholder="AUD"
                  fieldClassName="w-20 uppercase"
                />
              </div>
            </fieldset>

            <section>
              <h2 className="text-label uppercase tracking-widest text-ink-3">Photos</h2>
              <p className="mb-3 mt-1 text-caption text-ink-2">
                The first photo becomes the cover. Drag to reorder, or use the arrows.
              </p>
              <UploadDropzone
                photos={photos}
                onAdd={(files) => void addFiles(files)}
                onRemove={removePhoto}
                onMove={movePhoto}
                onAltText={setAltText}
                onRetry={retryPhoto}
                max={MAX_PHOTOS}
                disabled={busy}
              />
            </section>
          </>
        ) : null}

        <section>
          <h2 className="text-label uppercase tracking-widest text-ink-3">Tags</h2>
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
        </section>

        <div className="flex flex-wrap items-center gap-3 border-t border-line-subtle pt-6">
          <Button
            type="submit"
            loading={busy}
            disabled={uploading || (mode !== 'collection' && collections.length === 0)}
            iconLeft="plus"
          >
            {uploading ? 'Waiting for uploads…' : `Create ${MODE_LABELS[mode].toLowerCase()}`}
          </Button>
          <Button variant="ghost" onClick={resetDraft} disabled={busy}>
            Clear
          </Button>
          {failed.length > 0 ? (
            <span className="flex items-center gap-1 text-caption text-danger">
              <Icon name="alert" size="xs" />
              {failed.length} photo(s) need attention
            </span>
          ) : null}
        </div>
      </form>
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
