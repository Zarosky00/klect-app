import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import type { Database } from '@/lib/database.types';
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/lib/env';
import {
  ADMIN_PREFIX,
  AUTH_ONLY_PREFIXES,
  DEFAULT_SIGNED_IN_ROUTE,
  ONBOARDING_EXEMPT_PREFIXES,
  PROTECTED_PREFIXES,
  matchesPrefix,
  routes,
  safeRedirectTarget,
} from '@/lib/routes';

const STAFF_ROLES = new Set(['moderator', 'admin', 'superadmin']);

/**
 * Refreshes the auth session on every request and enforces route access.
 *
 * Cookie handling uses the current `getAll` / `setAll` API. The dance below —
 * write onto `request.cookies`, rebuild the response, write onto
 * `response.cookies` — is what keeps a token refresh visible to both the
 * Server Components rendered downstream *and* the browser.
 */
export async function updateSession(request: NextRequest): Promise<NextResponse> {
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
        // Responses that set auth cookies must never be cached by a CDN.
        for (const [key, value] of Object.entries(headers ?? {})) {
          response.headers.set(key, value);
        }
      },
    },
  });

  // Must run before any response is generated so a refresh can be written back.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname, search } = request.nextUrl;

  const redirectTo = (path: string, params?: Record<string, string>): NextResponse => {
    const url = request.nextUrl.clone();
    url.pathname = path;
    url.search = '';
    for (const [key, value] of Object.entries(params ?? {})) {
      url.searchParams.set(key, value);
    }
    const redirect = NextResponse.redirect(url);
    for (const cookie of response.cookies.getAll()) {
      redirect.cookies.set(cookie);
    }
    return redirect;
  };

  // ── signed out ────────────────────────────────────────────────────────────
  if (!user) {
    if (matchesPrefix(pathname, PROTECTED_PREFIXES)) {
      return redirectTo(routes.signIn, { next: `${pathname}${search}` });
    }
    return response;
  }

  // ── signed in ─────────────────────────────────────────────────────────────
  if (matchesPrefix(pathname, AUTH_ONLY_PREFIXES)) {
    const next = safeRedirectTarget(request.nextUrl.searchParams.get('next'));
    const url = request.nextUrl.clone();
    url.search = '';
    url.pathname = next ?? DEFAULT_SIGNED_IN_ROUTE;
    const redirect = NextResponse.redirect(url);
    for (const cookie of response.cookies.getAll()) {
      redirect.cookies.set(cookie);
    }
    return redirect;
  }

  const needsProfileCheck =
    matchesPrefix(pathname, PROTECTED_PREFIXES) ||
    !matchesPrefix(pathname, ONBOARDING_EXEMPT_PREFIXES);

  if (needsProfileCheck) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('onboarded_at, is_suspended')
      .eq('id', user.id)
      .maybeSingle();

    if (profile?.is_suspended && pathname !== routes.suspended) {
      return redirectTo(routes.suspended);
    }

    if (
      profile &&
      !profile.is_suspended &&
      profile.onboarded_at === null &&
      !matchesPrefix(pathname, ONBOARDING_EXEMPT_PREFIXES) &&
      matchesPrefix(pathname, PROTECTED_PREFIXES)
    ) {
      return redirectTo(routes.onboarding);
    }

    if (!profile?.is_suspended && pathname === routes.suspended) {
      return redirectTo(DEFAULT_SIGNED_IN_ROUTE);
    }
  }

  // ── /admin: staff only ────────────────────────────────────────────────────
  // The server re-checks `is_staff()` inside every admin RPC regardless, so a
  // leaked route exposes nothing. This is the UX guard, not the security one.
  if (pathname === ADMIN_PREFIX || pathname.startsWith(`${ADMIN_PREFIX}/`)) {
    const { data: roles } = await supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', user.id);

    const isStaff = (roles ?? []).some((row) => STAFF_ROLES.has(row.role));
    if (!isStaff) {
      return redirectTo(DEFAULT_SIGNED_IN_ROUTE);
    }
  }

  return response;
}
