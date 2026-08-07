import { CONFIG, SUPPORTED_SCHEMA_VERSION } from '../config';
import { ensureSession } from '../lib/auth';
import { COPY } from '../lib/copy';
import {
  checkedLabel,
  effectiveDisplayState,
  readingFromStatus,
  type DisplayState,
  type Reading,
} from '../lib/freshness';
import { isPairingCode, normalizePairingCode } from '../lib/pairingCode';
import { startPoller } from '../lib/poller';
import { fetchPairedStatus } from '../lib/status';
import { supabase } from '../lib/supabase';

declare global {
  interface Window {
    turnstile?: {
      render: (
        element: HTMLElement,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          'error-callback': () => void;
          'expired-callback': () => void;
        },
      ) => string;
      remove: (widgetId: string) => void;
    };
  }
}

export function boot(): void {
  const elements = getElements();
  let reading: Reading | null = null;
  let lastFetchMonotonic = performance.now();
  let lastFetchFailed = false;
  let pairingMessage = '';
  let turnstilePromise: Promise<string> | undefined;

  const render = (): void => {
    const now = performance.now();
    const display = reading ? effectiveDisplayState(reading, now) : 'unpaired';
    const status = reading?.status;
    const offline = !navigator.onLine || lastFetchFailed;
    elements.offline.hidden = !offline;
    elements.pairing.hidden = display !== 'unpaired';
    elements.board.hidden = display === 'unpaired';
    elements.pairingMessage.textContent = pairingMessage;
    if (display === 'unpaired') {
      return;
    }
    renderBoard(display, status, now);
  };

  const renderBoard = (
    display: DisplayState,
    status: Reading['status'] | undefined,
    now: number,
  ): void => {
    const offline = !navigator.onLine || lastFetchFailed;
    const isSchemaTooNew =
      status && status.schemaVersion > SUPPORTED_SCHEMA_VERSION;
    const effective = isSchemaTooNew ? 'unavailable' : display;
    const previous = elements.plate.dataset.state;
    elements.plate.dataset.state = effective;
    if (previous && previous !== effective) {
      elements.plate.classList.remove('is-changing');
      void elements.plate.offsetWidth;
      elements.plate.classList.add('is-changing');
    }
    for (const shape of elements.shapes) {
      shape.hidden =
        shape.dataset.shape !== shapeFor(effective, status?.callOkay === true);
      shape.style.display = shape.hidden ? 'none' : 'block';
    }
    const name = status?.displayName ?? '';
    elements.name.textContent = name;
    elements.name.hidden = !name;
    elements.plate.dataset.hasName = String(Boolean(name));
    if (isSchemaTooNew) {
      elements.headline.textContent = COPY.board.schemaTooNew.headline;
      elements.supporting.textContent = COPY.board.schemaTooNew.supporting;
    } else if (effective === 'available') {
      elements.headline.textContent = name
        ? COPY.board.available.headlineWithName(name)
        : COPY.board.available.headline;
      elements.supporting.textContent = COPY.board.available.supporting;
    } else if (effective === 'busy') {
      elements.headline.textContent = name
        ? COPY.board.busy.headlineWithName(name)
        : COPY.board.busy.headline;
      elements.supporting.textContent = status?.callOkay
        ? COPY.board.callOkay
        : COPY.board.busy.supporting;
    } else {
      elements.headline.textContent = COPY.board.unavailable.headline;
      elements.supporting.textContent = offline
        ? COPY.board.offline.supporting
        : COPY.board.unavailable.supporting;
    }
    elements.stateRegion.setAttribute(
      'aria-label',
      elements.headline.textContent,
    );
    elements.checked.textContent = checkedLabel(
      (now - lastFetchMonotonic) / 1000,
    );
  };

  const read = async (): Promise<void> => {
    lastFetchFailed = false;
    try {
      const { data: session } = await supabase.auth.getSession();
      if (!session.session) {
        reading = null;
        render();
        return;
      }
      const status = await fetchPairedStatus();
      lastFetchMonotonic = performance.now();
      if (!status.paired) {
        reading = null;
      } else {
        reading = readingFromStatus(status, lastFetchMonotonic);
      }
      render();
    } catch {
      lastFetchFailed = true;
      render();
    }
  };

  const poller = startPoller({
    intervalMs: 30_000,
    onTick: read,
  });

  elements.refresh.addEventListener('click', () => {
    elements.refresh.textContent = COPY.rail.checking;
    void poller.refreshNow().finally(() => {
      elements.refresh.textContent = COPY.rail.checkAgain;
    });
  });

  elements.form.addEventListener('submit', (event) => {
    event.preventDefault();
    pairingMessage = '';
    const raw = elements.code.value;
    if (!isPairingCode(raw)) {
      pairingMessage = COPY.pairing.invalid;
      render();
      return;
    }
    elements.submit.disabled = true;
    elements.submit.textContent = COPY.rail.checking;
    void connect(raw)
      .then(() => {
        elements.pairingMessage.textContent = '';
        void read();
      })
      .catch((error: unknown) => {
        pairingMessage =
          error instanceof RateLimitedError
            ? COPY.pairing.rateLimited
            : !navigator.onLine
              ? COPY.pairing.offline
              : COPY.pairing.invalid;
        render();
      })
      .finally(() => {
        elements.submit.disabled = false;
        elements.submit.textContent = COPY.pairing.button;
      });
  });

  const ticker = window.setInterval(render, 1_000);
  window.addEventListener('pagehide', () => {
    window.clearInterval(ticker);
    poller.stop();
  });

  async function connect(rawCode: string): Promise<void> {
    const token = await getTurnstileToken();
    await ensureSession(token);
    const { data, error } = await supabase.rpc('claim_pairing_code', {
      p_code: normalizePairingCode(rawCode),
    });
    if (error) {
      throw error;
    }
    if ((data as { reason?: string }).reason === 'rate_limited') {
      throw new RateLimitedError();
    }
    if (!(data as { ok?: boolean }).ok) {
      throw new Error('PAIR_INVALID_CODE');
    }
    elements.code.value = '';
  }

  async function getTurnstileToken(): Promise<string> {
    if (!turnstilePromise) {
      turnstilePromise = loadTurnstile();
    }
    return turnstilePromise;
  }

  async function loadTurnstile(): Promise<string> {
    const holder = elements.turnstile;
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
    script.async = true;
    document.head.append(script);
    await new Promise<void>((resolve, reject) => {
      script.addEventListener('load', () => resolve(), { once: true });
      script.addEventListener(
        'error',
        () => reject(new Error('TURNSTILE_FAILED')),
        {
          once: true,
        },
      );
    });
    return new Promise<string>((resolve, reject) => {
      if (!window.turnstile) {
        reject(new Error('TURNSTILE_FAILED'));
        return;
      }
      const widget = window.turnstile.render(holder, {
        sitekey: CONFIG.turnstileSiteKey,
        callback: (token) => {
          window.turnstile?.remove(widget);
          holder.replaceChildren();
          resolve(token);
        },
        'error-callback': () => reject(new Error('TURNSTILE_FAILED')),
        'expired-callback': () => reject(new Error('TURNSTILE_EXPIRED')),
      });
    });
  }

  render();
}

class RateLimitedError extends Error {}

function shapeFor(state: DisplayState, callOkay: boolean): string {
  if (state === 'available') return 'disc';
  if (state === 'busy' && callOkay) return 'pennant';
  if (state === 'busy') return 'cone';
  return 'mast';
}

function getElements() {
  const root = document.querySelector<HTMLElement>('[data-viewer]');
  const board = document.querySelector<HTMLElement>('[data-board]');
  const pairing = document.querySelector<HTMLElement>('[data-pairing]');
  const plate = document.querySelector<HTMLElement>('[data-plate]');
  const stateRegion = document.querySelector<HTMLElement>(
    '[data-state-region]',
  );
  const name = document.querySelector<HTMLElement>('[data-name]');
  const headline = document.querySelector<HTMLElement>('[data-headline]');
  const supporting = document.querySelector<HTMLElement>('[data-supporting]');
  const checked = document.querySelector<HTMLElement>('[data-checked]');
  const refresh = document.querySelector<HTMLButtonElement>('[data-refresh]');
  const offline = document.querySelector<HTMLElement>('[data-offline]');
  const form = document.querySelector<HTMLFormElement>('[data-pairing-form]');
  const code = document.querySelector<HTMLInputElement>('[data-code]');
  const submit = document.querySelector<HTMLButtonElement>('[data-connect]');
  const pairingMessage = document.querySelector<HTMLElement>(
    '[data-pairing-message]',
  );
  const turnstile = document.querySelector<HTMLElement>('[data-turnstile]');
  const shapes = [...document.querySelectorAll<HTMLElement>('[data-shape]')];
  if (
    !root ||
    !board ||
    !pairing ||
    !plate ||
    !stateRegion ||
    !name ||
    !headline ||
    !supporting ||
    !checked ||
    !refresh ||
    !offline ||
    !form ||
    !code ||
    !submit ||
    !pairingMessage ||
    !turnstile
  ) {
    throw new Error('Meeting Pulse: viewer markup is incomplete.');
  }
  return {
    root,
    board,
    pairing,
    plate,
    stateRegion,
    name,
    headline,
    supporting,
    checked,
    refresh,
    offline,
    form,
    code,
    submit,
    pairingMessage,
    turnstile,
    shapes,
  };
}
