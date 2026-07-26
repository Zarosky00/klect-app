'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useState } from 'react';
import { IconButton } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Sheet } from '@/components/ui/Sheet';
import { usePhoneViewport } from '@/lib/media-query';
import { CloseupPanel } from './CloseupPanel';
import type { CloseupPayload } from '@/lib/types';

/**
 * The intercepted closeup, with the URL updated so it is deep-linkable and the
 * back button behaves. A hard load of the same URL renders `/closeup/[type]/[id]`
 * as a full page instead — same payload, same component.
 *
 * Desktop gets the large dialog. Phones get a full-screen `dvh` sheet — a
 * 92vw rounded island on a 390px screen is all chrome and no photograph, and
 * `vh` units misjudge Safari's collapsing URL bar where `dvh` does not.
 */
export function CloseupModal({ payload }: { payload: CloseupPayload }) {
  const router = useRouter();
  const [open, setOpen] = useState(true);
  const phone = usePhoneViewport();

  const close = useCallback(() => {
    setOpen(false);
    router.back();
  }, [router]);

  if (phone) {
    return (
      <Sheet open={open} onClose={close} fullHeight contentClassName="p-0">
        {/* Drag dismisses, but reduced-motion disables the drag — a visible
            close control must always exist. Sticky so it survives the scroll. */}
        <div className="pointer-events-none sticky top-0 z-raised h-0">
          <div className="pointer-events-auto absolute right-3 top-1">
            <IconButton icon="close" label="Close" onClick={close} size="sm" />
          </div>
        </div>
        <CloseupPanel payload={payload} variant="modal" />
      </Sheet>
    );
  }

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
