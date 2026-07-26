import type { PostgrestError } from '@supabase/supabase-js';

export type KlectErrorKind =
  | 'unauthorized'
  | 'forbidden'
  | 'suspended'
  | 'not_found'
  | 'messages_blocked'
  | 'duplicate'
  | 'network'
  | 'unknown';

/**
 * A Postgrest failure translated into something the UI can act on.
 * See BACKEND_API.md §5 — the conditions that must be handled explicitly.
 */
export class KlectError extends Error {
  readonly kind: KlectErrorKind;
  readonly code: string | undefined;
  readonly details: string | undefined;
  /** True when retrying the same call could plausibly succeed. */
  readonly retryable: boolean;

  constructor(
    kind: KlectErrorKind,
    message: string,
    options?: { code?: string; details?: string; retryable?: boolean; cause?: unknown },
  ) {
    super(message, options?.cause !== undefined ? { cause: options.cause } : undefined);
    this.name = 'KlectError';
    this.kind = kind;
    this.code = options?.code;
    this.details = options?.details;
    this.retryable = options?.retryable ?? (kind === 'network' || kind === 'unknown');
  }

  /** A unique violation on follows/likes means "already applied" — treat as success. */
  get isAlreadyApplied(): boolean {
    return this.kind === 'duplicate';
  }
}

const SUSPENDED = /account suspended/i;
const NOT_ACCEPTING = /not accepting messages/i;

/**
 * Stable snake_case texts raised by the RPCs (migration 0018's header lists
 * them) → human copy. The raw text is the whole exception message.
 */
const RPC_MESSAGES: Record<
  string,
  { kind: KlectErrorKind; message: string }
> = {
  body_too_long: { kind: 'unknown', message: 'That post is over the length limit.' },
  body_or_attachment_required: {
    kind: 'unknown',
    message: 'Write something or attach something first.',
  },
  bad_target: { kind: 'unknown', message: 'That attachment cannot be shared.' },
  entity_not_found: { kind: 'not_found', message: 'That no longer exists.' },
  reply_not_found: { kind: 'not_found', message: 'The post you replied to is gone.' },
  blocked: { kind: 'forbidden', message: 'You cannot interact with this collector.' },
  bad_media: { kind: 'unknown', message: 'One of those photos could not be attached.' },
  too_many_media: { kind: 'unknown', message: 'A post can carry up to four photos.' },
  media_not_yours: { kind: 'forbidden', message: 'Those photos are not yours to attach.' },
  bad_mode: { kind: 'unknown', message: 'Unknown feed mode. Refresh and try again.' },
};

export function toKlectError(error: unknown): KlectError {
  if (error instanceof KlectError) return error;

  if (error instanceof Error && error.name === 'AbortError') {
    return new KlectError('network', 'Request cancelled.', { retryable: true, cause: error });
  }

  const pg = error as Partial<PostgrestError> | null | undefined;
  const rawMessage = pg?.message ?? (error instanceof Error ? error.message : '');
  const code = pg?.code;

  const rpc = RPC_MESSAGES[rawMessage.trim()];
  if (rpc) {
    return new KlectError(rpc.kind, rpc.message, { code, retryable: false, cause: error });
  }

  if (SUSPENDED.test(rawMessage)) {
    return new KlectError('suspended', 'Your account is suspended.', {
      code,
      retryable: false,
      cause: error,
    });
  }

  if (NOT_ACCEPTING.test(rawMessage)) {
    return new KlectError('messages_blocked', 'This person is not accepting messages.', {
      code,
      retryable: false,
      cause: error,
    });
  }

  switch (code) {
    case '42501':
      // RLS refused: the content went private, was hidden, or you were blocked.
      return new KlectError(
        'forbidden',
        'You can no longer interact with this. Refresh to see the latest.',
        { code, details: pg?.details ?? undefined, retryable: false, cause: error },
      );
    case '23505':
      return new KlectError('duplicate', 'Already applied.', {
        code,
        retryable: false,
        cause: error,
      });
    case 'PGRST301':
    case '401':
      return new KlectError('unauthorized', 'Sign in to do that.', {
        code,
        retryable: false,
        cause: error,
      });
    case 'PGRST116':
      return new KlectError('not_found', 'That no longer exists.', {
        code,
        retryable: false,
        cause: error,
      });
    default:
      break;
  }

  if (
    error instanceof TypeError ||
    /fetch failed|network|Failed to fetch/i.test(rawMessage)
  ) {
    return new KlectError('network', 'You appear to be offline. We will retry.', {
      code,
      retryable: true,
      cause: error,
    });
  }

  return new KlectError('unknown', rawMessage || 'Something went wrong.', {
    code,
    details: pg?.details ?? undefined,
    retryable: true,
    cause: error,
  });
}

/** Human copy for a toast. */
export function errorMessage(error: unknown): string {
  return toKlectError(error).message;
}
