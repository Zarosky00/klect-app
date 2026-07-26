'use client';

import { useState } from 'react';
import { submitReport } from '@/lib/api';
import { REPORT_REASONS, REPORT_REASON_LABELS, type EntityType, type ReportReason } from '@/lib/entities';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { Button } from './Button';
import { Modal } from './Modal';
import { TextArea } from './TextField';

/**
 * Reachable from every surface: item, subcollection, collection, post, comment,
 * message and profile (CHECKLIST F). Reporting the same target twice is not an
 * error — the RPC returns `already_reported` and we say so.
 */
export interface ReportDialogProps {
  open: boolean;
  onClose: () => void;
  /** What is being reported. Give an entity, a user, or a message. */
  target:
    | { kind: 'entity'; type: EntityType; id: string }
    | { kind: 'user'; id: string }
    | { kind: 'message'; id: string };
  /** Shown above the reason list, e.g. the item title. */
  subject?: string;
}

export function ReportDialog({ open, onClose, target, subject }: ReportDialogProps) {
  const { supabase } = useSession();
  const { success, toast, fromError } = useToast();
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState('');
  const [busy, setBusy] = useState(false);

  const reset = () => {
    setReason(null);
    setDetails('');
    setBusy(false);
  };

  const close = () => {
    reset();
    onClose();
  };

  const send = async () => {
    if (!reason) return;
    setBusy(true);
    try {
      const result = await submitReport(supabase, {
        reason,
        ...(target.kind === 'entity' ? { entityType: target.type, entityId: target.id } : {}),
        ...(target.kind === 'user' ? { userId: target.id } : {}),
        ...(target.kind === 'message' ? { messageId: target.id } : {}),
        ...(details.trim() ? { details: details.trim() } : {}),
      });

      if (result.already_reported) {
        toast({
          title: 'You have already reported this',
          description: 'Our moderators are on it. No need to report it twice.',
        });
      } else {
        success('Report sent', 'Thank you. A moderator will review it.');
      }
      close();
    } catch (error) {
      fromError(error);
      setBusy(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={close}
      title="Report"
      description={subject ? `Reporting “${subject}”.` : 'Tell us what is wrong.'}
      size="sm"
      dismissOnBackdrop={!busy}
      footer={
        <>
          <Button variant="ghost" onClick={close} disabled={busy}>
            Cancel
          </Button>
          <Button variant="danger" onClick={send} loading={busy} disabled={!reason}>
            Send report
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 px-6 py-4">
        <fieldset className="flex flex-col gap-1">
          <legend className="mb-2 text-label text-ink-2">Reason</legend>
          {REPORT_REASONS.map((value) => (
            <label
              key={value}
              className={
                'focus-within:ring-2 focus-within:ring-accent flex cursor-pointer items-center gap-3 rounded-sm px-2 py-2 text-body text-ink transition-colors dur-fast hover:bg-surface-2'
              }
            >
              <input
                type="radio"
                name="report-reason"
                value={value}
                checked={reason === value}
                onChange={() => setReason(value)}
                className="size-4 accent-[var(--k-accent-default)]"
              />
              {REPORT_REASON_LABELS[value]}
            </label>
          ))}
        </fieldset>

        <TextArea
          label="Anything else? (optional)"
          value={details}
          onChange={(event) => setDetails(event.target.value)}
          maxLength={500}
          showCount
          rows={3}
          placeholder="Context helps moderators act faster."
        />
      </div>
    </Modal>
  );
}
