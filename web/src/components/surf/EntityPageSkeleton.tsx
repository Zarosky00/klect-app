import { Skeleton, SkeletonGrid, SkeletonRow } from '@/components/ui/Skeleton';

/**
 * Matches the closeup's real two-column shape — photo left, detail right, child
 * grid below — so the swap-in does not flash (DESIGN_SYSTEM §5).
 */
export function EntityPageSkeleton() {
  return (
    <div className="content-max px-0 md:px-6 md:py-8">
      <div className="overflow-hidden border-line bg-surface-1 md:rounded-xl md:border">
        <div className="grid gap-0 lg:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]">
          <div className="bg-sunken p-4 lg:p-6">
            <Skeleton className="w-full" style={{ aspectRatio: '4 / 3' }} />
          </div>

          <div className="flex flex-col gap-5 p-4 lg:p-6">
            <Skeleton shape="text" className="w-24" />
            <Skeleton className="h-10 w-3/4" />
            <Skeleton shape="text" className="w-full" />
            <Skeleton shape="text" className="w-2/3" />
            <SkeletonRow />
            <Skeleton className="h-10 w-full rounded-full" />
            <div className="grid grid-cols-2 gap-3">
              {[0, 1, 2, 3].map((index) => (
                <Skeleton key={index} shape="text" className="w-full" />
              ))}
            </div>
          </div>
        </div>

        <div className="border-t border-line-subtle p-4 lg:p-6">
          <Skeleton className="mb-4 h-6 w-40" />
          <SkeletonGrid count={8} />
        </div>
      </div>
    </div>
  );
}
