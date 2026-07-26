import '@testing-library/jest-dom/vitest';

// The token env vars are read at module load by `src/lib/env.ts`; tests must
// not depend on a developer's `.env.local` being present.
process.env.NEXT_PUBLIC_SUPABASE_URL ??= 'https://example.supabase.co';
process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??= 'sb_publishable_test';
process.env.NEXT_PUBLIC_SITE_URL ??= 'http://localhost:3000';
