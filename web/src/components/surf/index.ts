/**
 * The surf layer: the masonry, the gesture contract on top of it, and the
 * closeup those gestures lead to.
 *
 * Every consumer — the surf feed, the public `/c` `/s` `/i` pages, the
 * marketing preview — composes from here so a tile behaves identically
 * wherever it appears.
 */
export { Masonry, masonrySizes, distribute, tileRatio, useMasonryColumns } from './Masonry';
export type { MasonryProps } from './Masonry';

export { SurfTile } from './SurfTile';
export type { SurfTileProps } from './SurfTile';

export { TileGrid } from './TileGrid';
export type { TileGridProps } from './TileGrid';

export { SurfGrid } from './SurfGrid';
export type { SurfGridProps } from './SurfGrid';

export { PeekMenu } from './PeekMenu';
export type { PeekMenuProps, PeekTarget } from './PeekMenu';

export { ImmersiveViewer, photosFromMedia } from './ImmersiveViewer';
export type { ImmersivePhoto, ImmersiveSource, ImmersiveViewerProps } from './ImmersiveViewer';

export {
  tileFromChildItem,
  tileFromChildSubcollection,
  tileFromSearchItem,
  tileFromSibling,
  tileFromSurfCard,
  tileKey,
} from './tile-card';
export type { TileCard, TileCounts, TileOwner, TileViewer } from './tile-card';

export { CloseupView } from './closeup/CloseupView';
export type { CloseupViewProps, CloseupVariant } from './closeup/CloseupView';
export { CommentThread } from './closeup/CommentThread';
export { ItemFacts } from './closeup/ItemFacts';
export { MediaPager } from './closeup/MediaPager';
export { OverflowSheet } from './closeup/OverflowSheet';
export { OwnerRow } from './closeup/OwnerRow';
export { EntityJsonLd } from './seo/EntityJsonLd';
export { SignedOutCta } from './SignedOutCta';
