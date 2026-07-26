import type { ReactNode } from 'react';
import { SettingsNav } from '@/components/chrome/SettingsNav';

export default function SettingsLayout({ children }: { children: ReactNode }) {
  return (
    <div className="content-max px-4 py-8 sm:px-6">
      <h1 className="font-display text-display2 text-ink">Settings</h1>

      <div className="mt-8 flex flex-col gap-8 lg:flex-row">
        <SettingsNav />
        <div className="min-w-0 flex-1">{children}</div>
      </div>
    </div>
  );
}
