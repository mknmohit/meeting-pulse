# Pre-publication checklist

- [ ] `gitleaks detect --log-opts=--all` is clean over full history.
- [ ] No `.env`, `Config.xcconfig`, certificate, or private key exists in history.
- [ ] Example files contain placeholders only; CI config contains no production host.
- [ ] README documents setup, Accessibility, privacy, known detector limits, and storage eviction.
- [ ] SECURITY.md carries the stable signing-identity constraint and reporting address.
- [ ] LICENSE has the correct year and holder.
- [ ] A fresh clone builds the viewer and Swift packages from example configuration.
- [ ] The Xcode app archive builds Universal 2 with hardened runtime and no App Sandbox.
- [ ] All normalization implementations pass the shared fixture.
- [ ] All fourteen negative RLS tests pass.
- [ ] The two-session concurrency tests pass against the local test superuser URL.
- [ ] The redaction test passes.
- [ ] The privacy capture is attached.
- [ ] The viewer detector reports no findings.
- [ ] `DESIGN.md` describes the built viewer.
- [ ] The built viewer contains the seed key `950bbeef`.
- [ ] Every row in `docs/acceptance-0.1.md` required for release is `PASS`.
