'use client';

import { useEffect, useState } from 'react';
import { cn } from '@/lib/cn';
import type { NotificationType } from '@/lib/entities';
import {
  MUTABLE_NOTIFICATION_TYPES,
  NOTIFICATION_TYPE_BLURBS,
  NOTIFICATION_TYPE_LABELS,
  loadMutedTypes,
  saveMutedTypes,
  subscribeMutedTypes,
  type MutableNotificationType,
} from '@/lib/notification-prefs';
import { Icon } from '@/components/ui/Icon';
import {
  NOTIFICATION_TYPE_ICON,
  NOTIFICATION_TYPE_TONE,
} from './notification-meta';

/**
 * Per-type notification mutes — the device-preference model mobile uses,
 * persisted client-side. A muted type stops popping the arrival banner on
 * this browser; the rows still land in Alerts and still count as unread, so
 * turning a mute off later shows everything that happened meanwhile.
 */
export function SettingsNotificationsForm() {
  // Prefs live in localStorage, so read them after mount — the server render
  // must not guess at a browser-only value.
  const [muted, setMuted] = useState<ReadonlySet<NotificationType> | null>(null);

  useEffect(() => {
    setMuted(loadMutedTypes());
    return subscribeMutedTypes(() => setMuted(loadMutedTypes()));
  }, []);

  const toggle = (type: MutableNotificationType) => {
    if (muted === null) return;
    const next = new Set(muted);
    if (next.has(type)) next.delete(type);
    else next.add(type);
    setMuted(next);
    saveMutedTypes(next);
  };

  return (
    <section className="flex flex-col gap-8">
      <header>
        <h2 className="font-display text-title1 text-ink">Notifications</h2>
        <p className="mt-1 text-callout text-ink-2">
          A device preference, like on the mobile app: muting a type silences its
          pop-up banner in this browser. Everything still lands in your Alerts
          list — nothing is ever lost.
        </p>
      </header>

      <ul className="flex flex-col gap-2">
        {MUTABLE_NOTIFICATION_TYPES.map((type) => {
          const on = muted === null ? true : !muted.has(type);
          return (
            <li
              key={type}
              className="flex items-start justify-between gap-4 rounded-lg border border-line bg-surface-1 p-4"
            >
              <span className="flex min-w-0 items-start gap-3">
                <span
                  className={cn(
                    'grid size-10 shrink-0 place-items-center rounded-full',
                    NOTIFICATION_TYPE_TONE[type],
                  )}
                >
                  <Icon name={NOTIFICATION_TYPE_ICON[type]} size="md" />
                </span>
                <span className="min-w-0">
                  <span className="block text-body-strong text-ink">
                    {NOTIFICATION_TYPE_LABELS[type]}
                  </span>
                  <span className="mt-0.5 block text-caption text-ink-2">
                    {NOTIFICATION_TYPE_BLURBS[type]}
                  </span>
                </span>
              </span>
              <button
                type="button"
                role="switch"
                aria-checked={on}
                aria-label={`${NOTIFICATION_TYPE_LABELS[type]} banners`}
                disabled={muted === null}
                onClick={() => toggle(type)}
                className={cn(
                  'focus-ring relative mt-1 h-6 w-11 shrink-0 rounded-full transition-colors dur-fast ease-standard',
                  on ? 'bg-accent' : 'bg-surface-3',
                  'disabled:opacity-[var(--k-opacity-disabled)]',
                )}
              >
                <span
                  className={cn(
                    'absolute top-0.5 size-5 rounded-full bg-base transition-all dur-fast ease-standard',
                    on ? 'left-[calc(100%-1.375rem)]' : 'left-0.5',
                  )}
                />
              </button>
            </li>
          );
        })}
      </ul>

      <p className="text-caption text-ink-3">
        System and moderation notices cannot be muted.
      </p>
    </section>
  );
}
