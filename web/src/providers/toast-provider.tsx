'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { duration } from '@/design/tokens.g';
import { ToastCard, type ToastData, type ToastTone } from '@/components/ui/Toast';
import { errorMessage, toKlectError } from '@/lib/errors';

const DEFAULT_DURATION = duration.deliberate * 10; // 4.8s — long enough to read.
const MAX_VISIBLE = 4;

export interface ToastInput {
  title: string;
  description?: string;
  tone?: ToastTone;
  duration?: number;
  action?: { label: string; onClick: () => void };
}

interface ToastContextValue {
  toast: (input: ToastInput) => string;
  success: (title: string, description?: string) => string;
  error: (title: string, description?: string) => string;
  /** Turns any thrown value into the right toast, with retry when sensible. */
  fromError: (error: unknown, options?: { retry?: () => void }) => string;
  dismiss: (id: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

let counter = 0;
const nextId = (): string => {
  counter += 1;
  return `toast-${counter}`;
};

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastData[]>([]);
  const timers = useRef(new Map<string, ReturnType<typeof setTimeout>>());

  const dismiss = useCallback((id: string) => {
    const timer = timers.current.get(id);
    if (timer) {
      clearTimeout(timer);
      timers.current.delete(id);
    }
    setToasts((current) => current.filter((item) => item.id !== id));
  }, []);

  const toast = useCallback(
    (input: ToastInput): string => {
      const id = nextId();
      const data: ToastData = { id, ...input };
      setToasts((current) => [...current.slice(-(MAX_VISIBLE - 1)), data]);

      const ms = input.duration ?? DEFAULT_DURATION;
      if (ms > 0) {
        timers.current.set(
          id,
          setTimeout(() => dismiss(id), ms),
        );
      }
      return id;
    },
    [dismiss],
  );

  const success = useCallback(
    (title: string, description?: string) =>
      toast(description === undefined ? { title, tone: 'success' } : { title, description, tone: 'success' }),
    [toast],
  );

  const error = useCallback(
    (title: string, description?: string) =>
      toast(description === undefined ? { title, tone: 'danger' } : { title, description, tone: 'danger' }),
    [toast],
  );

  const fromError = useCallback(
    (thrown: unknown, options?: { retry?: () => void }) => {
      const klect = toKlectError(thrown);
      // A duplicate follow/like simply means it already applied — never a toast.
      if (klect.isAlreadyApplied) return '';
      const input: ToastInput = { title: errorMessage(klect), tone: 'danger' };
      if (klect.retryable && options?.retry) {
        input.action = { label: 'Retry', onClick: options.retry };
      }
      return toast(input);
    },
    [toast],
  );

  useEffect(() => {
    const map = timers.current;
    return () => {
      for (const timer of map.values()) clearTimeout(timer);
      map.clear();
    };
  }, []);

  const value = useMemo<ToastContextValue>(
    () => ({ toast, success, error, fromError, dismiss }),
    [dismiss, error, fromError, success, toast],
  );

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div
        aria-live="polite"
        className="pointer-events-none fixed inset-x-0 bottom-0 z-toast flex flex-col items-center gap-2 p-4 sm:items-end"
      >
        {toasts.map((item) => (
          <ToastCard key={item.id} toast={item} onDismiss={dismiss} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const context = useContext(ToastContext);
  if (!context) throw new Error('useToast must be used inside <ToastProvider/>.');
  return context;
}
