import { Skeleton, SkeletonText } from '@/components/ui/Skeleton';

/**
 * Instant response to a tile tap. The intercepted closeup page awaits
 * `get_closeup` on the server, and without this boundary the tap does nothing
 * until the RPC returns — a dead tap. This shell paints on the next frame,
 * shaped like the real modal (media pane left, meta column right) so the
 * payload swap does not flash.
 *
 * Server component, tokens only — no client JS rides in for a skeleton.
 */
export default function CloseupLoading() {
  return (
    <div className="fixed inset-0 z-modal flex items-center justify-center sm:p-4">
      <div className="absolute inset-0 bg-scrim" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Loading"
        aria-busy="true"
        className="relative flex h-dvh w-full flex-col overflow-hidden border-line bg-surface-1 shadow-high sm:h-auto sm:max-h-[92vh] sm:w-[92vw] sm:max-w-275 sm:rounded-xl sm:border"
      >
        <div className="grid min-h-0 flex-1 gap-0 overflow-hidden lg:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]">
          <div className="bg-sunken p-4 lg:p-6">
            <Skeleton className="w-full" style={{ aspectRatio: '1' }} />
          </div>

          <div className="hidden flex-col gap-5 p-4 lg:flex lg:p-6">
            {/* Breadcrumb chip */}
            <Skeleton className="h-5 w-28" />
            {/* Title + description */}
            <div className="flex flex-col gap-3">
              <Skeleton className="h-8 w-3/4" />
              <SkeletonText lines={2} />
            </div>
            {/* Owner row */}
            <div className="flex items-center gap-3">
              <Skeleton shape="circle" className="size-10" />
              <div className="flex flex-1 flex-col gap-2">
                <Skeleton shape="text" className="w-1/3" />
                <Skeleton shape="text" className="w-1/4" />
              </div>
            </div>
            {/* Action bar */}
            <div className="flex items-center gap-2 border-y border-line-subtle py-3">
              <Skeleton className="h-6 w-12" />
              <Skeleton className="h-6 w-12" />
              <Skeleton className="h-6 w-12" />
              <Skeleton className="h-6 w-12" />
            </div>
            {/* Comments */}
            <SkeletonText lines={3} />
          </div>
        </div>
      </div>
    </div>
  );
}
