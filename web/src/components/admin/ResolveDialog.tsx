'use client';

import { useEffect, useState } from 'react';
import { cn } from '@/lib/cn';
import { Button } from '@/components/ui/Button';
import type { IconName } from '@/components/ui/Icon';
import { Modal } from '@/components/ui/Modal';
import { TextArea } from '@/components/ui/TextField';
import { SUSPENSION_TERMS } from './actions';
import { Notice, type BadgeTone } from './ui';

export interface ResolvePayload {
  reason?: string;
  suspendDays?: number;
}

/** `ModActionSpec` satisfies this structurally, and so does a user-console action. */
export interface ResolveIntent {
  label: string;
  icon: IconName;
  tone: BadgeTone;
  /** Plain words for what the verb actually does. Shown before it fires. */
  blurb: string;
  /** Offers the suspension term picker. */
  duration: boolean;
}

export interface ResolveDialogProps {
  open: boolean;
  spec: ResolveIntent | null;
  /** What the action lands on — "@aria" or "this item". */
  subject: string;
  /** An extra consequence worth stating, e.g. the sibling-report auto-resolve. */
  note?: string;
  onCancel: () => void;
  onConfirm: (payload: ResolvePayload) => Promise<void>;
}

/**
 * The confirm step for every destructive moderation action.
 *
 * The reason is optional to the RPC but not to the operator: it becomes the
 * report's `resolution`, the `moderation_actions.reason`, and the text the
 * suspended account is shown. So it is offered on every action, and the dialog
 * says in plain words what the verb does before it is pressed.
 */
export function ResolveDialog({
  open,
  spec,
  subject,
  note,
  onCancel,
  onConfirm,
}: ResolveDialogProps) {
  const [reason, setReason] = useState('');
  const [days, setDays] = useState<number | null>(7);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (open) {
      setReason('');
      setDays(7);
      setBusy(false);
    }
  }, [open, spec?.label]);

  if (!spec) return null;

  const confirm = async () => {
    setBusy(true);
    try {
      const payload: ResolvePayload = {};
      const trimmed = reason.trim();
      if (trimmed) payload.reason = trimmed;
      if (spec.duration && days !== null) payload.suspendDays = days;
      await onConfirm(payload);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={busy ? () => undefined : onCancel}
      title={`${spec.label} — ${subject}`}
      size="sm"
      dismissOnBackdrop={!busy}
      footer={
        <>
          <Button variant="ghost" size="sm" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button
            variant={spec.tone === 'danger' ? 'danger' : 'primary'}
            size="sm"
            iconLeft={spec.icon}
            loading={busy}
            onClick={() => void confirm()}
          >
            {spec.label}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 px-6 py-4">
        <Notice tone={spec.tone === 'danger' ? 'danger' : 'warning'} title={spec.label}>
          {spec.blurb}
        </Notice>

        {spec.duration ? (
          <fieldset className="flex flex-col gap-2">
            <legend className="text-label text-ink-2">Term</legend>
            <div className="flex flex-wrap gap-1.5">
              {SUSPENSION_TERMS.map((term) => {
                const selected = term.days === days;
                return (
                  <button
                    key={term.label}
                    type="button"
                    aria-pressed={selected}
                    onClick={() => setDays(term.days)}
                    className={cn(
                      'focus-ring rounded-xs border px-2 py-1 text-caption tabular',
                      'transition-colors dur-fast ease-standard',
                      selected
                        ? 'border-accent bg-accent-subtle text-accent'
                        : 'border-line bg-surface-2 text-ink-2 hover:text-ink',
                    )}
                  >
                    {term.label}
                  </button>
                );
              })}
            </div>
            <p className="text-caption text-ink-3">
              {days === null
                ? 'No end date — the account stays suspended until a moderator lifts it.'
                : `Lifts automatically after ${days} ${days === 1 ? 'day' : 'days'}.`}
            </p>
          </fieldset>
        ) : null}

        <TextArea
          label="Reason"
          hint="Stored on the report and shown to the account. Optional, but the next moderator will want it."
          rows={3}
          maxLength={280}
          showCount
          value={reason}
          onChange={(event) => setReason(event.target.value)}
        />

        {note ? <p className="text-caption text-ink-3">{note}</p> : null}
      </div>
    </Modal>
  );
}
