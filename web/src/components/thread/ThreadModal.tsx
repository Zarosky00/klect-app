'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useState } from 'react';
import { IconButton } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Sheet } from '@/components/ui/Sheet';
import { usePhoneViewport } from '@/lib/media-query';
import type { PostThread } from '@/lib/types';
import { PostThreadView } from './PostThreadView';

/**
 * The intercepted post thread, with the URL updated so it is deep-linkable and
 * the back button behaves. A hard load of the same URL renders `/p/[id]` as a
 * full page instead — same payload, same component (the closeup pattern).
 */
export function ThreadModal({ thread }: { thread: PostThread }) {
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
        <div className="pointer-events-none sticky top-0 z-raised h-0">
          <div className="pointer-events-auto absolute right-3 top-1">
            <IconButton icon="close" label="Close" onClick={close} size="sm" />
          </div>
        </div>
        <PostThreadView thread={thread} variant="modal" />
      </Sheet>
    );
  }

  return (
    <Modal
      open={open}
      onClose={close}
      size="md"
      contentClassName="p-0"
      title={undefined}
      className="p-0"
    >
      <PostThreadView thread={thread} variant="modal" />
    </Modal>
  );
}
