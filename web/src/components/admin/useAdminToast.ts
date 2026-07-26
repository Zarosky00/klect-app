'use client';

import { useCallback } from 'react';
import { toKlectError } from '@/lib/errors';
import { useToast } from '@/providers/toast-provider';
import { serverErrorText } from './data';

export type AdminFailureHandler = (error: unknown, retry?: () => void) => void;

/**
 * Toasts for the console.
 *
 * A refusal is never softened: `admin_*` RPCs raise `Forbidden` /
 * `Superadmin only` with `errcode = 42501`, and the operator is shown exactly
 * that rather than the public app's "you can no longer interact with this".
 * Everything else goes through the normal toast, retry offer and all.
 */
export function useAdminToast(): {
  fail: AdminFailureHandler;
  toast: ReturnType<typeof useToast>;
} {
  const toast = useToast();

  const fail = useCallback<AdminFailureHandler>(
    (error, retry) => {
      const klect = toKlectError(error);
      if (klect.kind === 'forbidden' || klect.kind === 'unauthorized') {
        toast.error('Refused by the server', serverErrorText(error));
        return;
      }
      toast.fromError(error, retry ? { retry } : undefined);
    },
    [toast],
  );

  return { fail, toast };
}
