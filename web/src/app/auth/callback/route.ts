import { NextResponse, type NextRequest } from 'next/server';
import { DEFAULT_SIGNED_IN_ROUTE, routes, safeRedirectTarget } from '@/lib/routes';
import { createClient } from '@/lib/supabase/server';

/**
 * PKCE landing point for email confirmation and OAuth.
 * Exchanges `?code` for a session, then forwards to `?next`.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const code = searchParams.get('code');
  const next = safeRedirectTarget(searchParams.get('next')) ?? DEFAULT_SIGNED_IN_ROUTE;

  if (!code) {
    return NextResponse.redirect(`${origin}${routes.signIn}?error=missing_code`);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(
      `${origin}${routes.signIn}?error=${encodeURIComponent(error.message)}`,
    );
  }

  return NextResponse.redirect(`${origin}${next}`);
}
