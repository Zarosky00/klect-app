import { Skeleton, SkeletonRow, SkeletonText } from '@/components/ui/Skeleton';

/**
 * Instant response to a post tap. The intercepted thread page awaits
 * `get_post_thread` on the server; without this boundary the tap does nothing
 * until the RPC returns. Shaped like the real thread modal so the payload swap
 * does not flash. Server component, tokens only.
 */
export default function ThreadLoading() {
  return (
    <div className="fixed inset-0 z-modal flex items-center justify-center sm:p-4">
      <div className="absolute inset-0 bg-scrim" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Loading"
        aria-busy="true"
        className="relative flex h-dvh w-full flex-col gap-4 overflow-hidden border-line bg-surface-1 p-4 shadow-high sm:h-auto sm:max-h-[92vh] sm:max-w-160 sm:rounded-xl sm:border sm:p-6"
      >
        {/* Author header */}
        <SkeletonRow />
        {/* Body */}
        <SkeletonText lines={3} />
        {/* Media */}
        <Skeleton className="w-full" style={{ aspectRatio: '3 / 2' }} />
        {/* Stats + actions */}
        <div className="flex items-center gap-2 border-y border-line-subtle py-3">
          <Skeleton className="h-6 w-16" />
          <Skeleton className="h-6 w-16" />
          <Skeleton className="h-6 w-16" />
        </div>
        {/* Comments */}
        <SkeletonText lines={3} />
      </div>
    </div>
  );
}
