import { NextResponse, type NextRequest } from 'next/server';
import { routes } from '@/lib/routes';
import { createClient } from '@/lib/supabase/server';

/** POST-only so a prefetch or an <img> can never sign someone out. */
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  await supabase.auth.signOut();
  return NextResponse.redirect(`${request.nextUrl.origin}${routes.home}`, { status: 303 });
}
