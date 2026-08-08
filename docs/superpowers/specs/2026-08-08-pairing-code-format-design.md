# Pairing Code Format Design

## Problem

Pairing codes are generated as ten Crockford Base32 characters. The Mac
currently displays them as `XXXXX-XXXXX`, while the share link already carries
the normalized `XXXXXXXXXX` value. This makes the code and link look
inconsistent and can make manual entry confusing.

## Decision

Use ten Crockford Base32 characters with no hyphen as the canonical format on
every surface:

- Mac pairing-code display and copy actions show `XXXXXXXXXX`.
- Viewer share-link fragments continue to use `#code=XXXXXXXXXX`.
- Viewer input continues to accept a legacy `XXXXX-XXXXX` value by normalizing
  it before validation and submission.

The code remains ten characters because reducing it to six would reduce the
entropy from 50 bits to 30 bits for a persistent pairing credential.

## Scope and data flow

`PairingCodeFormat.length` remains `10`. `PairingCodeFormat.display` stops
inserting a separator and returns the raw normalized code. `PairingService`
already normalizes the code when building the share link, so link construction,
database hashes, stored secrets, and RPC validation do not change.

The viewer's existing normalization remains the compatibility boundary:

1. Uppercase the input.
2. Map Crockford confusables (`I`/`L`/`U` to `1`, `O` to `0`).
3. Remove characters outside the Crockford alphabet.
4. Require ten normalized characters.

The viewer input retains its length of eleven characters so a legacy
ten-character code with one hyphen can still be entered. New code is not
rendered with a hyphen anywhere.

## Implementation surfaces

- Update `PairingCodeFormat.display` in MPCore.
- Update MPCore and MPSync tests to expect an unhyphenated display value.
- Preserve the existing viewer normalization tests for hyphenated input and
  the existing unhyphenated share-link behavior.
- Update active pairing-code documentation that describes the display format.

No database migration, RPC change, secret migration, URL migration, or new
formatting abstraction is required.

## Error handling and compatibility

Invalid stored values continue to follow the existing validation path. The
viewer continues to reject inputs whose normalized value is not exactly ten
characters and surfaces the existing invalid-code message. Existing stored
codes remain valid because only presentation changes; their normalized hash and
share-link value are unchanged.

## Validation

Run the existing targeted Swift package tests for MPCore and MPSync, then run
the viewer's existing test, type-check, lint, and production-build commands:

```text
swift test --package-path mac-app/Packages/MPCore
swift test --package-path mac-app/Packages/MPSync
pnpm --dir viewer test
pnpm --dir viewer run check
pnpm --dir viewer run lint
pnpm --dir viewer run build
```

