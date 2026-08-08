# macOS 14 minimum

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The Station uses SwiftUI Observation, MenuBarExtra, and current Accessibility APIs.

## Decision

Set the owner app deployment target to macOS 14.

## Consequences

The implementation can use the required APIs directly, while older macOS versions are out of scope.
