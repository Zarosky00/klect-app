'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { useSession } from '@/providers/session-provider';

export function SignOutButton({ label = 'Sign out' }: { label?: string }) {
  const { signOut } = useSession();
  const [busy, setBusy] = useState(false);

  return (
    <Button
      variant="secondary"
      loading={busy}
      onClick={async () => {
        setBusy(true);
        await signOut();
        setBusy(false);
      }}
    >
      {label}
    </Button>
  );
}
