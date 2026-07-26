'use client';

import { useRouter } from 'next/navigation';
import { ErrorState } from '@/components/ui/ErrorState';

/**
 * A server read failed before the console could render.
 *
 * `ErrorState` needs an `onRetry` callback, which a Server Component cannot
 * hand it, so this thin client wrapper re-runs the server render instead.
 */
export function AdminLoadError({ title, message }: { title?: string; message: string }) {
  const router = useRouter();
  return (
    <ErrorState
      title={title ?? 'That did not load'}
      description={message}
      onRetry={() => router.refresh()}
      retryLabel="Retry"
    />
  );
}
