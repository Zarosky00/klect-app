'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/cn';
import { routes } from '@/lib/routes';
import { Icon, type IconName } from '@/components/ui/Icon';

const links: Array<{ href: string; label: string; icon: IconName }> = [
  { href: routes.settings, label: 'Profile', icon: 'user' },
  { href: routes.settingsPrivacy, label: 'Privacy', icon: 'lock' },
  { href: routes.settingsBlocked, label: 'Blocked', icon: 'shield' },
  { href: routes.settingsAppearance, label: 'Appearance', icon: 'sun' },
];

export function SettingsNav() {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Settings"
      className="flex shrink-0 gap-1 overflow-x-auto lg:w-55 lg:flex-col lg:overflow-visible"
    >
      {links.map((link) => {
        const active = pathname === link.href;
        return (
          <Link
            key={link.href}
            href={link.href}
            aria-current={active ? 'page' : undefined}
            className={cn(
              'focus-ring flex items-center gap-2.5 whitespace-nowrap rounded-md px-3 py-2.5',
              'text-body-strong transition-colors dur-fast ease-standard',
              active ? 'bg-surface-2 text-ink' : 'text-ink-2 hover:bg-surface-2 hover:text-ink',
            )}
          >
            <Icon name={link.icon} size="md" filled={active} />
            {link.label}
          </Link>
        );
      })}
    </nav>
  );
}
