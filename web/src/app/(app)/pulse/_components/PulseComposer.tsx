'use client';

import { useCallback, useState } from 'react';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { TextArea } from '@/components/ui/TextField';
import { cn } from '@/lib/cn';
import { toKlectError } from '@/lib/errors';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * The Pulse composer.
 *
 * Posts are a plain insert guarded by RLS — there is no `create_post` RPC,
 * because a post carries no counters that need a trigger at write time. On
 * success the new post is handed straight to the stream so it appears without a
 * refetch; on failure the draft is kept, never cleared.
 */

export const MAX_POST_LENGTH = 500;

export interface PulseComposerProps {
  onPosted: (post: { id: string; body: string; created_at: string }) => void;
  className?: string;
}

export function PulseComposer({ onPosted, className }: PulseComposerProps) {
  const { supabase, user, profile } = useSession();
  const { fromError, success } = useToast();
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = useCallback(async () => {
    const trimmed = body.trim();
    if (!trimmed || !user) return;

    setBusy(true);
    try {
      const { data, error } = await supabase
        .from('posts')
        .insert({ author_id: user.id, body: trimmed, kind: 'post' })
        .select('id, body, created_at')
        .single();
      if (error) throw toKlectError(error);

      setBody('');
      success('Posted');
      onPosted({
        id: data.id,
        body: data.body ?? trimmed,
        created_at: data.created_at,
      });
    } catch (error) {
      // The words stay in the box. Losing a draft to a network blip is the one
      // thing a composer must never do.
      fromError(error, { retry: () => void submit() });
    } finally {
      setBusy(false);
    }
  }, [body, fromError, onPosted, success, supabase, user]);

  if (!user) return null;

  return (
    <form
      className={cn('flex gap-3 border-b border-line-subtle px-4 py-4 sm:px-6', className)}
      onSubmit={(event) => {
        event.preventDefault();
        void submit();
      }}
    >
      <Avatar
        path={profile?.avatar_path}
        name={profile?.display_name}
        username={profile?.username}
        size="md"
        verified={profile?.is_verified ?? false}
      />

      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <TextArea
          label="What are you collecting?"
          labelHidden
          rows={2}
          value={body}
          maxLength={MAX_POST_LENGTH}
          showCount
          placeholder="What did you just add to the shelf?"
          onChange={(event) => setBody(event.target.value)}
          onKeyDown={(event) => {
            if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
              event.preventDefault();
              void submit();
            }
          }}
        />
        <div className="flex items-center justify-end gap-3">
          <span className="text-caption text-ink-3">⌘/Ctrl + Enter</span>
          <Button type="submit" size="sm" loading={busy} disabled={!body.trim()}>
            Post
          </Button>
        </div>
      </div>
    </form>
  );
}
