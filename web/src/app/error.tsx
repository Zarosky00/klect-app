'use client';

import { useEffect } from 'react';
import { ErrorState } from '@/components/ui/ErrorState';

export default function AppError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Server digests are the only handle we get on a production stack trace.
    console.error('[klect] route error', error.digest ?? error.message);
  }, [error]);

  return (
    <main id="main" className="flex min-h-dvh items-center justify-center">
      <ErrorState error={error} onRetry={reset} />
    </main>
  );
}
