import type { ReactNode } from 'react';
import { ThemeToggle } from '@/components/chrome/ThemeToggle';
import { Wordmark } from '@/components/chrome/Wordmark';

export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col bg-sunken">
      <header className="flex items-center gap-4 px-4 py-4 sm:px-6">
        <Wordmark />
        <div className="flex-1" />
        <ThemeToggle />
      </header>

      <main
        id="main"
        className="flex flex-1 items-start justify-center px-4 pb-16 pt-4 sm:items-center sm:pt-0"
      >
        {children}
      </main>
    </div>
  );
}
