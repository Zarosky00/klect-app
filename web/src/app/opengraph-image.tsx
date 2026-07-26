import { ImageResponse } from 'next/og';
import { SITE_NAME, SITE_TAGLINE } from '@/lib/env';
import { tokenColor } from '@/lib/token-colors';

export const alt = `${SITE_NAME} — ${SITE_TAGLINE}`;
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

/**
 * The default share card. Colours are resolved from the generated token CSS at
 * build time — a raster cannot reference `var(--k-*)`, but it can still be
 * derived from the same source of truth.
 */
export default function OpengraphImage() {
  const base = tokenColor('k-bg-base');
  const ink = tokenColor('k-text-primary');
  const ink2 = tokenColor('k-text-secondary');
  const accent = tokenColor('k-accent-default');
  const line = tokenColor('k-border-subtle');

  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          background: base,
          padding: 72,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
          <span style={{ fontSize: 46, color: ink, letterSpacing: -1 }}>{SITE_NAME}</span>
          <span style={{ fontSize: 46, color: accent }}>.</span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <span style={{ fontSize: 84, color: ink, lineHeight: 1.05, letterSpacing: -2 }}>
            The things you keep say more
          </span>
          <span style={{ fontSize: 84, color: ink, lineHeight: 1.05, letterSpacing: -2 }}>
            than the things you post.
          </span>
        </div>

        <div
          style={{
            display: 'flex',
            gap: 28,
            borderTop: `1px solid ${line}`,
            paddingTop: 28,
            fontSize: 26,
            color: ink2,
          }}
        >
          <span>Collections</span>
          <span style={{ color: accent }}>›</span>
          <span>Subcollections</span>
          <span style={{ color: accent }}>›</span>
          <span>Items</span>
        </div>
      </div>
    ),
    size,
  );
}
