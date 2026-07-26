'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { updateProfile, usernameAvailable } from '@/lib/api';
import { cn } from '@/lib/cn';
import { isValidUsername, normaliseUsername } from '@/lib/format';
import { profileHref } from '@/lib/routes';
import { bannerUrl } from '@/lib/storage';
import type { ProfileRow } from '@/lib/types';
import { Avatar } from '@/components/ui/Avatar';
import { Button, ButtonLink } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { TextArea, TextField } from '@/components/ui/TextField';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { ProgressBar } from './ProfileEditor';
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
 * The settings twin of `ProfileEditor` — same writes, laid out as a page rather
 * than a dialog, because settings is where people expect to find them.
 */

const BIO_MAX = 280;

interface SlotState {
  prepared: PreparedImage | null;
  progress: number;
  busy: boolean;
}

const emptySlot: SlotState = { prepared: null, progress: 0, busy: false };

export function SettingsProfileForm({ profile }: { profile: ProfileRow }) {
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
    async (slot: 'avatar' | 'banner', file: File | undefined) => {
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

      const upload = async (
        slot: 'avatar' | 'banner',
        state: SlotState,
      ): Promise<string | null> => {
        if (!state.prepared) return null;
        const path = mediaObjectKey(profile.id);
        const setSlot = slot === 'avatar' ? setAvatar : setBanner;
        await uploadObject({
          accessToken,
          bucket: slot === 'avatar' ? 'avatars' : 'banners',
          path,
          body: state.prepared.blob,
          contentType: state.prepared.mimeType,
          onProgress: (fraction) =>
            setSlot((current) => ({ ...current, progress: fraction, busy: fraction < 1 })),
        });
        return path;
      };

      const [avatarPath, bannerPath] = await Promise.all([
        upload('avatar', avatar),
        upload('banner', banner),
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
      setAvatar(emptySlot);
      setBanner(emptySlot);

      success('Profile saved');
      router.refresh();
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
    profile.id,
    router,
    success,
    supabase,
    username,
    website,
  ]);

  const bannerPreview = banner.prepared?.previewUrl ?? bannerUrl(profile.banner_path);

  return (
    <section className="flex flex-col gap-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="font-display text-title1 text-ink">Profile</h2>
          <p className="mt-1 text-callout text-ink-2">
            This is the front door to everything you collect.
          </p>
        </div>
        <ButtonLink
          href={profileHref(profile.username)}
          variant="ghost"
          size="sm"
          iconRight="chevron-right"
        >
          View public profile
        </ButtonLink>
      </header>

      <div className="overflow-hidden rounded-xl border border-line bg-surface-1">
        <div className="relative aspect-[4/1] w-full bg-surface-2">
          {bannerPreview ? (
            /* eslint-disable-next-line @next/next/no-img-element -- banners come
               from arbitrary storage hosts; see BlurhashImage. */
            <img src={bannerPreview} alt="" className="size-full object-cover" />
          ) : (
            <span className="grid size-full place-items-center text-ink-3">
              <Icon name="image" size="xl" />
            </span>
          )}
          <span className="absolute inset-x-0 bottom-0 flex items-center gap-2 bg-scrim p-2">
            <Button
              size="sm"
              variant="secondary"
              iconLeft="image"
              loading={banner.busy}
              onClick={() => bannerInput.current?.click()}
            >
              {profile.banner_path || banner.prepared ? 'Replace banner' : 'Add banner'}
            </Button>
            {banner.progress > 0 && banner.progress < 1 ? (
              <ProgressBar value={banner.progress} label="Banner upload" className="max-w-40" />
            ) : null}
          </span>
        </div>

        <div className="flex flex-wrap items-center gap-4 p-4">
          <span className={cn('relative -mt-12 rounded-full ring-4 ring-surface-1')}>
            {avatar.prepared ? (
              /* eslint-disable-next-line @next/next/no-img-element -- local
                 preview of a Blob the user just chose. */
              <img
                src={avatar.prepared.previewUrl}
                alt=""
                className="size-20 rounded-full object-cover"
              />
            ) : (
              <Avatar
                path={profile.avatar_path}
                name={profile.display_name}
                username={profile.username}
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
              loading={avatar.busy}
              onClick={() => avatarInput.current?.click()}
            >
              Change photo
            </Button>
            {avatar.progress > 0 && avatar.progress < 1 ? (
              <ProgressBar value={avatar.progress} label="Avatar upload" className="max-w-40" />
            ) : (
              <p className="text-caption text-ink-3">
                Downscaled and re-encoded on your device before upload.
              </p>
            )}
          </div>
        </div>
      </div>

      <input
        ref={bannerInput}
        type="file"
        accept="image/*"
        className="sr-only"
        onChange={(event) => void pick('banner', event.target.files?.[0])}
      />
      <input
        ref={avatarInput}
        type="file"
        accept="image/*"
        className="sr-only"
        onChange={(event) => void pick('avatar', event.target.files?.[0])}
      />

      <div className="grid gap-4 sm:grid-cols-2">
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
          hint={checking ? 'Checking availability…' : 'Your profile lives at /u/handle.'}
          maxLength={24}
          required
        />
      </div>

      <TextArea
        label="Bio"
        value={bio}
        onChange={(event) => setBio(event.target.value)}
        maxLength={BIO_MAX}
        showCount
        rows={3}
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

      <div className="flex items-center gap-3 border-t border-line-subtle pt-6">
        <Button onClick={() => void save()} loading={saving} disabled={Boolean(handleError)}>
          Save changes
        </Button>
      </div>
    </section>
  );
}
