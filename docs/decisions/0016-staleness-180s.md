# Stale threshold is 180 seconds

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The owner heartbeat and viewer polling are intentionally not realtime.

## Decision

Treat a publication older than 180 seconds as stale on both owner and viewer surfaces.

## Consequences

The two surfaces fail closed together, and any threshold change requires parity updates.
