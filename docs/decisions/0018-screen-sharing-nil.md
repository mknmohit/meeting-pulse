# Screen sharing stays nil in the payload

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The current product does not detect screen sharing and the viewer cannot learn meeting provenance.

## Decision

Set `StatusPayload.screenSharing` to nil at every owner publish site.

## Consequences

The payload remains compatible and no unsupported signal is implied.
