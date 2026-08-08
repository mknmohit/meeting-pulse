# LSUIElement is true

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

Meeting Pulse is a menu bar utility, not a Dock application.

## Decision

Set `LSUIElement` to true in the app metadata.

## Consequences

The Dock icon stays hidden until a window is opened, matching the owner workflow.
