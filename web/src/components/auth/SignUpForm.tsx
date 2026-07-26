'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState, type FormEvent } from 'react';
import { Button, IconButton } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { TextField } from '@/components/ui/TextField';
import { usernameAvailable } from '@/lib/api';
import { SITE_URL } from '@/lib/env';
import {
  isValidEmail,
  isValidUsername,
  normaliseUsername,
  passwordProblem,
} from '@/lib/format';
import { routes } from '@/lib/routes';
import { createClient } from '@/lib/supabase/client';

type HandleState = 'idle' | 'checking' | 'free' | 'taken' | 'invalid';

export function SignUpForm() {
  const router = useRouter();

  const [displayName, setDisplayName] = useState('');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [reveal, setReveal] = useState(false);
  const [handleState, setHandleState] = useState<HandleState>('idle');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [checkEmail, setCheckEmail] = useState(false);

  // Debounced availability probe. The signup trigger will de-duplicate anyway,
  // but telling someone up front beats renaming them silently.
  useEffect(() => {
    if (!username) {
      setHandleState('idle');
      return;
    }
    if (!isValidUsername(username)) {
      setHandleState('invalid');
      return;
    }
    setHandleState('checking');
    const timer = setTimeout(async () => {
      try {
        const free = await usernameAvailable(createClient(), username);
        setHandleState(free ? 'free' : 'taken');
      } catch {
        setHandleState('idle');
      }
    }, 350);
    return () => clearTimeout(timer);
  }, [username]);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);

    if (displayName.trim().length < 2) {
      setError('Tell us what to call you.');
      return;
    }
    if (!isValidUsername(username)) {
      setError('Handles are 3–24 characters: lowercase letters, numbers and underscores.');
      return;
    }
    if (handleState === 'taken') {
      setError('That handle is taken.');
      return;
    }
    if (!isValidEmail(email)) {
      setError('That email does not look right.');
      return;
    }
    const passwordIssue = passwordProblem(password);
    if (passwordIssue) {
      setError(passwordIssue);
      return;
    }

    setBusy(true);
    const supabase = createClient();
    const { data, error: signUpError } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        // `handle_new_user` reads these to seed the profile row.
        data: { username, display_name: displayName.trim() },
        emailRedirectTo: `${SITE_URL}${routes.authCallback}?next=${encodeURIComponent(routes.onboarding)}`,
      },
    });

    if (signUpError) {
      setBusy(false);
      setError(signUpError.message);
      return;
    }

    if (data.session) {
      router.replace(routes.onboarding);
      router.refresh();
      return;
    }

    // Email confirmation is on: nothing else to do until they click the link.
    setBusy(false);
    setCheckEmail(true);
  };

  if (checkEmail) {
    return (
      <div className="flex flex-col items-start gap-4">
        <span className="grid size-12 place-items-center rounded-full bg-accent-subtle text-accent">
          <Icon name="mail" size="xl" />
        </span>
        <p className="text-body text-ink">
          Check <strong>{email}</strong> for a confirmation link. Open it and we will pick
          up where you left off.
        </p>
        <p className="text-caption text-ink-3">
          No email after a minute? Check spam, or sign up again with a different address.
        </p>
      </div>
    );
  }

  const handleHint =
    handleState === 'taken'
      ? 'Taken — try another.'
      : handleState === 'free'
        ? 'Available.'
        : handleState === 'invalid'
          ? '3–24 characters: a–z, 0–9 and underscores.'
          : 'This is how people find you.';

  return (
    <form onSubmit={submit} className="flex flex-col gap-4" noValidate>
      <TextField
        label="Display name"
        name="display-name"
        autoComplete="name"
        required
        value={displayName}
        onChange={(event) => setDisplayName(event.target.value)}
        placeholder="Noor Haddad"
      />

      <TextField
        label="Handle"
        name="username"
        autoComplete="username"
        required
        value={username}
        onChange={(event) => setUsername(normaliseUsername(event.target.value))}
        placeholder="noor"
        hint={handleHint}
        error={handleState === 'taken' ? 'That handle is taken.' : null}
        trailing={
          handleState === 'checking' ? (
            <span className="pr-2 text-ink-3">
              <Icon name="spinner" size="sm" />
            </span>
          ) : handleState === 'free' ? (
            <span className="pr-2 text-success">
              <Icon name="check" size="sm" />
            </span>
          ) : null
        }
      />

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

      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}

      <Button type="submit" loading={busy} block size="lg">
        Create account
      </Button>
    </form>
  );
}
