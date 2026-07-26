'use client';

import { useState } from 'react';
import { Button } from './Button';
import { Modal } from './Modal';

export interface ConfirmDialogProps {
  open: boolean;
  onCancel: () => void;
  onConfirm: () => void | Promise<void>;
  title: string;
  description?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
}

export function ConfirmDialog({
  open,
  onCancel,
  onConfirm,
  title,
  description,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  destructive = false,
}: ConfirmDialogProps) {
  const [busy, setBusy] = useState(false);

  const confirm = async () => {
    setBusy(true);
    try {
      await onConfirm();
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onCancel}
      title={title}
      {...(description === undefined ? {} : { description })}
      size="sm"
      dismissOnBackdrop={!busy}
      footer={
        <>
          <Button variant="ghost" onClick={onCancel} disabled={busy}>
            {cancelLabel}
          </Button>
          <Button
            variant={destructive ? 'danger' : 'primary'}
            onClick={confirm}
            loading={busy}
          >
            {confirmLabel}
          </Button>
        </>
      }
    >
      <div className="px-6 py-2" />
    </Modal>
  );
}
