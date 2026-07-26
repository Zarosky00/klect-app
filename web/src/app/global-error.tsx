'use client';

/**
 * Replaces the root layout when it is the layout itself that threw.
 *
 * THE ONE FILE ALLOWED TO CARRY LITERAL STYLE VALUES. It renders its own
 * `<html>`/`<body>`, which means `globals.css` — and therefore every
 * `--k-*` token — may never have been applied. Referencing a token here would
 * produce an unstyled page precisely when the user most needs a way out.
 * Everything else in `web/` must go through the tokens.
 */
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="en">
      <body
        style={{
          minHeight: '100dvh',
          display: 'grid',
          placeItems: 'center',
          margin: 0,
          fontFamily: 'system-ui, sans-serif',
        }}
      >
        <main style={{ textAlign: 'center', padding: '2rem', maxWidth: '40rem' }}>
          <h1 style={{ fontSize: '1.5rem', marginBottom: '0.5rem' }}>Klect could not start</h1>
          <p style={{ opacity: 0.7, marginBottom: '1.5rem' }}>
            Something failed before the interface loaded.
            {error.digest ? ` Reference: ${error.digest}.` : ''}
          </p>
          <button
            type="button"
            onClick={reset}
            style={{
              padding: '0.75rem 1.25rem',
              borderRadius: '0.5rem',
              border: '1px solid currentColor',
              background: 'transparent',
              color: 'inherit',
              cursor: 'pointer',
            }}
          >
            Try again
          </button>
        </main>
      </body>
    </html>
  );
}
