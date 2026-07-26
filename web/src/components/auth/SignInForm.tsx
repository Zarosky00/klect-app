'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useState, type FormEvent } from 'react';
import { Button, IconButton } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { isValidEmail } from '@/lib/format';
import { DEFAULT_SIGNED_IN_ROUTE, routes, safeRedirectTarget } from '@/lib/routes';
import { createClient } from '@/lib/supabase/client';

export function SignInForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = safeRedirectTarget(searchParams.get('next')) ?? DEFAULT_SIGNED_IN_ROUTE;

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [reveal, setReveal] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);

    if (!isValidEmail(email)) {
      setError('That email does not look right.');
      return;
    }
    if (!password) {
      setError('Enter your password.');
      return;
    }

    setBusy(true);
    const supabase = createClient();
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    if (signInError) {
      setBusy(false);
      setError(
        signInError.message === 'Invalid login credentials'
          ? 'That email and password do not match an account.'
          : signInError.message,
      );
      return;
    }

    router.replace(next);
    router.refresh();
  };

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

      <TextField
        label="Password"
        type={reveal ? 'text' : 'password'}
        name="password"
        autoComplete="current-password"
        iconLeft="lock"
        required
        value={password}
        onChange={(event) => setPassword(event.target.value)}
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

      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}

      <Button type="submit" loading={busy} block size="lg">
        Sign in
      </Button>

      <Link
        href={routes.forgotPassword}
        className="focus-ring self-center rounded-sm text-caption text-ink-2 underline underline-offset-4 hover:text-ink"
      >
        Forgot your password?
      </Link>
    </form>
  );
}
