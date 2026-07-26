import { Skeleton, SkeletonRow } from '@/components/ui/Skeleton';

/** The stream's own shape: a composer, then entries. */
export default function PulseLoading() {
  return (
    <div className="mx-auto w-full max-w-160">
      <div className="border-b border-line-subtle px-4 py-4 sm:px-6">
        <SkeletonRow />
      </div>
      {[0, 1, 2, 3].map((index) => (
        <div key={index} className="flex flex-col gap-3 border-b border-line-subtle px-4 py-5 sm:px-6">
          <SkeletonRow />
          <Skeleton className="h-16 w-full" />
        </div>
      ))}
    </div>
  );
}
