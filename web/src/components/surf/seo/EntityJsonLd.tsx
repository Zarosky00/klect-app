import { entityHref } from '@/lib/entities';
import { SITE_NAME } from '@/lib/env';
import { profileHref } from '@/lib/routes';
import { absoluteUrl } from '@/lib/seo';
import { mediaUrl } from '@/lib/storage';
import {
  closeupCover,
  closeupDescription,
  closeupTitle,
  type CloseupPayload,
} from '@/lib/types';

/**
 * Structured data for the public entity pages.
 *
 * A collection and a subcollection are `CollectionPage`s; an item is a
 * `CreativeWork` that `isPartOf` its shelf. Engagement is emitted as
 * `interactionStatistic` straight from the counter columns — the same numbers
 * the UI shows, never a recount.
 *
 * A `BreadcrumbList` accompanies every page so the three-level hierarchy is
 * legible to a crawler exactly as it is to a reader.
 */

interface Crumb {
  name: string;
  path: string;
}

function interaction(type: string, count: number): Record<string, unknown> {
  return {
    '@type': 'InteractionCounter',
    interactionType: { '@type': type },
    userInteractionCount: Math.max(0, count),
  };
}

function author(payload: CloseupPayload): Record<string, unknown> {
  return {
    '@type': 'Person',
    name: payload.owner.display_name,
    alternateName: `@${payload.owner.username}`,
    url: absoluteUrl(profileHref(payload.owner.username)),
    ...(mediaUrl(payload.owner.avatar_path)
      ? { image: mediaUrl(payload.owner.avatar_path) }
      : {}),
  };
}

function breadcrumbs(payload: CloseupPayload): Crumb[] {
  const crumbs: Crumb[] = [];
  if (payload.entity_type === 'item') {
    crumbs.push({
      name: payload.breadcrumb.collection.name,
      path: entityHref('collection', payload.breadcrumb.collection.id),
    });
    if (payload.breadcrumb.subcollection) {
      crumbs.push({
        name: payload.breadcrumb.subcollection.name,
        path: entityHref('subcollection', payload.breadcrumb.subcollection.id),
      });
    }
  } else if (payload.entity_type === 'subcollection') {
    crumbs.push({
      name: payload.breadcrumb.collection.name,
      path: entityHref('collection', payload.breadcrumb.collection.id),
    });
  }
  crumbs.push({
    name: closeupTitle(payload),
    path: entityHref(payload.entity_type, payload.entity_id),
  });
  return crumbs;
}

function entityGraph(payload: CloseupPayload): Record<string, unknown> {
  const url = absoluteUrl(entityHref(payload.entity_type, payload.entity_id));
  const cover = closeupCover(payload);
  const images =
    payload.entity_type === 'item'
      ? payload.media
          .map((photo) => mediaUrl(photo.storage_path))
          .filter((value): value is string => value !== null)
      : [mediaUrl(cover.path)].filter((value): value is string => value !== null);

  const shared = {
    '@id': url,
    url,
    name: closeupTitle(payload),
    ...(closeupDescription(payload) ? { description: closeupDescription(payload) } : {}),
    ...(images.length > 0 ? { image: images } : {}),
    author: author(payload),
    isAccessibleForFree: true,
    publisher: { '@type': 'Organization', name: SITE_NAME, url: absoluteUrl('/') },
    interactionStatistic: [
      interaction('LikeAction', payload.counts.like),
      interaction('BookmarkAction', payload.counts.save),
      interaction('ShareAction', payload.counts.repost),
      interaction('CommentAction', payload.counts.comment),
      interaction('ViewAction', payload.counts.view),
    ],
    ...(payload.tags.length > 0 ? { keywords: payload.tags.join(', ') } : {}),
  };

  switch (payload.entity_type) {
    case 'collection':
      return {
        ...shared,
        '@type': 'CollectionPage',
        dateCreated: payload.collection.created_at,
        numberOfItems: payload.collection.item_count,
      };
    case 'subcollection':
      return {
        ...shared,
        '@type': 'CollectionPage',
        dateCreated: payload.subcollection.created_at,
        numberOfItems: payload.subcollection.item_count,
        isPartOf: {
          '@type': 'CollectionPage',
          name: payload.breadcrumb.collection.name,
          url: absoluteUrl(entityHref('collection', payload.breadcrumb.collection.id)),
        },
      };
    case 'item':
      return {
        ...shared,
        '@type': 'CreativeWork',
        dateCreated: payload.item.created_at,
        ...(payload.item.brand
          ? { brand: { '@type': 'Brand', name: payload.item.brand } }
          : {}),
        ...(payload.item.model ? { model: payload.item.model } : {}),
        ...(payload.item.year ? { datePublished: String(payload.item.year) } : {}),
        isPartOf: {
          '@type': 'CollectionPage',
          name: (payload.breadcrumb.subcollection ?? payload.breadcrumb.collection).name,
          url: absoluteUrl(
            payload.breadcrumb.subcollection
              ? entityHref('subcollection', payload.breadcrumb.subcollection.id)
              : entityHref('collection', payload.breadcrumb.collection.id),
          ),
        },
      };
    default:
      return { ...shared, '@type': 'CreativeWork' };
  }
}

export function EntityJsonLd({ payload }: { payload: CloseupPayload }) {
  const graph = [
    { '@context': 'https://schema.org', ...entityGraph(payload) },
    {
      '@context': 'https://schema.org',
      '@type': 'BreadcrumbList',
      itemListElement: breadcrumbs(payload).map((crumb, index) => ({
        '@type': 'ListItem',
        position: index + 1,
        name: crumb.name,
        item: absoluteUrl(crumb.path),
      })),
    },
  ];

  return (
    <script
      type="application/ld+json"
      // Serialised server-side from values that came out of Postgres; the
      // `<` escape stops a title from ever closing this tag early.
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(graph).replace(/</g, '\\u003c'),
      }}
    />
  );
}
