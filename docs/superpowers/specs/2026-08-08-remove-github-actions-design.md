# Remove Hosted GitHub Actions

## Goal

Temporarily stop all GitHub-hosted automation for Meeting Pulse so the
repository does not run CI or release jobs through GitHub Actions. Local
development checks and local macOS notarization remain supported.

## Scope

- Delete `.github/workflows/ci.yml`.
- Delete `.github/workflows/release.yml`.
- Remove the GitHub Actions secrets section from `docs/setup/release.md`.
- Update `HANDOFF.md`, `docs/03-implementation-plan.md`, and
  `CONTRIBUTING.md` so they describe local checks rather than hosted CI or
  tag-triggered releases.
- Leave `.env.ci`, local build scripts, signing instructions, and application
  code unchanged.

## Behavior

After the change, pushes and tags will not start repository workflows because
the `.github/workflows` directory will contain no active workflow files.
Developers can still run the existing viewer, Swift, database, secret-scan,
build, signing, and notarization commands locally.

No credentials, certificates, keychains, or environment files will be added,
removed, or committed as part of this change.

## Verification

- Confirm both workflow files are absent.
- Search the active documentation for hosted workflow and repository-secret
  instructions.
- Preserve the local commands in `CONTRIBUTING.md` and `docs/setup/release.md`.
- Do not create a commit; leave the requested changes in the current working
  tree.
