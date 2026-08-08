# Pairing codes expire after 30 days

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

Shared links need a bounded lifetime even when the owner does not rotate them manually.

## Decision

Use a 30-day default pairing lifetime.

## Consequences

Old links eventually stop granting access, and the owner must share a new link when the lifetime ends.
