/**
 * The moderation action vocabulary, in the order a triager reaches for it.
 *
 * `admin_resolve_report(p_report, p_action, p_reason, p_suspend_days)` accepts
 * every `mod_action`; this table is the UI's opinion about each one — the key
 * that fires it, whether it needs a confirmation step, and what it actually
 * does server-side (worth restating, because the RPC does more than its name
 * suggests: it also auto-resolves every other open report on the same target).
 */
import type { IconName } from '@/components/ui/Icon';
import type { ModAction } from '@/lib/entities';
import type { BadgeTone } from './ui';

export interface ModActionSpec {
  action: ModAction;
  /** Button label. */
  label: string;
  icon: IconName;
  tone: BadgeTone;
  /** Single keystroke in the queue. `7` is deliberately off the 1–6 sweep. */
  hotkey: string;
  /** Destructive: needs an explicit confirm before it fires. */
  confirm: boolean;
  /** Offers the duration picker. */
  duration: boolean;
  /** What the report must point at for the action to mean anything. */
  needs: 'entity' | 'user' | 'any';
  /** Shown in the confirm dialog, so nobody guesses what a verb does. */
  blurb: string;
}

export const MOD_ACTIONS: readonly ModActionSpec[] = [
  {
    action: 'none',
    label: 'Dismiss',
    icon: 'check',
    tone: 'neutral',
    hotkey: '1',
    confirm: false,
    duration: false,
    needs: 'any',
    blurb: 'Marks the report dismissed and leaves the content and the account untouched.',
  },
  {
    action: 'warn',
    label: 'Warn',
    icon: 'alert',
    tone: 'warning',
    hotkey: '2',
    confirm: false,
    duration: false,
    needs: 'user',
    blurb: 'Notifies the account that its content was reviewed. Nothing is hidden or removed.',
  },
  {
    action: 'hide_content',
    label: 'Hide',
    icon: 'eye',
    tone: 'warning',
    hotkey: '3',
    confirm: false,
    duration: false,
    needs: 'entity',
    blurb: 'Sets hidden_at on the reported row. Invisible to everyone but its owner and staff, and fully reversible.',
  },
  {
    action: 'restore_content',
    label: 'Restore',
    icon: 'repost',
    tone: 'success',
    hotkey: '4',
    confirm: false,
    duration: false,
    needs: 'entity',
    blurb: 'Clears hidden_at and puts the content back in every feed.',
  },
  {
    action: 'suspend_user',
    label: 'Suspend',
    icon: 'lock',
    tone: 'danger',
    hotkey: '5',
    confirm: true,
    duration: true,
    needs: 'user',
    blurb: 'Blocks the account from every write RPC and sends it to the suspension screen until the term expires.',
  },
  {
    action: 'ban_user',
    label: 'Ban',
    icon: 'close',
    tone: 'danger',
    hotkey: '6',
    confirm: true,
    duration: false,
    needs: 'user',
    blurb: 'Suspends the account with no end date. Reversible only from the Users console.',
  },
  {
    action: 'delete_content',
    label: 'Delete',
    icon: 'trash',
    tone: 'danger',
    hotkey: '7',
    confirm: true,
    duration: false,
    needs: 'entity',
    blurb: 'Deletes the row outright, along with its likes, saves, comments, views and tags. This cannot be undone.',
  },
];

export const MOD_ACTION_LABELS: Record<ModAction, string> = {
  none: 'Dismissed',
  warn: 'Warned',
  hide_content: 'Content hidden',
  delete_content: 'Content deleted',
  suspend_user: 'Account suspended',
  ban_user: 'Account banned',
  restore_content: 'Content restored',
};

export function modActionByHotkey(key: string): ModActionSpec | undefined {
  return MOD_ACTIONS.find((spec) => spec.hotkey === key);
}

/** Suspension terms. `null` = indefinite, which is what `ban_user` writes. */
export const SUSPENSION_TERMS: ReadonlyArray<{ days: number | null; label: string }> = [
  { days: 1, label: '1 day' },
  { days: 3, label: '3 days' },
  { days: 7, label: '7 days' },
  { days: 14, label: '14 days' },
  { days: 30, label: '30 days' },
  { days: 90, label: '90 days' },
  { days: null, label: 'Indefinite' },
];
