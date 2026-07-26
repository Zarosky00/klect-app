'use client';

import { cn } from '@/lib/cn';
import { Icon, type IconName } from './Icon';

export type ToastTone = 'neutral' | 'success' | 'danger' | 'accent';

export interface ToastData {
  id: string;
  title: string;
  description?: string;
  tone?: ToastTone;
  /** ms. Falsy keeps it until dismissed. */
  duration?: number;
  action?: { label: string; onClick: () => void };
}

const toneIcon: Record<ToastTone, IconName> = {
  neutral: 'check',
  success: 'check',
  danger: 'alert',
  accent: 'bookmark',
};

const toneClasses: Record<ToastTone, string> = {
  neutral: 'text-ink-2',
  success: 'text-success',
  danger: 'text-danger',
  accent: 'text-accent',
};

export interface ToastCardProps {
  toast: ToastData;
  onDismiss: (id: string) => void;
}

export function ToastCard({ toast, onDismiss }: ToastCardProps) {
  const tone = toast.tone ?? 'neutral';
  return (
    <div
      role="status"
      aria-live={tone === 'danger' ? 'assertive' : 'polite'}
      className={cn(
        'pointer-events-auto flex w-full max-w-[calc(var(--k-readable-max)/2)] items-start gap-3',
        'glass rounded-lg border border-line px-4 py-3 shadow-high',
        'k-toast-enter',
      )}
    >
      <span className={cn('mt-0.5', toneClasses[tone])}>
        <Icon name={toneIcon[tone]} size="md" />
      </span>

      <div className="min-w-0 flex-1">
        <p className="text-body-strong text-ink">{toast.title}</p>
        {toast.description ? (
          <p className="mt-0.5 text-caption text-ink-2">{toast.description}</p>
        ) : null}
        {toast.action ? (
          <button
            type="button"
            onClick={() => {
              toast.action?.onClick();
              onDismiss(toast.id);
            }}
            className="focus-ring mt-2 text-label text-accent underline underline-offset-4"
          >
            {toast.action.label}
          </button>
        ) : null}
      </div>

      <button
        type="button"
        onClick={() => onDismiss(toast.id)}
        aria-label="Dismiss"
        className="focus-ring -mr-1 rounded-sm p-1 text-ink-3 transition-colors dur-fast hover:text-ink"
      >
        <Icon name="close" size="sm" />
      </button>
    </div>
  );
}
