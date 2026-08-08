// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  getSession: vi.fn(),
  fetchPairedStatus: vi.fn(),
  rpc: vi.fn(),
  onTick: undefined as (() => Promise<void>) | undefined,
}));

vi.mock('../src/config', () => ({
  CONFIG: {
    turnstileSiteKey: 'test-site-key',
  },
}));

vi.mock('../src/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: mocks.getSession,
    },
    rpc: mocks.rpc,
  },
}));

vi.mock('../src/lib/status', () => ({
  fetchPairedStatus: mocks.fetchPairedStatus,
}));

vi.mock('../src/lib/poller', () => ({
  startPoller: (options: { onTick: () => Promise<void> }) => {
    mocks.onTick = options.onTick;
    return {
      stop: vi.fn(),
      refreshNow: vi.fn(async () => {}),
    };
  },
}));

import { boot } from '../src/ui/board';

function installMarkup(): void {
  document.body.innerHTML = `
    <main data-viewer>
      <section data-loading></section>
      <section data-board hidden>
        <div data-plate data-state="generic">
          <div data-state-region></div>
          <p data-name></p>
          <div data-shape="mast"></div>
          <div data-shape="cone"></div>
          <div data-shape="pennant"></div>
          <h1 data-headline></h1>
          <p data-supporting></p>
        </div>
        <p data-checked></p>
        <button data-refresh type="button"></button>
      </section>
      <section data-pairing hidden>
        <form data-pairing-form>
          <input data-code />
          <button data-connect type="submit"></button>
          <p data-pairing-message></p>
        </form>
        <div data-turnstile></div>
      </section>
    </main>
  `;
}

async function readOnce(): Promise<void> {
  if (!mocks.onTick) {
    throw new Error('Test poller was not initialized.');
  }
  await mocks.onTick();
}

function element(selector: string): HTMLElement {
  const found = document.querySelector<HTMLElement>(selector);
  if (!found) {
    throw new Error(`Missing test element: ${selector}`);
  }
  return found;
}

describe('viewer initial hydration', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    mocks.onTick = undefined;
    installMarkup();
  });

  afterEach(() => {
    window.dispatchEvent(new Event('pagehide'));
    vi.useRealTimers();
  });

  it('keeps the pairing form hidden while the first read is pending', async () => {
    mocks.getSession.mockResolvedValue({ data: { session: {} } });
    let resolveStatus: (() => void) | undefined;
    mocks.fetchPairedStatus.mockReturnValue(
      new Promise((resolve) => {
        resolveStatus = () =>
          resolve({
            paired: true,
            displayName: null,
            state: 'available',
            callOkay: false,
            lastSeenAt: '2026-08-08T05:00:00.000Z',
            serverNow: '2026-08-08T05:00:01.000Z',
            schemaVersion: 1,
          });
      }),
    );

    boot();
    const pendingRead = readOnce();
    await Promise.resolve();
    await Promise.resolve();

    expect(element('[data-loading]').hidden).toBe(false);
    expect(element('[data-pairing]').hidden).toBe(true);
    expect(element('[data-board]').hidden).toBe(true);

    resolveStatus?.();
    await pendingRead;

    expect(element('[data-loading]').hidden).toBe(true);
    expect(element('[data-pairing]').hidden).toBe(true);
    expect(element('[data-board]').hidden).toBe(false);
  });

  it('reveals pairing after a confirmed missing session', async () => {
    mocks.getSession.mockResolvedValue({ data: { session: null } });

    boot();
    await readOnce();

    expect(element('[data-loading]').hidden).toBe(true);
    expect(element('[data-pairing]').hidden).toBe(false);
    expect(element('[data-board]').hidden).toBe(true);
  });

  it('keeps a known session on the neutral board when status fetch fails', async () => {
    mocks.getSession.mockResolvedValue({ data: { session: {} } });
    mocks.fetchPairedStatus.mockRejectedValue(new Error('offline'));

    boot();
    await readOnce();

    expect(element('[data-loading]').hidden).toBe(true);
    expect(element('[data-pairing]').hidden).toBe(true);
    expect(element('[data-board]').hidden).toBe(false);
    expect(element('[data-headline]').textContent).toBe(
      'Meeting status unavailable',
    );
  });

  it('shows the call-okay message when busy and call_okay is true', async () => {
    mocks.getSession.mockResolvedValue({ data: { session: {} } });
    mocks.fetchPairedStatus.mockResolvedValue({
      paired: true,
      displayName: 'Alex',
      state: 'busy',
      callOkay: true,
      lastSeenAt: '2026-08-08T05:00:00.000Z',
      serverNow: '2026-08-08T05:00:01.000Z',
      schemaVersion: 1,
    });

    boot();
    await readOnce();

    expect(element('[data-plate]').dataset.state).toBe('callOkay');
    expect(element('[data-headline]').textContent).toBe(
      "Alex is in Meeting, but it's fine to ring through",
    );
    expect(element('[data-supporting]').textContent).toBe(
      'He said to go ahead and interrupt.',
    );
  });

  it('keeps the busy meeting message when call_okay is false', async () => {
    mocks.getSession.mockResolvedValue({ data: { session: {} } });
    mocks.fetchPairedStatus.mockResolvedValue({
      paired: true,
      displayName: 'Alex',
      state: 'busy',
      callOkay: false,
      lastSeenAt: '2026-08-08T05:00:00.000Z',
      serverNow: '2026-08-08T05:00:01.000Z',
      schemaVersion: 1,
    });

    boot();
    await readOnce();

    expect(element('[data-plate]').dataset.state).toBe('meeting');
    expect(element('[data-headline]').textContent).toBe('Alex is in a meeting');
    expect(element('[data-supporting]').textContent).toBe('Better to wait.');
  });
});
