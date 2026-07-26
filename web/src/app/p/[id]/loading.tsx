import { Skeleton, SkeletonRow, SkeletonText } from '@/components/ui/Skeleton';

/** Full-page thread skeleton — same column as the real page, no dead load. */
export default function PostThreadLoading() {
  return (
    <div className="flex min-h-dvh flex-col">
      <header className="glass sticky top-0 z-sticky flex items-center gap-4 border-b border-line-subtle px-4 py-3 sm:px-6">
        <Skeleton className="h-6 w-28" />
      </header>
      <main className="mx-auto w-full max-w-160 flex-1 px-0 py-0 md:px-6 md:py-8">
        <div className="flex flex-col gap-4 border-line bg-surface-1 p-4 sm:p-6 md:rounded-xl md:border">
          <SkeletonRow />
          <SkeletonText lines={3} />
          <Skeleton className="w-full" style={{ aspectRatio: '3 / 2' }} />
          <div className="flex items-center gap-2 border-y border-line-subtle py-3">
            <Skeleton className="h-6 w-16" />
            <Skeleton className="h-6 w-16" />
            <Skeleton className="h-6 w-16" />
          </div>
          <SkeletonText lines={4} />
        </div>
      </main>
    </div>
  );
}
