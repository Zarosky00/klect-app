'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/cn';
import { routes } from '@/lib/routes';
import { Icon, type IconName } from '@/components/ui/Icon';

const links: Array<{ href: string; label: string; icon: IconName }> = [
  { href: routes.admin, label: 'Overview', icon: 'activity' },
  { href: routes.adminReports, label: 'Reports', icon: 'flag' },
  { href: routes.adminUsers, label: 'Users', icon: 'users' },
  { href: routes.adminContent, label: 'Content', icon: 'grid' },
  { href: routes.adminAudit, label: 'Audit log', icon: 'shield' },
];

export function AdminNav() {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Admin"
      className="flex shrink-0 gap-1 overflow-x-auto lg:w-50 lg:flex-col lg:overflow-visible"
    >
      {links.map((link) => {
        const active =
          link.href === routes.admin ? pathname === link.href : pathname.startsWith(link.href);
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
