'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { CloseupPanel } from './CloseupPanel';
import type { CloseupPayload } from '@/lib/types';

/**
 * The intercepted closeup: a modal over the grid, with the URL updated so it is
 * deep-linkable and the back button behaves. A hard load of the same URL renders
 * `/closeup/[type]/[id]` as a full page instead — same payload, same component.
 */
export function CloseupModal({ payload }: { payload: CloseupPayload }) {
  const router = useRouter();
  const [open, setOpen] = useState(true);

  const close = useCallback(() => {
    setOpen(false);
    router.back();
  }, [router]);

  return (
    <Modal
      open={open}
      onClose={close}
      size="lg"
      contentClassName="p-0"
      title={undefined}
      className="p-0"
    >
      <CloseupPanel payload={payload} variant="modal" />
    </Modal>
  );
}
