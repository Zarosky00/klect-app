'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { TextArea, TextField } from '@/components/ui/TextField';
import {
  completeOnboarding,
  listSuggestedCollectors,
  updateProfile,
  usernameAvailable,
} from '@/lib/api';
import { cn } from '@/lib/cn';
import { compactCount, isValidUsername, normaliseUsername } from '@/lib/format';
import { DEFAULT_SIGNED_IN_ROUTE } from '@/lib/routes';
import type { ProfileRow } from '@/lib/types';
import { useFollowState } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * Three steps, matching the mobile flow:
 *   1. Claim your handle.
 *   2. Say what you collect.
 *   3. Find your people.
 *
 * Only step 1 is compulsory. `profiles.onboarded_at` is stamped at the end,
 * which is what the middleware gate reads.
 */
const STEPS = ['Handle', 'Profile', 'People'] as const;

export function OnboardingFlow() {
  const router = useRouter();
  const { supabase, user, profile } = useSession();
  const { fromError, success } = useToast();

  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [bio, setBio] = useState('');
  const [location, setLocation] = useState('');
  const [website, setWebsite] = useState('');

  useEffect(() => {
    if (!profile) return;
    setUsername((current) => current || profile.username);
    setDisplayName((current) => current || profile.display_name);
  }, [profile]);

  const saveIdentity = useCallback(async (): Promise<boolean> => {
    if (!user) return false;
    if (!isValidUsername(username)) {
      setError('Handles are 3–24 characters: lowercase letters, numbers and underscores.');
      return false;
    }
    if (displayName.trim().length < 2) {
      setError('Tell us what to call you.');
      return false;
    }

    setBusy(true);
    setError(null);
    try {
      if (username !== profile?.username) {
        const free = await usernameAvailable(supabase, username);
        if (!free) {
          setError('That handle is taken.');
          return false;
        }
      }
      await updateProfile(supabase, user.id, {
        username,
        display_name: displayName.trim(),
      });
      return true;
    } catch (thrown) {
      fromError(thrown);
      return false;
    } finally {
      setBusy(false);
    }
  }, [displayName, fromError, profile?.username, supabase, user, username]);

  const saveProfile = useCallback(async (): Promise<boolean> => {
    if (!user) return false;
    setBusy(true);
    setError(null);
    try {
      await updateProfile(supabase, user.id, {
        bio: bio.trim() || null,
        location: location.trim() || null,
        website: website.trim() || null,
      });
      return true;
    } catch (thrown) {
      fromError(thrown);
      return false;
    } finally {
      setBusy(false);
    }
  }, [bio, fromError, location, supabase, user, website]);

  const finish = useCallback(async () => {
    if (!user) return;
    setBusy(true);
    try {
      await completeOnboarding(supabase, user.id);
      success('You are all set', 'Welcome to Klect.');
      router.replace(DEFAULT_SIGNED_IN_ROUTE);
      router.refresh();
    } catch (thrown) {
      fromError(thrown);
      setBusy(false);
    }
  }, [fromError, router, success, supabase, user]);

  const next = async () => {
    if (step === 0) {
      if (await saveIdentity()) setStep(1);
      return;
    }
    if (step === 1) {
      if (await saveProfile()) setStep(2);
      return;
    }
    await finish();
  };

  return (
    <div className="w-full max-w-160">
      <ol className="mb-8 flex items-center gap-2" aria-label="Onboarding progress">
        {STEPS.map((label, index) => (
          <li key={label} className="flex flex-1 items-center gap-2">
            <span
              aria-current={index === step ? 'step' : undefined}
              className={cn(
                'flex h-1.5 flex-1 rounded-full transition-colors dur-base ease-standard',
                index <= step ? 'bg-accent' : 'bg-surface-3',
              )}
            />
            <span
              className={cn(
                'text-micro uppercase tracking-widest',
                index === step ? 'text-accent' : 'text-ink-3',
              )}
            >
              {label}
            </span>
          </li>
        ))}
      </ol>

      <section className="rounded-xl border border-line bg-surface-1 p-6 shadow-mid sm:p-8">
        {step === 0 ? (
          <div className="flex flex-col gap-4">
            <h1 className="font-display text-display3 text-ink">Claim your handle</h1>
            <p className="text-callout text-ink-2">
              This is how people find you and how your collections are addressed.
            </p>

            <TextField
              label="Display name"
              value={displayName}
              onChange={(event) => setDisplayName(event.target.value)}
              autoComplete="name"
              required
            />
            <TextField
              label="Handle"
              value={username}
              onChange={(event) => setUsername(normaliseUsername(event.target.value))}
              autoComplete="username"
              hint="Lowercase letters, numbers and underscores."
              required
            />
          </div>
        ) : null}

        {step === 1 ? (
          <div className="flex flex-col gap-4">
            <h1 className="font-display text-display3 text-ink">Say what you collect</h1>
            <p className="text-callout text-ink-2">
              One sentence is plenty. You can change any of this later.
            </p>

            <TextArea
              label="Bio"
              value={bio}
              onChange={(event) => setBio(event.target.value)}
              maxLength={160}
              showCount
              rows={3}
              placeholder="Film photographer. I collect the cameras more than I shoot them."
            />
            <TextField
              label="Location"
              value={location}
              onChange={(event) => setLocation(event.target.value)}
              placeholder="Beirut"
            />
            <TextField
              label="Website"
              type="url"
              inputMode="url"
              value={website}
              onChange={(event) => setWebsite(event.target.value)}
              iconLeft="link"
              placeholder="https://"
            />
          </div>
        ) : null}

        {step === 2 ? <SuggestedCollectors /> : null}

        {error ? (
          <p role="alert" className="mt-4 text-caption text-danger">
            {error}
          </p>
        ) : null}

        <div className="mt-8 flex items-center gap-3">
          {step > 0 ? (
            <Button variant="ghost" onClick={() => setStep((current) => current - 1)} disabled={busy}>
              Back
            </Button>
          ) : null}
          <div className="flex-1" />
          {step === 1 ? (
            <Button variant="quiet" onClick={() => setStep(2)} disabled={busy}>
              Skip
            </Button>
          ) : null}
          <Button onClick={() => void next()} loading={busy} size="lg">
            {step === 2 ? 'Start collecting' : 'Continue'}
          </Button>
        </div>
      </section>
    </div>
  );
}

function SuggestedCollectors() {
  const { supabase, user } = useSession();
  const [people, setPeople] = useState<ProfileRow[] | null>(null);

  useEffect(() => {
    let active = true;
    void listSuggestedCollectors(supabase, {
      ...(user ? { excludeUserId: user.id } : {}),
      limit: 8,
    })
      .then((rows) => {
        if (active) setPeople(rows);
      })
      .catch(() => {
        if (active) setPeople([]);
      });
    return () => {
      active = false;
    };
  }, [supabase, user]);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="font-display text-display3 text-ink">Find your people</h1>
      <p className="text-callout text-ink-2">
        Follow a few collectors so Pulse has something to say. You can always change
        your mind.
      </p>

      <ul className="flex flex-col gap-1">
        {people === null
          ? Array.from({ length: 4 }, (_, index) => (
              <li key={index} className="px-1 py-2">
                <SkeletonRow />
              </li>
            ))
          : people.map((person) => <SuggestionRow key={person.id} person={person} />)}
      </ul>

      {people !== null && people.length === 0 ? (
        <p className="flex items-center gap-2 text-callout text-ink-3">
          <Icon name="users" size="sm" />
          No public collectors to suggest yet — you are early.
        </p>
      ) : null}
    </div>
  );
}

function SuggestionRow({ person }: { person: ProfileRow }) {
  const follow = useFollowState(person.id, {
    followerCount: person.follower_count,
    viewerFollows: false,
  });

  return (
    <li className="flex items-center gap-3 rounded-md px-1 py-2 transition-colors dur-fast hover:bg-surface-2">
      <Avatar
        path={person.avatar_path}
        name={person.display_name}
        verified={person.is_verified}
      />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-body-strong text-ink">
          {person.display_name}
        </span>
        <span className="block truncate text-caption text-ink-3">
          @{person.username} · {compactCount(follow.followerCount)} followers
        </span>
      </span>
      <Button
        size="sm"
        variant={follow.following ? 'secondary' : 'primary'}
        onClick={follow.toggle}
      >
        {follow.following ? 'Following' : 'Follow'}
      </Button>
    </li>
  );
}
