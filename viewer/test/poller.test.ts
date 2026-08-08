// @vitest-environment jsdom

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { startPoller } from '../src/lib/poller';

describe('visibility and focus poller', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  it('keeps one timer and refreshes on the interval', async () => {
    let active = true;
    const onTick = vi.fn(async () => {});
    const poller = startPoller({
      intervalMs: 1_000,
      onTick,
      isActive: () => active,
    });
    await Promise.resolve();
    expect(onTick).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1_000);
    expect(onTick).toHaveBeenCalledTimes(2);
    active = false;
    await vi.advanceTimersByTimeAsync(2_000);
    expect(onTick).toHaveBeenCalledTimes(2);
    poller.stop();
  });

  it('deduplicates an in-flight refresh', async () => {
    let resolve: (() => void) | undefined;
    let active = false;
    const onTick = vi.fn(
      () =>
        new Promise<void>((done) => {
          resolve = done;
        }),
    );
    const poller = startPoller({
      intervalMs: 1_000,
      onTick,
      isActive: () => active,
    });
    active = true;
    const first = poller.refreshNow();
    const second = poller.refreshNow();
    expect(onTick).toHaveBeenCalledTimes(1);
    resolve?.();
    await first;
    await second;
    poller.stop();
  });

  it('runs the first fetch even when the page is not focused', async () => {
    const onTick = vi.fn(async () => {});
    const poller = startPoller({
      intervalMs: 1_000,
      onTick,
      isActive: () => false,
    });
    await Promise.resolve();
    expect(onTick).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(onTick).toHaveBeenCalledTimes(1);
    poller.stop();
  });

  it('honours an explicit refresh while the page is not focused', async () => {
    const onTick = vi.fn(async () => {});
    const poller = startPoller({
      intervalMs: 1_000,
      onTick,
      isActive: () => false,
    });
    await Promise.resolve();
    await poller.refreshNow();
    expect(onTick).toHaveBeenCalledTimes(2);
    poller.stop();
  });

  it('stops ticking after stop, even when forced', async () => {
    const onTick = vi.fn(async () => {});
    const poller = startPoller({
      intervalMs: 1_000,
      onTick,
      isActive: () => true,
    });
    await Promise.resolve();
    poller.stop();
    await poller.refreshNow();
    expect(onTick).toHaveBeenCalledTimes(1);
  });
});
