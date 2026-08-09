## Summary

<!-- One or two sentences. What does this PR do, and why? -->

## Surfaces touched

- [ ] macOS app
- [ ] Viewer
- [ ] Supabase (migrations / RPCs / RLS)
- [ ] Documentation
- [ ] CI / tooling

## Privacy boundary

<!-- Confirm the change does not leak meeting titles, URLs, participants,
audio, video, screenshots, screen contents, microphone state, or camera
state. If it does, justify and call it out in SECURITY.md. -->

- [ ] No new data leaves the Mac beyond `state`, `call_okay`, optional display
      name, and freshness timestamps.

## Fail-closed state

- [ ] Unknown, stale, or permission-blocked input still renders
      `Status unavailable`, never an assumed `Available`.

## Checks run

<!-- Delete any you didn't run. Add manual scenarios where unit tests do
not cover the change. -->

- [ ] `pnpm run check && pnpm run lint && pnpm test && pnpm run format:check && pnpm run build`
- [ ] `swift test` in each affected package under `mac-app/Packages/`
- [ ] `make lint`
- [ ] `gitleaks detect --no-git --config .gitleaks.toml`
- [ ] Manual scenarios from `docs/acceptance-0.1.md` (if applicable)

## Documentation

<!-- Delete any docs that don't need a change. -->

- [ ] `README.md`, `CONTRIBUTING.md`, `SECURITY.md` updated where behaviour changed
- [ ] User-facing strings live in `docs/copy/deck.md` and `viewer/src/lib/coupleCopyData/`
- [ ] New architectural decisions recorded in `docs/decisions/`

## Privacy self-check

- [ ] No pairing codes, recovery phrases, Supabase session tokens, or
      diagnostics exports included in the diff
- [ ] No meeting titles, URLs, or participants included anywhere
- [ ] `git diff` reviewed for unrelated edits and generated files
