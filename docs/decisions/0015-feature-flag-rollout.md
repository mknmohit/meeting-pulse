# Native UI rollout is feature flagged

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The MPUI migration changes the owner surface and needs a release rollback path.

## Decision

Use `ui.macNative`, defaulting to true, to select the native shell.

## Consequences

Operators can revert to the legacy menu shell without rebuilding the app, at the cost of retaining the old code for one release.
