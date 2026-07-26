'use client';

import { useState, type FormEvent } from 'react';
import { Button } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { TextField } from '@/components/ui/TextField';
import { SITE_URL } from '@/lib/env';
import { isValidEmail } from '@/lib/format';
import { routes } from '@/lib/routes';
import { createClient } from '@/lib/supabase/client';

export function ForgotPasswordForm() {
  const [email, setEmail] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);

    if (!isValidEmail(email)) {
      setError('That email does not look right.');
      return;
    }

    setBusy(true);
    const supabase = createClient();
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${SITE_URL}${routes.authConfirm}?next=${encodeURIComponent(routes.resetPassword)}`,
    });
    setBusy(false);

    if (resetError) {
      setError(resetError.message);
      return;
    }
    // Always report success — telling a stranger which addresses exist is a leak.
    setSent(true);
  };

  if (sent) {
    return (
      <div className="flex flex-col items-start gap-4">
        <span className="grid size-12 place-items-center rounded-full bg-accent-subtle text-accent">
          <Icon name="mail" size="xl" />
        </span>
        <p className="text-body text-ink">
          If an account exists for <strong>{email}</strong>, a reset link is on its way.
        </p>
        <p className="text-caption text-ink-3">The link expires in one hour.</p>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-4" noValidate>
      <TextField
        label="Email"
        type="email"
        name="email"
        autoComplete="email"
        inputMode="email"
        iconLeft="mail"
        required
        value={email}
        onChange={(event) => setEmail(event.target.value)}
      />

      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}

      <Button type="submit" loading={busy} block size="lg">
        Send reset link
      </Button>
    </form>
  );
}
