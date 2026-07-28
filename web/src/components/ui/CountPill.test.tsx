import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { CountPill } from './CountPill';

describe('CountPill engagement hit targets', () => {
  it('keeps the mutation icon and account-list number independent', () => {
    const toggle = vi.fn();
    const inspect = vi.fn();
    render(
      <CountPill
        icon="repost"
        tone="repost"
        label="Repost or quote"
        count={7}
        countLabel="7 reposts and 2 quotes, view engagement"
        onClick={toggle}
        onCountClick={inspect}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Repost or quote' }));
    expect(toggle).toHaveBeenCalledTimes(1);
    expect(inspect).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: '7 reposts and 2 quotes, view engagement' }));
    expect(inspect).toHaveBeenCalledTimes(1);
    expect(toggle).toHaveBeenCalledTimes(1);
  });

  it('keeps a zero count inspectable when the caller supplies engagement details', () => {
    render(
      <CountPill
        icon="repost"
        label="Repost"
        count={0}
        countLabel="0 reposts and 1 quote, view engagement"
        onClick={() => undefined}
        onCountClick={() => undefined}
      />,
    );

    expect(screen.getByRole('button', { name: '0 reposts and 1 quote, view engagement' })).toBeEnabled();
  });
});
