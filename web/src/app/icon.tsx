import { ImageResponse } from 'next/og';
import { tokenColor } from '@/lib/token-colors';

export const size = { width: 32, height: 32 };
export const contentType = 'image/png';

/** Favicon: the K on the near-black base, with the oxblood full stop. */
export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: tokenColor('k-bg-base'),
          color: tokenColor('k-text-primary'),
          fontSize: 22,
          fontWeight: 600,
          borderRadius: 7,
        }}
      >
        K<span style={{ color: tokenColor('k-accent-default') }}>.</span>
      </div>
    ),
    size,
  );
}
