# Revocation takes effect within 30 seconds

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

Viewer polling is intentionally bounded and the backend is not realtime.

## Decision

Treat a revoked pairing as effective within the existing 30-second viewer polling window.

## Consequences

The owner gets predictable revocation without adding realtime infrastructure.
