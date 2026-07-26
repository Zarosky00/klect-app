import type { NextConfig } from 'next';

/** Derive the Supabase storage host from the configured URL — never hardcode it. */
const supabaseUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL ?? 'https://dikhuygcwxnrsckqglzg.supabase.co';
const supabaseHost = new URL(supabaseUrl).hostname;

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: supabaseHost,
        pathname: '/storage/v1/**',
      },
      // Seeded demo media are absolute picsum URLs (PROJECT_STATE). The bare
      // host issues a redirect to the fastly host, so both must be allowed.
      { protocol: 'https', hostname: 'picsum.photos' },
      { protocol: 'https', hostname: 'fastly.picsum.photos' },
    ],
    // Blurhash placeholders are painted by <BlurhashImage/>, so Next's own
    // blur placeholder is redundant.
    formats: ['image/webp'],
  },
  experimental: {
    optimizePackageImports: ['framer-motion', 'date-fns'],
  },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'X-DNS-Prefetch-Control', value: 'on' },
        ],
      },
    ];
  },
};

export default nextConfig;
