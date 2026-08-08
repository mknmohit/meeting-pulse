# Recovery code auto-hides after 60 seconds

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

The recovery code can take over publishing and should not remain visible in an unattended window.

## Decision

Hide the recovery code after 60 seconds and reset the timer on interaction.

## Consequences

The code remains available when actively used, while unattended exposure is limited.
