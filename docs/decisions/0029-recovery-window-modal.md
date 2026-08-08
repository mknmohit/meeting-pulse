# Recovery window is fixed size

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The recovery surface contains a short secret and a small set of actions.

## Decision

Use a non-resizable recovery window.

## Consequences

The secret layout remains stable and the owner cannot accidentally create an oversized exposed surface.
