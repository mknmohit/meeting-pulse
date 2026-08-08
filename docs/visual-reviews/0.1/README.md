# Meeting Pulse owner UI visual review

**Status:** CAPTURED IN DEBUG HARNESS

Captured from the configured debug app in dark mode:

- `onboarding-dark-intro.png`
- `onboarding-dark-permission.png`
- `onboarding-dark-sharing.png`

Captured from the local MPUI visual-review harness:

- `meeting-day-light.png`
- `meeting-day-dark.png`
- `call-okay-day-light.png`
- `call-okay-day-dark.png`
- `generic-day-light.png`
- `generic-day-dark.png`
- `generic-increase-contrast.png`

Representative section captures:

- `sharing-day-dark.png`
- `this-mac-day-dark.png`
- `privacy-day-dark.png`

The harness captures the 2x Retina surface. The screenshots cover the face and
appearance states. The `1x/` directory contains downsampled checks and the
`grayscale/` directory confirms that shape and copy still distinguish the
three faces without color.

To reproduce a review:

```bash
swift run --package-path mac-app/Packages/MPUI MPUIVisualReview \
  --face=meeting --scheme=dark
```

Use `meeting`, `call-okay`, or `generic` for `--face`, and `light` or `dark`
for `--scheme`. Add `--contrast` to exercise the contrast override. Use
`--section=sharing`, `--section=this-mac`, or `--section=privacy` to review
individual Station sections.
