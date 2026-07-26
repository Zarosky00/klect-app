import type { MetadataRoute } from 'next';
import { SITE_URL } from '@/lib/env';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        // Nothing private, personal or staff-only is ever worth crawling.
        disallow: [
          '/admin',
          '/settings',
          '/messages',
          '/notifications',
          '/matches',
          '/pulse',
          '/create',
          '/onboarding',
          '/signin',
          '/signup',
          '/forgot-password',
          '/reset-password',
          '/suspended',
          '/auth/',
        ],
      },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
