import { NextResponse, type NextRequest } from 'next/server';
import type { EmailOtpType } from '@supabase/supabase-js';
import { DEFAULT_SIGNED_IN_ROUTE, routes, safeRedirectTarget } from '@/lib/routes';
import { createClient } from '@/lib/supabase/server';

const ALLOWED_TYPES: readonly EmailOtpType[] = [
  'signup',
  'invite',
  'magiclink',
  'recovery',
  'email_change',
  'email',
];

/**
 * Token-hash landing point (password recovery, email change, magic links).
 * Verifies the OTP server-side so the token never reaches client JavaScript.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const tokenHash = searchParams.get('token_hash');
  const type = searchParams.get('type') as EmailOtpType | null;
  const next = safeRedirectTarget(searchParams.get('next')) ?? DEFAULT_SIGNED_IN_ROUTE;

  if (!tokenHash || !type || !ALLOWED_TYPES.includes(type)) {
    return NextResponse.redirect(`${origin}${routes.signIn}?error=invalid_link`);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });

  if (error) {
    return NextResponse.redirect(
      `${origin}${routes.forgotPassword}?error=${encodeURIComponent(error.message)}`,
    );
  }

  return NextResponse.redirect(`${origin}${next}`);
}
