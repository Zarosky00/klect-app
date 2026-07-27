/**
 * The route map. Middleware and UI both import from here so a path is never
 * spelled twice.
 */

export const routes = {
  home: '/',
  about: '/about',

  signIn: '/signin',
  signUp: '/signup',
  forgotPassword: '/forgot-password',
  resetPassword: '/reset-password',
  onboarding: '/onboarding',
  suspended: '/suspended',
  authCallback: '/auth/callback',
  authConfirm: '/auth/confirm',
  signOut: '/auth/signout',

  surf: '/surf',
  pulse: '/pulse',
  search: '/search',
  matches: '/matches',
  notifications: '/notifications',
  messages: '/messages',
  create: '/create',

  settings: '/settings',
  settingsPrivacy: '/settings/privacy',
  settingsNotifications: '/settings/notifications',
  settingsBlocked: '/settings/blocked',
  settingsAppearance: '/settings/appearance',
  settingsApp: '/settings/app',

  admin: '/admin',
  adminReports: '/admin/reports',
  adminUsers: '/admin/users',
  adminContent: '/admin/content',
  adminAudit: '/admin/audit',
} as const;

export const profileHref = (username: string): string => `/u/${username}`;
export const collectionHref = (id: string): string => `/c/${id}`;
export const subcollectionHref = (id: string): string => `/s/${id}`;
export const itemHref = (id: string): string => `/i/${id}`;
export const conversationHref = (id: string): string => `/messages/${id}`;
export const closeupHref = (type: string, id: string): string => `/closeup/${type}/${id}`;
/** The post thread page — the X-style destination for a post (W3). */
export const postHref = (id: string): string => `/p/${id}`;

/** Signed-out visitors are redirected to sign-in from these. */
export const PROTECTED_PREFIXES = [
  routes.pulse,
  routes.matches,
  routes.notifications,
  routes.messages,
  routes.create,
  routes.settings,
  routes.onboarding,
  routes.admin,
] as const;

/** Signed-in users are bounced off these back into the app. */
export const AUTH_ONLY_PREFIXES = [
  routes.signIn,
  routes.signUp,
  routes.forgotPassword,
] as const;

/** Reachable while onboarding is still incomplete. */
export const ONBOARDING_EXEMPT_PREFIXES = [
  routes.onboarding,
  routes.suspended,
  '/auth',
  routes.about,
] as const;

export const ADMIN_PREFIX = routes.admin;

export function matchesPrefix(pathname: string, prefixes: readonly string[]): boolean {
  return prefixes.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}

/** Where a signed-in user lands. */
export const DEFAULT_SIGNED_IN_ROUTE: string = routes.surf;

/** Only same-origin, absolute-path redirects survive the round trip. */
export function safeRedirectTarget(value: string | null | undefined): string | null {
  if (!value) return null;
  if (!value.startsWith('/') || value.startsWith('//')) return null;
  return value;
}
