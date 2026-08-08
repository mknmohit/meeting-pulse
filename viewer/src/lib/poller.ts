export type PollerOptions = {
  intervalMs: number;
  onTick: () => Promise<void>;
  isActive?: () => boolean;
};

export function startPoller(options: PollerOptions): {
  stop: () => void;
  refreshNow: () => Promise<void>;
} {
  const isActive =
    options.isActive ??
    (() => document.visibilityState === 'visible' && document.hasFocus());
  let timer: ReturnType<typeof setTimeout> | undefined;
  let stopped = false;
  let inFlight: Promise<void> | undefined;

  const tick = async (force = false): Promise<void> => {
    if (stopped || (!force && !isActive())) {
      return;
    }
    if (inFlight) {
      await inFlight;
      return;
    }
    inFlight = options.onTick().finally(() => {
      inFlight = undefined;
    });
    await inFlight;
  };

  const schedule = (): void => {
    if (stopped) {
      return;
    }
    if (timer !== undefined) {
      clearTimeout(timer);
    }
    timer = setTimeout(async () => {
      await tick();
      schedule();
    }, options.intervalMs);
  };

  const activate = async (force = false): Promise<void> => {
    await tick(force);
    schedule();
  };
  const onVisibility = (): void => {
    if (isActive()) {
      void activate();
    }
  };

  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('focus', onVisibility);
  window.addEventListener('blur', schedule);
  window.addEventListener('pagehide', schedule);
  window.addEventListener('online', onVisibility);
  window.addEventListener('offline', schedule);
  void activate(true);

  return {
    stop: () => {
      stopped = true;
      if (timer !== undefined) {
        clearTimeout(timer);
      }
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('focus', onVisibility);
      window.removeEventListener('blur', schedule);
      window.removeEventListener('pagehide', schedule);
      window.removeEventListener('online', onVisibility);
      window.removeEventListener('offline', schedule);
    },
    refreshNow: async () => {
      await tick(true);
      schedule();
    },
  };
}
