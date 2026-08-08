# Viewer status text visibility

## Context

The paired viewer renders the neutral status message `Meeting status
unavailable` inside the large status plate. The headline currently uses a
viewport-based font size and a character-width cap. On the reported desktop
viewport, the long word `unavailable` is wider than the usable plate content
area, so its right side is clipped instead of remaining fully visible.

The same constraint can affect the named meeting message on smaller viewports.
The fix should preserve the existing visual hierarchy and status behavior while
making the headline responsive to the space it actually has.

## Goals

- Keep every viewer status headline fully visible inside the plate.
- Scale the headline from the plate content width, not only from the viewport.
- Preserve natural multi-line wrapping, centered alignment, and balanced text.
- Apply the same protection to the named meeting headline.
- Keep existing copy, colors, animations, state transitions, and accessibility
  semantics unchanged.

## Non-goals

- Do not change status mapping, freshness handling, polling, or pairing.
- Do not rewrite or shorten user-facing status copy.
- Do not force arbitrary word splitting as the normal layout behavior.
- Do not add a component framework or a new layout dependency.

## Considered approaches

1. **Container-aware sizing with natural wrapping (selected).** Make the
   headline's parent an inline-size query container, allow the headline to use
   the full content width, and use a container-based `clamp()` scale. This
   addresses the source of the overflow and adapts to both desktop and mobile
   layouts.
2. **Smaller viewport-based headline.** Reduce the existing `vw` scale and
   widen the character cap. This is a smaller edit, but it remains dependent on
   viewport dimensions and can regress when plate padding or copy changes.
3. **Forced word breaking.** Keep the current type scale and allow emergency
   word breaks. This guarantees containment but can split status words in an
   undesirable way.

## Design

### Responsive headline container

Update `viewer/src/styles/board.css` so `.plate__content` establishes an
inline-size query container. The generic `.plate__headline` will:

- use `width: 100%` and `max-width: 100%`;
- use a `clamp()` font size based on the container query width with a readable
  minimum and the existing large-display maximum;
- retain `text-wrap: balance`, centered text, and the existing line-height and
  tracking.

Update the `[data-has-name='true']` variant to use the same available-width
constraint and container-aware scale instead of its fixed `12ch` cap and
viewport-only scale. This keeps long display names within the plate without
changing the name copy.

Normal browser wrapping remains preferred. The chosen minimum size and
container-based scale must leave enough width for the longest current status
word at the supported minimum page width.

### Unchanged behavior

No TypeScript or markup changes are required. The existing `data-headline`
element continues to receive the same copy, and the existing `aria-label`
update continues to expose the full status headline to assistive technology.
The loading shell, plate transitions, rail controls, pairing flow, and reduced
motion rules remain unchanged.

## Data flow

```text
existing status read
  -> existing display-state projection
  -> existing headline copy assignment
  -> container-aware CSS sizing and normal wrapping
  -> fully visible status text inside the plate
```

## Failure and accessibility handling

- A long or newly introduced status string must remain contained by the
  headline's available width rather than being clipped by the plate.
- The visual change must not hide, truncate, or replace the accessible headline
  text.
- No error path, stale-state path, or offline path changes its status copy or
  display-state semantics.

## Verification and acceptance

Run the existing viewer checks, tests, lint, and build commands. Perform a
browser smoke check at the reported desktop viewport and at a narrow mobile
viewport.

The change is accepted when `Meeting status unavailable` and a named meeting
headline are fully visible inside the plate at both viewport sizes, with no
horizontal clipping or page overflow, while the existing board state behavior
and accessible headline text remain unchanged.
