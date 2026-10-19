import { CONFIG } from '../config';
import { ensureSession } from '../lib/auth';
import { readCoupleMode, writeCoupleMode } from '../lib/coupleMode';
import { COPY } from '../lib/copy';
import {
  checkedLabel,
  effectiveDisplayState,
  readingFromStatus,
  type DisplayState,
  type Reading,
} from '../lib/freshness';
import {
  isPairingCode,
  normalizePairingCode,
  pairingCodeFromHash,
} from '../lib/pairingCode';
import { startPoller } from '../lib/poller';
import { fetchPairedStatus } from '../lib/status';
import { supabase } from '../lib/supabase';

type CoupleDisplayState = Exclude<DisplayState, 'unpaired'>;

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
  let fragmentPairingStarted = false;
  let initialHydrationComplete = false;
  let pairingStatus: 'unknown' | 'paired' | 'unpaired' = 'unknown';
  let coupleMode = readCoupleMode();
  let couplePhrase: string | null = null;
  let couplePhraseDisplayState: CoupleDisplayState | null = null;
  let couplePhraseName = '';
  let coupleCopyModule: typeof import('../lib/coupleCopy') | undefined;
  let coupleCopyLoad: Promise<void> | undefined;
  let coupleCopyLoadFailed = false;
  let lastBoardRender: {
    display: DisplayState;
    status: Reading['status'] | undefined;
    offline: boolean;
    coupleMode: boolean;
  } | null = null;

  const render = (): void => {
    if (!initialHydrationComplete) {
      elements.loading.hidden = false;
      elements.board.hidden = true;
      elements.pairing.hidden = true;
      return;
    }
    const now = performance.now();
    const display = reading
      ? effectiveDisplayState(reading, now)
      : pairingStatus === 'unpaired'
        ? 'unpaired'
        : 'generic';
    const status = reading?.status;
    elements.loading.hidden = true;
    elements.pairing.hidden = display !== 'unpaired';
    elements.board.hidden = display === 'unpaired';
    elements.pairingMessage.textContent = pairingMessage;
    if (display === 'unpaired') {
      return;
    }
    if (
      !lastBoardRender ||
      lastBoardRender.display !== display ||
      lastBoardRender.status !== status ||
      lastBoardRender.offline !== (lastFetchFailed || !navigator.onLine) ||
      lastBoardRender.coupleMode !== coupleMode
    ) {
      renderBoard(display, status, now);
      lastBoardRender = {
        display,
        status,
        offline: lastFetchFailed || !navigator.onLine,
        coupleMode,
      };
      return;
    }
    elements.checked.textContent = checkedLabel(
      (now - lastFetchMonotonic) / 1000,
    );
  };

  const renderBoard = (
    display: DisplayState,
    status: Reading['status'] | undefined,
    now: number,
  ): void => {
    const offline = !navigator.onLine || lastFetchFailed;
    const effective = display;
    const previous = elements.plate.dataset.state;
    elements.plate.dataset.state = effective;
    elements.plate.dataset.coupleMode = String(coupleMode);
    syncCoupleModeControl();
    if (previous && previous !== effective) {
      elements.plate.classList.remove('is-changing');
      void elements.plate.offsetWidth;
      elements.plate.classList.add('is-changing');
    }
    for (const shape of elements.shapes) {
      shape.hidden = shape.dataset.shape !== shapeFor(effective);
      shape.style.display = shape.hidden ? 'none' : 'block';
    }
    const name = status?.displayName?.trim() ?? '';
    elements.plate.dataset.hasName = String(Boolean(name));

    if (coupleMode && isCoupleDisplayState(effective) && coupleCopyModule) {
      if (
        couplePhrase === null ||
        couplePhraseDisplayState !== effective ||
        couplePhraseName !== name
      ) {
        couplePhrase = coupleCopyModule.selectCouplePhrase(effective, name);
        couplePhraseDisplayState = effective;
        couplePhraseName = name;
      }
      elements.headline.textContent = couplePhrase;
      elements.supporting.textContent = '';
      elements.supporting.hidden = true;
    } else {
      if (coupleMode && isCoupleDisplayState(effective)) {
        ensureCoupleCopy();
      }
      elements.supporting.hidden = false;
      if (effective === 'meeting') {
        elements.headline.textContent = name
          ? COPY.board.meeting.headlineWithName(name)
          : COPY.board.meeting.headline;
        elements.supporting.textContent = COPY.board.meeting.supporting;
      } else if (effective === 'callOkay') {
        elements.headline.textContent = name
          ? COPY.board.callOkay.headlineWithName(name)
          : COPY.board.callOkay.headline;
        elements.supporting.textContent = COPY.board.callOkay.supporting;
      } else {
        elements.headline.textContent = COPY.board.generic.headline;
        elements.supporting.textContent = offline
          ? COPY.board.generic.offlineSupporting
          : COPY.board.generic.supporting;
      }
    }
    elements.stateRegion.setAttribute(
      'aria-label',
      elements.headline.textContent,
    );
    elements.checked.textContent = checkedLabel(
      (now - lastFetchMonotonic) / 1000,
    );
  };

  const ensureCoupleCopy = (): void => {
    if (coupleCopyModule || coupleCopyLoad || coupleCopyLoadFailed) {
      return;
    }
    coupleCopyLoad = import('../lib/coupleCopy')
      .then((module) => {
        coupleCopyModule = module;
        coupleCopyLoad = undefined;
        lastBoardRender = null;
        render();
      })
      .catch((error: unknown) => {
        coupleCopyLoad = undefined;
        coupleCopyLoadFailed = true;
        coupleMode = false;
        writeCoupleMode(false);
        couplePhrase = null;
        couplePhraseDisplayState = null;
        couplePhraseName = '';
        lastBoardRender = null;
        console.error('Meeting Pulse: Couple mode copy failed to load.', error);
        render();
      });
  };

  const syncCoupleModeControl = (): void => {
    const state = coupleMode ? COPY.rail.coupleModeOn : COPY.rail.coupleModeOff;
    elements.coupleModeToggle.setAttribute('aria-checked', String(coupleMode));
    elements.coupleModeToggle.setAttribute(
      'aria-label',
      COPY.rail.coupleModeAria(coupleMode),
    );
    elements.coupleModeState.textContent = state;
  };

  const read = async (): Promise<void> => {
    lastFetchFailed = false;
    try {
      const { data: session } = await supabase.auth.getSession();
      if (!session.session) {
        pairingStatus = 'unpaired';
        reading = null;
        render();
        return;
      }
      const status = await fetchPairedStatus();
      lastFetchMonotonic = performance.now();
      if (!status.paired) {
        pairingStatus = 'unpaired';
        reading = null;
      } else {
        pairingStatus = 'paired';
        reading = readingFromStatus(status, lastFetchMonotonic);
      }
      render();
    } catch {
      lastFetchFailed = true;
      render();
    } finally {
      if (!initialHydrationComplete) {
        initialHydrationComplete = true;
        render();
      }
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

  elements.coupleModeToggle.addEventListener('click', () => {
    coupleMode = !coupleMode;
    writeCoupleMode(coupleMode);
    couplePhrase = null;
    couplePhraseDisplayState = null;
    couplePhraseName = '';
    render();
  });

  const submitPairing = (raw: string, clearFragment: boolean): void => {
    if (!isPairingCode(raw)) {
      pairingMessage = COPY.pairing.invalid;
      render();
      return;
    }
    elements.submit.disabled = true;
    elements.submit.textContent = COPY.rail.checking;
    void connect(raw)
      .then(() => {
        if (clearFragment) {
          clearPairingFragment();
        }
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
  };

  elements.form.addEventListener('submit', (event) => {
    event.preventDefault();
    pairingMessage = '';
    submitPairing(elements.code.value, false);
  });

  const ticker = window.setInterval(render, 1_000);
  window.addEventListener('pagehide', () => {
    window.clearInterval(ticker);
    poller.stop();
  });

  async function connect(rawCode: string): Promise<void> {
    const { data: session } = await supabase.auth.getSession();
    if (session.session) {
      await ensureSession();
    } else {
      const token = await getTurnstileToken();
      await ensureSession(token);
    }
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
    elements.pairingMessage.textContent = COPY.rail.checking;
    holder.hidden = false;
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

  const submitFragmentPairing = (): void => {
    if (fragmentPairingStarted) {
      return;
    }
    const fragmentCode = pairingCodeFromHash(window.location.hash);
    if (!fragmentCode) {
      return;
    }
    fragmentPairingStarted = true;
    elements.code.value = fragmentCode;
    submitPairing(fragmentCode, true);
  };

  window.addEventListener('hashchange', submitFragmentPairing);
  render();
  submitFragmentPairing();
}

class RateLimitedError extends Error {}

function shapeFor(state: DisplayState): string {
  if (state === 'meeting') {
    return 'cone';
  }
  if (state === 'callOkay') {
    return 'pennant';
  }
  return 'mast';
}

function clearPairingFragment(): void {
  const url = new URL(window.location.href);
  url.hash = '';
  window.history.replaceState(null, '', url);
}

function getElements() {
  const root = document.querySelector<HTMLElement>('[data-viewer]');
  const loading = document.querySelector<HTMLElement>('[data-loading]');
  const board = document.querySelector<HTMLElement>('[data-board]');
  const pairing = document.querySelector<HTMLElement>('[data-pairing]');
  const plate = document.querySelector<HTMLElement>('[data-plate]');
  const stateRegion = document.querySelector<HTMLElement>(
    '[data-state-region]',
  );
  const headline = document.querySelector<HTMLElement>('[data-headline]');
  const supporting = document.querySelector<HTMLElement>('[data-supporting]');
  const checked = document.querySelector<HTMLElement>('[data-checked]');
  const refresh = document.querySelector<HTMLButtonElement>('[data-refresh]');
  const form = document.querySelector<HTMLFormElement>('[data-pairing-form]');
  const code = document.querySelector<HTMLInputElement>('[data-code]');
  const submit = document.querySelector<HTMLButtonElement>('[data-connect]');
  const pairingMessage = document.querySelector<HTMLElement>(
    '[data-pairing-message]',
  );
  const turnstile = document.querySelector<HTMLElement>('[data-turnstile]');
  const coupleModeToggle = document.querySelector<HTMLButtonElement>(
    '[data-couple-mode-toggle]',
  );
  const coupleModeState = document.querySelector<HTMLElement>(
    '[data-couple-mode-state]',
  );
  const shapes = [...document.querySelectorAll<HTMLElement>('[data-shape]')];
  if (
    !root ||
    !loading ||
    !board ||
    !pairing ||
    !plate ||
    !stateRegion ||
    !headline ||
    !supporting ||
    !checked ||
    !refresh ||
    !form ||
    !code ||
    !submit ||
    !pairingMessage ||
    !turnstile ||
    !coupleModeToggle ||
    !coupleModeState
  ) {
    throw new Error('Meeting Pulse: viewer markup is incomplete.');
  }
  return {
    root,
    loading,
    board,
    pairing,
    plate,
    stateRegion,
    headline,
    supporting,
    checked,
    refresh,
    form,
    code,
    submit,
    pairingMessage,
    turnstile,
    coupleModeToggle,
    coupleModeState,
    shapes,
  };
}

function isCoupleDisplayState(
  display: DisplayState,
): display is CoupleDisplayState {
  return display !== 'unpaired';
}
