'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useState } from 'react';
import { updateProfile } from '@/lib/api';
import { cn } from '@/lib/cn';
import { VISIBILITY_LABELS, type Visibility } from '@/lib/entities';
import type { ProfileRow } from '@/lib/types';
import { Button } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * Privacy. Every control here maps to exactly one column, and the server
 * enforces all three regardless of what the UI shows:
 *   · `account_visibility` gates the profile and everything under it via RLS;
 *   · `allow_messages_from` is checked inside `start_dm`;
 *   · `show_similarity` hides the match score from other people's screens.
 */

const VISIBILITIES: readonly Visibility[] = ['public', 'followers', 'private'];

const VISIBILITY_BLURB: Record<Visibility, string> = {
  public: 'Anyone, signed in or not, can see your profile and public collections.',
  followers: 'Only people you have approved as followers can see your shelves.',
  private: 'Nobody but you. Your collections disappear from surf, search and matches.',
};

const MESSAGE_OPTIONS = ['everyone', 'following', 'matches', 'nobody'] as const;
type MessageOption = (typeof MESSAGE_OPTIONS)[number];

const MESSAGE_LABELS: Record<MessageOption, string> = {
  everyone: 'Everyone',
  following: 'People I follow',
  matches: 'Collectors who match my taste',
  nobody: 'Nobody',
};

const MESSAGE_BLURB: Record<MessageOption, string> = {
  everyone: 'Any collector can open a DM with you.',
  following: 'Only accounts you follow can start a conversation.',
  matches: 'Only people the matching engine rates as a real overlap.',
  nobody: 'No new conversations. Existing threads stay readable.',
};

function isMessageOption(value: string): value is MessageOption {
  return (MESSAGE_OPTIONS as readonly string[]).includes(value);
}

export function SettingsPrivacyForm({ profile }: { profile: ProfileRow }) {
  const router = useRouter();
  const { supabase } = useSession();
  const { success, fromError } = useToast();

  const [visibility, setVisibility] = useState<Visibility>(profile.account_visibility);
  const [messages, setMessages] = useState<MessageOption>(
    isMessageOption(profile.allow_messages_from) ? profile.allow_messages_from : 'everyone',
  );
  const [similarity, setSimilarity] = useState(profile.show_similarity);
  const [saving, setSaving] = useState(false);

  const dirty =
    visibility !== profile.account_visibility ||
    messages !== profile.allow_messages_from ||
    similarity !== profile.show_similarity;

  const save = useCallback(async () => {
    setSaving(true);
    try {
      await updateProfile(supabase, profile.id, {
        account_visibility: visibility,
        allow_messages_from: messages,
        show_similarity: similarity,
      });
      success('Privacy updated');
      router.refresh();
    } catch (error) {
      fromError(error);
    } finally {
      setSaving(false);
    }
  }, [fromError, messages, profile.id, router, similarity, success, supabase, visibility]);

  return (
    <section className="flex flex-col gap-8">
      <header>
        <h2 className="font-display text-title1 text-ink">Privacy</h2>
        <p className="mt-1 text-callout text-ink-2">
          These are enforced in the database, not in this page — turning something off
          here removes it for everyone, everywhere, immediately.
        </p>
      </header>

      <fieldset className="flex flex-col gap-2">
        <legend className="mb-2 text-label uppercase tracking-widest text-ink-3">
          Who can see your account
        </legend>
        {VISIBILITIES.map((value) => (
          <RadioCard
            key={value}
            name="account-visibility"
            value={value}
            checked={visibility === value}
            onSelect={() => setVisibility(value)}
            icon={value === 'public' ? 'compass' : value === 'followers' ? 'users' : 'lock'}
            title={VISIBILITY_LABELS[value]}
            blurb={VISIBILITY_BLURB[value]}
          />
        ))}
      </fieldset>

      <fieldset className="flex flex-col gap-2">
        <legend className="mb-2 text-label uppercase tracking-widest text-ink-3">
          Who can message you
        </legend>
        {MESSAGE_OPTIONS.map((value) => (
          <RadioCard
            key={value}
            name="allow-messages"
            value={value}
            checked={messages === value}
            onSelect={() => setMessages(value)}
            icon="mail"
            title={MESSAGE_LABELS[value]}
            blurb={MESSAGE_BLURB[value]}
          />
        ))}
      </fieldset>

      <div className="flex items-start justify-between gap-4 rounded-lg border border-line bg-surface-1 p-4">
        <span className="min-w-0">
          <span className="block text-body-strong text-ink">Show my taste similarity</span>
          <span className="mt-1 block text-caption text-ink-2">
            When on, other collectors see a match percentage next to your name. Off hides
            the number — you are still matched, you are just not scored in public.
          </span>
        </span>
        <button
          type="button"
          role="switch"
          aria-checked={similarity}
          aria-label="Show my taste similarity"
          onClick={() => setSimilarity((current) => !current)}
          className={cn(
            'focus-ring relative h-6 w-11 shrink-0 rounded-full transition-colors dur-fast ease-standard',
            similarity ? 'bg-accent' : 'bg-surface-3',
          )}
        >
          <span
            className={cn(
              'absolute top-0.5 size-5 rounded-full bg-base transition-all dur-fast ease-standard',
              similarity ? 'left-[calc(100%-1.375rem)]' : 'left-0.5',
            )}
          />
        </button>
      </div>

      <div className="flex items-center gap-3 border-t border-line-subtle pt-6">
        <Button onClick={() => void save()} loading={saving} disabled={!dirty}>
          Save privacy settings
        </Button>
        {dirty ? <span className="text-caption text-ink-3">Unsaved changes</span> : null}
      </div>
    </section>
  );
}

function RadioCard({
  name,
  value,
  checked,
  onSelect,
  icon,
  title,
  blurb,
}: {
  name: string;
  value: string;
  checked: boolean;
  onSelect: () => void;
  icon: 'compass' | 'users' | 'lock' | 'mail';
  title: string;
  blurb: string;
}) {
  return (
    <label
      className={cn(
        'flex cursor-pointer items-start gap-3 rounded-lg border p-4',
        'transition-colors dur-fast ease-standard',
        'focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-focus',
        checked ? 'border-accent bg-accent-subtle' : 'border-line bg-surface-1 hover:bg-surface-2',
      )}
    >
      <input
        type="radio"
        name={name}
        value={value}
        checked={checked}
        onChange={onSelect}
        className="sr-only"
      />
      <span
        className={cn(
          'grid size-10 shrink-0 place-items-center rounded-full',
          checked ? 'bg-accent text-ink-on-accent' : 'bg-surface-3 text-ink-2',
        )}
      >
        <Icon name={icon} size="md" />
      </span>
      <span className="min-w-0">
        <span className="block text-body-strong text-ink">{title}</span>
        <span className="mt-0.5 block text-caption text-ink-2">{blurb}</span>
      </span>
      {checked ? (
        <span className="ml-auto text-accent">
          <Icon name="check" size="md" />
        </span>
      ) : null}
    </label>
  );
}
