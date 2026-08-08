# Empty display name uses the unnamed form

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

An owner may prefer not to publish a name.

## Decision

Treat an empty trimmed display name as valid and render the shorter board headline.

## Consequences

The owner can remove a name without an error, and the viewer never sees an empty placeholder.
