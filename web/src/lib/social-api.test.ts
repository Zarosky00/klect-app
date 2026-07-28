import { describe, expect, it, vi } from 'vitest';
import {
  myProfileReactions,
  deletePost,
  profileDiscussionActivity,
  profilePulseActivity,
  pulseFeedV2,
  socialEngagement,
  type Client,
} from '@/lib/api';

function clientReturning(data: unknown) {
  const rpc = vi.fn().mockResolvedValue({ data, error: null });
  return { client: { rpc } as unknown as Client, rpc };
}

describe('v1.6.3 social RPC adapters', () => {
  it('passes the opaque Pulse cursor through and preserves the page envelope', async () => {
    const cursor = { score: 9.4, sort_at: '2026-07-28T00:00:00Z', id: 'p1' };
    const { client, rpc } = clientReturning({ items: [{ post_id: 'p1' }], has_more: true, next_cursor: cursor });

    const page = await pulseFeedV2(client, { mode: 'foryou', limit: 12, cursor });

    expect(rpc).toHaveBeenCalledWith('pulse_feed_v2', {
      p_mode: 'foryou',
      p_limit: 12,
      p_cursor: cursor,
    });
    expect(page.has_more).toBe(true);
    expect(page.next_cursor).toEqual(cursor);
    expect(page.items).toHaveLength(1);
  });

  it('keeps plain repost and quote totals separate', async () => {
    const { client } = clientReturning({
      summary: { like_count: 8, repost_count: 3, quote_count: 5 },
      items: [],
      has_more: false,
      next_cursor: null,
    });

    const page = await socialEngagement(client, 'post', 'p1', 'repost');
    expect(page.summary).toEqual({ like_count: 8, repost_count: 3, quote_count: 5 });
  });

  it('uses the dedicated public, discussion and owner-only profile endpoints', async () => {
    const { client, rpc } = clientReturning({ items: [], has_more: false, next_cursor: null });

    await profilePulseActivity(client, 'u1', 'quotes');
    await profileDiscussionActivity(client, 'u1', 'surf');
    await myProfileReactions(client, 'save', 'pulse');

    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'profile_pulse_activity_v1',
      'profile_discussion_activity_v1',
      'my_profile_reactions_v1',
    ]);
    expect(rpc.mock.calls[2]?.[1]).not.toHaveProperty('p_user');
  });

  it('deletes posts only through the owner RPC', async () => {
    const { client, rpc } = clientReturning({ deleted: true, post_id: 'p1' });
    await expect(deletePost(client, 'p1')).resolves.toEqual({ deleted: true, post_id: 'p1' });
    expect(rpc).toHaveBeenCalledWith('delete_post', { p_post: 'p1' });
  });
});
