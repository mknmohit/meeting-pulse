# Camera and microphone permissions are never requested

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

Meeting detection only needs window structure and Accessibility permission.

## Decision

Do not request camera or microphone access in the owner app.

## Consequences

The privacy boundary stays narrow, and camera or microphone signals cannot be added without a new product decision.
