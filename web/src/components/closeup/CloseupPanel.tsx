'use client';

import { CloseupView } from '@/components/surf/closeup/CloseupView';
import type { CloseupPayload } from '@/lib/types';

/**
 * The single-tap detail view, shared by the intercepted modal and the full page
 * fallback. Both are fed by the same `get_closeup` payload, so a deep link and
 * an in-grid tap render identically.
 *
 * The foundation shipped this file as a shell with the social wiring already
 * correct and an explicit note that a feature agent would replace the body. It
 * now delegates to `@/components/surf/closeup/CloseupView`, which carries the
 * media pager, the metadata, the breadcrumb, the siblings, the owner row with
 * follow, the threaded comments and the overflow — while keeping exactly the
 * props and export this module always had.
 */
export function CloseupPanel({
  payload,
  variant = 'page',
}: {
  payload: CloseupPayload;
  variant?: 'page' | 'modal';
}) {
  return <CloseupView payload={payload} variant={variant} />;
}
