'use client';

import { useRouter } from 'next/navigation';
import { useState, type FormEvent } from 'react';
import { Button, IconButton } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { passwordProblem } from '@/lib/format';
import { DEFAULT_SIGNED_IN_ROUTE } from '@/lib/routes';
import { createClient } from '@/lib/supabase/client';
import { useToast } from '@/providers/toast-provider';

export function ResetPasswordForm() {
  const router = useRouter();
  const { success } = useToast();

  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [reveal, setReveal] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);

    const problem = passwordProblem(password);
    if (problem) {
      setError(problem);
      return;
    }
    if (password !== confirm) {
      setError('The two passwords do not match.');
      return;
    }

    setBusy(true);
    const supabase = createClient();
    const { error: updateError } = await supabase.auth.updateUser({ password });

    if (updateError) {
      setBusy(false);
      setError(
        /Auth session missing/i.test(updateError.message)
          ? 'That reset link has expired. Request a new one.'
          : updateError.message,
      );
      return;
    }

    success('Password updated');
    router.replace(DEFAULT_SIGNED_IN_ROUTE);
    router.refresh();
  };

  return (
    <form onSubmit={submit} className="flex flex-col gap-4" noValidate>
      <TextField
        label="New password"
        type={reveal ? 'text' : 'password'}
        autoComplete="new-password"
        iconLeft="lock"
        required
        value={password}
        onChange={(event) => setPassword(event.target.value)}
        hint="At least 8 characters, with a letter and a number."
        trailing={
          <IconButton
            icon={reveal ? 'eye' : 'lock'}
            label={reveal ? 'Hide password' : 'Show password'}
            size="sm"
            variant="ghost"
            onClick={() => setReveal((current) => !current)}
          />
        }
      />

      <TextField
        label="Confirm new password"
        type={reveal ? 'text' : 'password'}
        autoComplete="new-password"
        iconLeft="lock"
        required
        value={confirm}
        onChange={(event) => setConfirm(event.target.value)}
      />

      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}

      <Button type="submit" loading={busy} block size="lg">
        Update password
      </Button>
    </form>
  );
}
