# Heartbeat default is 60 seconds

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The viewer stale threshold is 180 seconds and quiet owners still need fresh status.

## Decision

Use a 60-second foreground heartbeat, with cadence changes for overrides and closed windows.

## Consequences

Freshness remains within the product contract, with lower background work when the Station is closed.
