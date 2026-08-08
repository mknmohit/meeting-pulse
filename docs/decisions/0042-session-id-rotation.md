# Session ID rotates on each app launch

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

A device instance nonce prevents an older process from continuing to publish after a handoff.

## Decision

Use a new session identifier for each app launch while retaining the stable recovery identity.

## Consequences

Stale processes can be superseded safely, while recovery and pairing ownership remain attached to the device.
