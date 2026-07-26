'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState } from 'react';
import { cn } from '@/lib/cn';
import { profileHref, routes } from '@/lib/routes';
import { Avatar } from '@/components/ui/Avatar';
import { Icon, type IconName } from '@/components/ui/Icon';
import { Sheet } from '@/components/ui/Sheet';
import { Wordmark } from './Wordmark';
import { ThemeToggle } from './ThemeToggle';
import { useNotifications } from '@/providers/notifications-provider';
import { useSession } from '@/providers/session-provider';

interface NavItem {
  href: string;
  label: string;
  icon: IconName;
  authOnly?: boolean;
}

const NAV_ITEMS: NavItem[] = [
  { href: routes.surf, label: 'Surf', icon: 'compass' },
  { href: routes.pulse, label: 'Pulse', icon: 'activity', authOnly: true },
  { href: routes.search, label: 'Search', icon: 'search' },
  { href: routes.matches, label: 'Matches', icon: 'users', authOnly: true },
  { href: routes.notifications, label: 'Alerts', icon: 'bell', authOnly: true },
  { href: routes.messages, label: 'Messages', icon: 'mail', authOnly: true },
];

/**
 * The five mobile tabs. Everything that fell off the bar — Profile, Matches,
 * Settings, Admin, theme, sign out — lives in the top-bar account sheet, so
 * every destination stays reachable on a phone.
 */
const MOBILE_TABS: NavItem[] = [
  { href: routes.surf, label: 'Surf', icon: 'compass' },
  { href: routes.pulse, label: 'Pulse', icon: 'activity' },
  { href: routes.create, label: 'Create', icon: 'plus' },
  { href: routes.notifications, label: 'Alerts', icon: 'bell' },
  { href: routes.messages, label: 'Messages', icon: 'mail' },
];

const MOBILE_TABS_SIGNED_OUT: NavItem[] = [
  { href: routes.surf, label: 'Surf', icon: 'compass' },
  { href: routes.search, label: 'Search', icon: 'search' },
  { href: routes.signIn, label: 'Sign in', icon: 'user' },
];

function isActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}

/**
 * The live unread count on the Alerts item — fed by the shell notifications
 * channel, so it is right from app start, not from the first Alerts visit.
 */
function AlertsBadge({ className }: { className?: string }) {
  const { unread } = useNotifications();
  if (unread <= 0) return null;
  return (
    <span
      aria-label={`${unread} unread`}
      className={cn(
        'tabular grid min-w-4.5 place-items-center rounded-full bg-accent px-1 py-px',
        'text-micro font-semibold leading-none text-ink-on-accent',
        className,
      )}
    >
      {unread > 99 ? '99+' : unread}
    </span>
  );
}

/** Desktop: a left rail. Mobile: the bottom bar below. */
export function AppNavRail() {
  const pathname = usePathname();
  const { user, profile, isStaff } = useSession();

  const items = NAV_ITEMS.filter((item) => !item.authOnly || user);

  return (
    <nav
      aria-label="Primary"
      className="sticky top-0 hidden h-dvh w-60 shrink-0 flex-col gap-1 border-r border-line-subtle px-4 py-5 md:flex"
    >
      <Wordmark className="mb-6 px-2" />

      {items.map((item) => {
        const active = isActive(pathname, item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? 'page' : undefined}
            className={cn(
              'focus-ring flex items-center gap-3 rounded-md px-3 py-2.5 text-body-strong',
              'transition-colors dur-fast ease-standard',
              active ? 'bg-surface-2 text-ink' : 'text-ink-2 hover:bg-surface-2 hover:text-ink',
            )}
          >
            <Icon name={item.icon} filled={active} size="lg" />
            {item.label}
            {item.href === routes.notifications ? <AlertsBadge className="ml-auto" /> : null}
          </Link>
        );
      })}

      {user ? (
        <Link
          href={routes.create}
          className="focus-ring k-pressable mt-4 flex items-center justify-center gap-2 rounded-md bg-accent px-4 py-3 text-body-strong text-ink-on-accent transition-colors dur-fast hover:bg-accent-hover"
        >
          <Icon name="plus" size="md" />
          Create
        </Link>
      ) : (
        <Link
          href={routes.signIn}
          className="focus-ring k-pressable mt-4 flex items-center justify-center gap-2 rounded-md bg-accent px-4 py-3 text-body-strong text-ink-on-accent transition-colors dur-fast hover:bg-accent-hover"
        >
          Sign in
        </Link>
      )}

      <div className="flex-1" />

      {isStaff ? (
        <Link
          href={routes.admin}
          className={cn(
            'focus-ring flex items-center gap-3 rounded-md px-3 py-2.5 text-callout text-ink-2',
            'transition-colors dur-fast hover:bg-surface-2 hover:text-ink',
          )}
        >
          <Icon name="shield" size="md" />
          Admin
        </Link>
      ) : null}

      <Link
        href={routes.settings}
        className="focus-ring flex items-center gap-3 rounded-md px-3 py-2.5 text-callout text-ink-2 transition-colors dur-fast hover:bg-surface-2 hover:text-ink"
      >
        <Icon name="sliders" size="md" />
        Settings
      </Link>

      {profile ? (
        <Link
          href={profileHref(profile.username)}
          className="focus-ring mt-2 flex items-center gap-3 rounded-md px-2 py-2 transition-colors dur-fast hover:bg-surface-2"
        >
          <Avatar
            path={profile.avatar_path}
            name={profile.display_name}
            size="sm"
            verified={profile.is_verified}
          />
          <span className="min-w-0">
            <span className="block truncate text-label text-ink">{profile.display_name}</span>
            <span className="block truncate text-caption text-ink-3">@{profile.username}</span>
          </span>
        </Link>
      ) : null}

      <ThemeToggle className="mt-3 self-start" />
    </nav>
  );
}

/** Mobile chrome. Height comes from the `bottombar` layout token. */
export function AppNavBottomBar() {
  const pathname = usePathname();
  const { user } = useSession();
  const items = user ? MOBILE_TABS : MOBILE_TABS_SIGNED_OUT;

  return (
    <nav
      aria-label="Primary"
      className="glass fixed inset-x-0 bottom-0 z-chrome flex items-stretch border-t border-line-subtle pb-[env(safe-area-inset-bottom)] md:hidden"
      style={{ minHeight: 'var(--k-bottombar-h)' }}
    >
      {items.map((item) => {
        const active = isActive(pathname, item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? 'page' : undefined}
            className={cn(
              'focus-ring flex flex-1 flex-col items-center justify-center gap-0.5 py-2',
              'transition-colors dur-fast ease-standard',
              active ? 'text-ink' : 'text-ink-3',
            )}
          >
            <span className="relative">
              <Icon name={item.icon} filled={active} size="lg" />
              {item.href === routes.notifications ? (
                <AlertsBadge className="absolute -right-2.5 -top-1" />
              ) : null}
            </span>
            <span className="text-micro">{item.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

/**
 * Mobile top bar. Signed in: search plus the account sheet (everything the
 * five tabs cannot hold). Signed out: theme and sign-in. Both bars pad for
 * the device's top notch/status bar (`safe-area-inset-top`).
 */
export function AppTopBar() {
  const { user } = useSession();
  return (
    <header
      className="glass sticky top-0 z-sticky flex items-center gap-3 border-b border-line-subtle px-4 pt-[env(safe-area-inset-top)] md:hidden"
      style={{ minHeight: 'calc(var(--k-topbar-h) + env(safe-area-inset-top))' }}
    >
      <Wordmark size="sm" />
      <div className="flex-1" />
      {user ? (
        <>
          <Link
            href={routes.search}
            aria-label="Search"
            className="focus-ring grid size-9 place-items-center rounded-full text-ink-2 transition-colors dur-fast ease-standard hover:text-ink"
          >
            <Icon name="search" size="lg" />
          </Link>
          <AccountMenu />
        </>
      ) : (
        <>
          <ThemeToggle />
          <Link
            href={routes.signIn}
            aria-label="Sign in"
            className="focus-ring k-pressable inline-flex size-9 items-center justify-center rounded-full bg-accent text-ink-on-accent"
          >
            <Icon name="user" size="md" />
          </Link>
        </>
      )}
    </header>
  );
}

/* ── the account sheet ────────────────────────────────────────────────────── */

function MenuRow({
  href,
  icon,
  label,
  onNavigate,
}: {
  href: string;
  icon: IconName;
  label: string;
  onNavigate: () => void;
}) {
  return (
    <Link
      href={href}
      onClick={onNavigate}
      className={cn(
        'focus-ring flex items-center gap-3 rounded-md px-3 py-3 text-body-strong text-ink',
        'transition-colors dur-fast ease-standard hover:bg-surface-2',
      )}
    >
      <Icon name={icon} size="lg" className="text-ink-2" />
      {label}
    </Link>
  );
}

/**
 * The avatar in the top bar opens this bottom sheet: Profile, Matches,
 * Settings, Admin (staff), the theme control and sign out — the destinations
 * the five-tab bar cannot carry.
 */
function AccountMenu() {
  const { profile, isStaff, signOut } = useSession();
  const [open, setOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  const close = () => setOpen(false);

  return (
    <>
      <button
        type="button"
        aria-label="Account menu"
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => setOpen(true)}
        className="focus-ring k-pressable inline-flex rounded-full"
      >
        <Avatar
          path={profile?.avatar_path}
          name={profile?.display_name}
          size="sm"
          verified={profile?.is_verified ?? false}
        />
      </button>

      <Sheet
        open={open}
        onClose={close}
        title={profile?.display_name ?? 'Account'}
        {...(profile ? { description: `@${profile.username}` } : {})}
      >
        <nav aria-label="Account" className="flex flex-col gap-1">
          {profile ? (
            <MenuRow
              href={profileHref(profile.username)}
              icon="user"
              label="Profile"
              onNavigate={close}
            />
          ) : null}
          <MenuRow href={routes.matches} icon="users" label="Matches" onNavigate={close} />
          <MenuRow href={routes.settings} icon="sliders" label="Settings" onNavigate={close} />
          {isStaff ? (
            <MenuRow href={routes.admin} icon="shield" label="Admin" onNavigate={close} />
          ) : null}

          <div className="mt-2 flex items-center justify-between gap-3 border-t border-line-subtle px-3 pt-4">
            <span className="text-label text-ink-2">Theme</span>
            <ThemeToggle />
          </div>

          <button
            type="button"
            disabled={signingOut}
            onClick={async () => {
              setSigningOut(true);
              try {
                await signOut();
                setOpen(false);
              } finally {
                setSigningOut(false);
              }
            }}
            className={cn(
              'focus-ring mt-2 flex items-center gap-3 rounded-md px-3 py-3 text-left text-body-strong text-danger',
              'transition-colors dur-fast ease-standard hover:bg-danger-subtle',
              'disabled:opacity-[var(--k-opacity-disabled)]',
            )}
          >
            <Icon name={signingOut ? 'spinner' : 'logout'} size="lg" />
            Sign out
          </button>
        </nav>
      </Sheet>
    </>
  );
}
