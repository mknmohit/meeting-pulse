# Decision 0003: Pairing throttle layers

The MVP uses two throttle layers for pairing claims:

- five attempts per authenticated viewer in a fixed 15-minute window;
- a global circuit breaker after 100 failures in a fixed one-hour window.

There is no per-IP table. Supabase's connection pooler does not expose the
viewer's real address reliably through `inet_client_addr()`. An IP layer would
either rate-limit every viewer together or separate nothing. Turnstile,
per-viewer throttling, and the global breaker provide the intended controls
without pretending the pooled address is an end-user identity.
