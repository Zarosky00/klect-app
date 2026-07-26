import { Skeleton, SkeletonGrid } from '@/components/ui/Skeleton';

/**
 * Matches the real layout's shape: a filter row, then the masonry. A skeleton
 * that does not match the final layout flashes when it swaps out
 * (DESIGN_SYSTEM §5), and a centred spinner on a full page is never acceptable.
 */
export default function SurfLoading() {
  return (
    <div className="content-max flex flex-col gap-4 px-4 sm:px-6">
      <div className="flex items-center gap-2 border-b border-line-subtle py-3">
        {[0, 1, 2, 3].map((index) => (
          <Skeleton key={index} className="h-8 w-24 rounded-full" />
        ))}
      </div>
      <SkeletonGrid count={14} />
    </div>
  );
}
