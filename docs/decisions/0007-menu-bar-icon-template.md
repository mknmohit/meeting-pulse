# Menu bar icon uses template rendering

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The menu bar is rendered against both light and dark system surfaces.

## Decision

Use `symbolRenderingMode(.template)` and shape-carried state instead of a colored raster icon.

## Consequences

The icon follows native contrast and vibrancy behavior, while state remains readable from its silhouette.
