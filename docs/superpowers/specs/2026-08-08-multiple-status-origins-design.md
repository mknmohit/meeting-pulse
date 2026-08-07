# Multiple status origins in the viewer

## Context

The Astro viewer currently requires a single status-origin environment value
and validates it as one HTTPS URL. The value is not consumed by any other
viewer runtime path today, but it is part of the public configuration contract
and is documented in the repository.

The viewer must support deployments reachable through more than one public
domain without changing the existing canonical-origin API used by future
consumers.

## Goals

- Rename the environment variable to `PUBLIC_STATUS_ORIGINS`.
- Accept one or more comma-separated HTTPS URLs.
- Preserve a canonical origin as the first unique normalized URL.
- Expose every validated origin for alias-aware consumers.
- Fail clearly on malformed, insecure, placeholder, empty, or missing values.
- Update all tracked examples, tests, type declarations, and documentation.

## Non-goals

- Do not change generated CSP headers or Supabase connection behavior.
- Do not add runtime origin redirects, link generation, or host allow-list
  behavior; no current viewer path consumes the origin value.
- Do not support the previous singular environment-key name as a fallback.

## Considered approaches

1. **Comma-separated URLs in the existing variable name.** This is simple and
   backwards-compatible with the value format, but leaves a misleading
   singular key.
2. **JSON array in `PUBLIC_STATUS_ORIGINS`.** This is explicit for structured
   data, but is less convenient in `.env` files and more error-prone for
   deployment configuration.
3. **Numbered variables.** Separate variables are readable, but impose an
   arbitrary limit or require dynamic discovery and create more configuration
   surface.

The selected approach is a comma-separated list under the renamed plural key.

## Design

### Configuration parsing

`viewer/src/config.ts` will parse `PUBLIC_STATUS_ORIGINS` by splitting on
commas. Every segment is trimmed and validated using the existing required URL
rules:

- the value is present and is not a placeholder;
- each URL is syntactically valid;
- each URL uses `https:`;
- trailing slashes are normalized away;
- duplicate normalized URLs are removed;
- an empty segment is rejected instead of silently ignored.

The resulting config will expose:

- `CONFIG.statusOrigin`: the first unique normalized URL, retained as the
  canonical origin for existing or future consumers;
- `CONFIG.statusOrigins`: the complete ordered list of unique normalized URLs.

The previous singular environment key is removed completely. It will not be
read, silently migrated, or treated as a fallback.

### Repository updates

All tracked references will use `PUBLIC_STATUS_ORIGINS`, including:

- `viewer/.env.example`;
- `viewer/.env.ci`;
- `viewer/src/env.d.ts`;
- viewer configuration tests;
- the project specification, implementation plan, and audit documentation.

The example will show a comma-separated pair while CI will continue to use one
URL, demonstrating that both forms are supported.

### Error handling

Configuration errors remain fail-fast and use `ConfigurationError`. Errors
identify `PUBLIC_STATUS_ORIGINS` and the relevant failure, rather than
silently discarding invalid entries or falling back to a default domain.

### Verification

Tests will cover:

- one URL;
- multiple comma-separated URLs;
- whitespace and trailing-slash normalization;
- duplicate removal while preserving order;
- missing values;
- empty list entries;
- malformed and non-HTTPS URLs;
- placeholder values;
- the canonical first-origin and full-origin config shape.

The viewer's existing check, lint, formatting, test, and production build
commands will be used for validation after implementation.
