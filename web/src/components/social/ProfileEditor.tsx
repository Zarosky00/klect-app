'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { updateProfile, usernameAvailable } from '@/lib/api';
import { cn } from '@/lib/cn';
import { isValidUsername, normaliseUsername } from '@/lib/format';
import { avatarUrl, bannerUrl } from '@/lib/storage';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { Modal } from '@/components/ui/Modal';
import { TextArea, TextField } from '@/components/ui/TextField';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import type { ProfileRow } from '@/lib/types';
import {
  MAX_AVATAR_EDGE,
  MAX_BANNER_EDGE,
  assertWithinBucketLimit,
  mediaObjectKey,
  prepareImage,
  releasePreview,
  uploadObject,
  type PreparedImage,
} from './media';

/**
 * Own-profile editing. Avatar and banner are downscaled and re-encoded in the
 * browser, then uploaded to `{user_id}/{uuid}.webp` in their own bucket — the
 * storage policy enforces that first segment, so nothing else is possible.
 *
 * The handle is checked for availability before the save round trip, because
 * finding out from a unique-violation toast is a bad way to learn your name is
 * taken.
 */

const BIO_MAX = 280;

export interface ProfileEditorProps {
  open: boolean;
  onClose: () => void;
  profile: ProfileRow;
}

type ImageSlot = 'avatar' | 'banner';

interface SlotState {
  prepared: PreparedImage | null;
  progress: number;
  busy: boolean;
}

const emptySlot: SlotState = { prepared: null, progress: 0, busy: false };

export function ProfileEditor({ open, onClose, profile }: ProfileEditorProps) {
  const router = useRouter();
  const { supabase } = useSession();
  const { success, fromError, error: errorToast } = useToast();

  const [displayName, setDisplayName] = useState(profile.display_name);
  const [username, setUsername] = useState(profile.username);
  const [bio, setBio] = useState(profile.bio ?? '');
  const [location, setLocation] = useState(profile.location ?? '');
  const [website, setWebsite] = useState(profile.website ?? '');
  const [handleError, setHandleError] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);
  const [saving, setSaving] = useState(false);

  const [avatar, setAvatar] = useState<SlotState>(emptySlot);
  const [banner, setBanner] = useState<SlotState>(emptySlot);
  const avatarInput = useRef<HTMLInputElement | null>(null);
  const bannerInput = useRef<HTMLInputElement | null>(null);

  // Reset whenever the dialog re-opens, so a cancelled edit never leaks forward.
  useEffect(() => {
    if (!open) return;
    setDisplayName(profile.display_name);
    setUsername(profile.username);
    setBio(profile.bio ?? '');
    setLocation(profile.location ?? '');
    setWebsite(profile.website ?? '');
    setHandleError(null);
    setAvatar(emptySlot);
    setBanner(emptySlot);
  }, [open, profile]);

  // Debounced availability check — never on every keystroke's round trip.
  useEffect(() => {
    const candidate = normaliseUsername(username);
    if (candidate === profile.username) {
      setHandleError(null);
      return;
    }
    if (!isValidUsername(candidate)) {
      setHandleError('3–24 characters: lowercase letters, numbers and underscores.');
      return;
    }
    setChecking(true);
    const timer = setTimeout(() => {
      void usernameAvailable(supabase, candidate)
        .then((free) => setHandleError(free ? null : 'That handle is taken.'))
        .catch(() => setHandleError(null))
        .finally(() => setChecking(false));
    }, 350);
    return () => {
      clearTimeout(timer);
      setChecking(false);
    };
  }, [profile.username, supabase, username]);

  const pick = useCallback(
    async (slot: ImageSlot, file: File | undefined) => {
      if (!file) return;
      const setSlot = slot === 'avatar' ? setAvatar : setBanner;
      try {
        assertWithinBucketLimit(slot === 'avatar' ? 'avatars' : 'banners', file.size);
        setSlot({ ...emptySlot, busy: true });
        const prepared = await prepareImage(file, {
          maxEdge: slot === 'avatar' ? MAX_AVATAR_EDGE : MAX_BANNER_EDGE,
        });
        setSlot({ prepared, progress: 0, busy: false });
      } catch (thrown) {
        setSlot(emptySlot);
        fromError(thrown);
      }
    },
    [fromError],
  );

  const uploadSlot = useCallback(
    async (slot: ImageSlot, state: SlotState, accessToken: string): Promise<string | null> => {
      if (!state.prepared) return null;
      const bucket = slot === 'avatar' ? 'avatars' : 'banners';
      const path = mediaObjectKey(profile.id);
      const setSlot = slot === 'avatar' ? setAvatar : setBanner;

      await uploadObject({
        accessToken,
        bucket,
        path,
        body: state.prepared.blob,
        contentType: state.prepared.mimeType,
        onProgress: (fraction) =>
          setSlot((current) => ({ ...current, progress: fraction, busy: fraction < 1 })),
      });
      return path;
    },
    [profile.id],
  );

  const save = useCallback(async () => {
    const candidate = normaliseUsername(username);
    if (handleError || !displayName.trim()) {
      errorToast('Check the highlighted fields');
      return;
    }
    setSaving(true);
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();
      const accessToken = session?.access_token;
      if (!accessToken) throw new Error('Your session expired. Sign in again.');

      const [avatarPath, bannerPath] = await Promise.all([
        uploadSlot('avatar', avatar, accessToken),
        uploadSlot('banner', banner, accessToken),
      ]);

      await updateProfile(supabase, profile.id, {
        display_name: displayName.trim(),
        username: candidate,
        bio: bio.trim() || null,
        location: location.trim() || null,
        website: website.trim() || null,
        ...(avatarPath ? { avatar_path: avatarPath } : {}),
        ...(bannerPath ? { banner_path: bannerPath } : {}),
      });

      if (avatar.prepared) releasePreview(avatar.prepared);
      if (banner.prepared) releasePreview(banner.prepared);

      success('Profile saved');
      onClose();
      if (candidate !== profile.username) router.replace(`/u/${candidate}`);
      else router.refresh();
    } catch (thrown) {
      fromError(thrown);
    } finally {
      setSaving(false);
    }
  }, [
    avatar,
    banner,
    bio,
    displayName,
    errorToast,
    fromError,
    handleError,
    location,
    onClose,
    profile.id,
    profile.username,
    router,
    success,
    supabase,
    uploadSlot,
    username,
    website,
  ]);

  const bannerPreview = banner.prepared?.previewUrl ?? bannerUrl(profile.banner_path);
  const avatarPreview = avatar.prepared?.previewUrl ?? avatarUrl(profile.avatar_path);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Edit profile"
      description="This is the front door to everything you collect."
      size="md"
      dismissOnBackdrop={!saving}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={() => void save()} loading={saving} disabled={Boolean(handleError)}>
            Save changes
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-6 px-6 py-5">
        <section className="flex flex-col gap-2">
          <span className="text-label text-ink-2">Banner</span>
          <div className="relative overflow-hidden rounded-lg border border-line bg-surface-2">
            <div className="aspect-[3/1] w-full">
              {bannerPreview ? (
                /* eslint-disable-next-line @next/next/no-img-element -- banners
                   come from arbitrary storage hosts; see BlurhashImage. */
                <img src={bannerPreview} alt="" className="size-full object-cover" />
              ) : (
                <div className="grid size-full place-items-center text-ink-3">
                  <Icon name="image" size="xl" />
                </div>
              )}
            </div>
            <div className="absolute inset-x-0 bottom-0 flex items-center gap-2 bg-scrim p-2">
              <Button
                size="sm"
                variant="secondary"
                iconLeft="image"
                onClick={() => bannerInput.current?.click()}
                loading={banner.busy}
              >
                {profile.banner_path || banner.prepared ? 'Replace banner' : 'Add banner'}
              </Button>
              {banner.progress > 0 && banner.progress < 1 ? (
                <ProgressBar value={banner.progress} label="Banner upload" />
              ) : null}
            </div>
          </div>
          <input
            ref={bannerInput}
            type="file"
            accept="image/*"
            className="sr-only"
            onChange={(event) => void pick('banner', event.target.files?.[0])}
          />
        </section>

        <section className="flex items-center gap-4">
          <span className="relative">
            {avatar.prepared ? (
              /* eslint-disable-next-line @next/next/no-img-element -- local
                 preview of a Blob the user just chose. */
              <img
                src={avatarPreview ?? ''}
                alt=""
                className="size-20 rounded-full object-cover"
              />
            ) : (
              <Avatar
                path={profile.avatar_path}
                name={profile.display_name}
                size="xl"
                verified={profile.is_verified}
              />
            )}
          </span>
          <div className="flex flex-col gap-2">
            <Button
              size="sm"
              variant="secondary"
              iconLeft="user"
              onClick={() => avatarInput.current?.click()}
              loading={avatar.busy}
            >
              Change photo
            </Button>
            {avatar.progress > 0 && avatar.progress < 1 ? (
              <ProgressBar value={avatar.progress} label="Avatar upload" />
            ) : (
              <p className="text-caption text-ink-3">
                Square works best. Downscaled and re-encoded before it leaves your device.
              </p>
            )}
          </div>
          <input
            ref={avatarInput}
            type="file"
            accept="image/*"
            className="sr-only"
            onChange={(event) => void pick('avatar', event.target.files?.[0])}
          />
        </section>

        <TextField
          label="Display name"
          value={displayName}
          onChange={(event) => setDisplayName(event.target.value)}
          maxLength={60}
          required
        />

        <TextField
          label="Handle"
          value={username}
          onChange={(event) => setUsername(normaliseUsername(event.target.value))}
          iconLeft="user"
          error={handleError}
          hint={checking ? 'Checking availability…' : 'klect.app/u/your-handle'}
          maxLength={24}
          required
        />

        <TextArea
          label="Bio"
          value={bio}
          onChange={(event) => setBio(event.target.value)}
          maxLength={BIO_MAX}
          showCount
          rows={3}
          placeholder="What do you collect, and why?"
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <TextField
            label="Location"
            value={location}
            onChange={(event) => setLocation(event.target.value)}
            maxLength={80}
          />
          <TextField
            label="Website"
            type="url"
            inputMode="url"
            value={website}
            onChange={(event) => setWebsite(event.target.value)}
            placeholder="https://"
            maxLength={200}
          />
        </div>
      </div>
    </Modal>
  );
}

export function ProgressBar({
  value,
  label,
  className,
}: {
  value: number;
  label: string;
  className?: string;
}) {
  const percent = Math.round(Math.min(1, Math.max(0, value)) * 100);
  return (
    <div
      role="progressbar"
      aria-label={label}
      aria-valuenow={percent}
      aria-valuemin={0}
      aria-valuemax={100}
      className={cn('h-1.5 w-full overflow-hidden rounded-full bg-surface-3', className)}
    >
      <div
        className="h-full rounded-full bg-accent transition-[width] dur-fast ease-standard"
        style={{ width: `${percent}%` }}
      />
    </div>
  );
}
