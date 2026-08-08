# Display names trim on commit

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

Whitespace-only names should not create a misleading viewer line.

## Decision

Trim leading and trailing whitespace before publishing a display name and accept an empty result.

## Consequences

Stored and displayed names are stable, and the owner can clear the field naturally.
