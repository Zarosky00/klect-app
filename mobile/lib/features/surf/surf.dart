/// The Surf feature's reusable surface.
///
/// Other features import **this** rather than reaching into `widgets/`:
///
/// ```dart
/// import 'package:klect/features/surf/surf.dart';
///
/// KEntityGestureCard(
///   entity: EntityRef.item(id),
///   title: item.title,
///   imageUrl: coverUrl,
///   child: myCard,
/// );
/// ```
///
/// `KEntityGestureCard` gives any card the full gesture contract — tap to the
/// Closeup with no delay, double tap to Immersive, long press for the radial
/// peek — and `KMasonryGrid` gives any screen the same never-reflowing grid the
/// Surf feed uses.
library;

export 'data/closeup_providers.dart' show ImmersiveMedia, closeupProvider, immersiveMediaOf;
export 'data/comments_controller.dart' show CommentsController, CommentsState, commentsProvider;
export 'data/surf_feed_controller.dart'
    show SurfFeedController, SurfFeedState, surfFeedProvider, surfFilterProvider;
export 'widgets/closeup_sections.dart';
export 'widgets/comment_thread.dart' show CommentThread;
export 'widgets/entity_gesture_card.dart' show KEntityGestureCard, KPressFeedback;
export 'widgets/masonry_grid.dart' show KMasonryGrid;
export 'widgets/peek_menu.dart' show KPeekMenu;
export 'widgets/surf_tile.dart' show SurfTile, surfCoverHeroTag;
