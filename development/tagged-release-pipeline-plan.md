# Veldmuis Tagged Release Pipeline Plan

This plan describes the preferred release model for Veldmuis: keep the workflow on `main`, build only for release tags, gate the signing and publish path behind approvals, and publish the final ISO to Cloudflare R2.

Implementation status:

- Workflow draft: `.github/workflows/release-iso.yml`
- GitHub setup checklist: `development/release-environment-setup.md`

## Core Decision

- Do not keep ISO build automation on a separate long-lived CI branch
- Keep the workflow file on `main`
- Trigger the release workflow when a release tag is pushed from `main`
- Allow `workflow_dispatch` for manual recovery or test runs

This is the right mental model. The branch does not need to be special. `main` stays the source of truth, and tags decide when a real release build happens.

## Recommended Release Flow

1. Merge release-ready changes into `main`.
2. Create and push a release tag from `main`.
3. GitHub Actions starts the release workflow from the workflow file on `main`.
4. A protected `release` environment requires approval before secrets for signing and publishing are exposed.
5. The workflow builds packages, local repos, and the ISO.
6. The workflow signs using a dedicated Veldmuis release signing subkey, not the primary certifying key.
7. The workflow generates checksums and any release metadata.
8. The workflow uploads the ISO and checksum files to Cloudflare R2.
9. The workflow updates any `latest` pointers or manifests used by the website.
10. The workflow optionally creates or updates a GitHub Release entry with links and checksums.

## Trigger Model

Recommended trigger:

- `push` on tags such as `v*`
- `workflow_dispatch`

Recommended tag examples:

- `v1.3.2-beta1`
- `v1.4.0`
- `v2026.03.26`

Recommended rule:

- Only create release tags from `main`
- Do not trigger ISO builds on every push to `main`
- Reserve the full ISO build-and-publish path for tags and manual dispatch only

## Workflow Shape

### Job 1. Validate source state

- Confirm the tag points to `main` or to a commit already merged into `main`
- Verify the repository is in a releaseable state
- Optionally check version strings, changelog state, and required files

### Job 2. Protected release build

- Runs only after the `release` environment is approved
- Has access to the signing subkey and R2 publish credentials
- Builds packages and local repos
- Builds the ISO
- Produces checksum files

Reason for combining build and signing initially:

- The current Veldmuis pipeline signs packages and repo metadata before ISO generation
- The ISO build consumes that signed local repo
- Splitting build and signing into separate stages is possible later, but would require more refactoring than the first release pipeline needs

### Job 3. Publish

- Uploads the final ISO and checksum files to Cloudflare R2
- Publishes immutable versioned filenames
- Optionally updates stable aliases such as `latest.iso` and `latest.sha256`
- Optionally creates or updates a GitHub Release page

## Signing Model

### Use a dedicated signing subkey

- Do not store the primary long-term certifying key in GitHub
- Create a dedicated signing subkey for CI release signing
- Export only the signing subkey material needed for the workflow
- Keep the primary key offline or on a more trusted machine

### Protect the signing job

- Store signing secrets in a protected GitHub Environment such as `release`
- Require reviewer approval before the protected job can run
- Enable `Prevent self-review` if available for the repository plan
- Keep protected secrets unavailable to ordinary branch and pull request workflows

### Scope and blast radius

- If the CI subkey is ever compromised, rotate and revoke that subkey
- Do not make the CI key your only root of trust
- Document subkey rotation and revocation in the key-rotation workflow

## Cloudflare R2 Publish Model

### Bucket layout

Recommended versioned objects:

- `iso/veldmuis-<version>-x86_64.iso`
- `iso/veldmuis-<version>-x86_64.iso.sha256`
- `iso/veldmuis-<version>-manifest.txt`

Optional stable aliases:

- `iso/latest.iso`
- `iso/latest.iso.sha256`
- `iso/latest-manifest.txt`

### Access model

- Serve downloads from an R2 custom domain such as `downloads.veldmuislinux.org`
- Treat R2 as the public artifact store
- Keep GitHub Actions artifacts short-lived and for debugging only

### Credentials

- Use narrowly scoped R2 credentials limited to the release bucket if long-lived credentials are required
- Keep R2 publish credentials separate from signing secrets
- Rotate publish credentials independently from signing material

## Repository Changes Expected

- Add the release workflow under `.github/workflows/`
- Move or adapt the existing ISO workflow logic from the CI branch into `main`
- Add environment-aware secret handling for the release workflow
- Add release metadata generation for checksums and manifests
- Add documentation in `README.md` or a dedicated release operations doc
- Update key-rotation docs to mention the dedicated CI signing subkey

## Implementation Phases

### Phase 1. Tag-triggered release workflow on `main`

- Move the existing ISO workflow concept into `main`
- Trigger on release tags and `workflow_dispatch`
- Keep GitHub artifact upload for debugging

### Phase 2. Protected signing and R2 publish

- Create a protected `release` environment
- Store the signing subkey and R2 credentials there
- Add approval-gated release build and publish jobs

### Phase 3. Release polish

- Add GitHub Release notes generation
- Add `latest` aliases and a small release manifest in R2
- Add post-release verification checks

### Phase 4. Future hardening

- Consider moving the protected release job to a self-hosted Arch runner if GitHub-hosted execution becomes a trust or reliability concern
- Consider further separating build and signing if the package/repo/ISO pipeline is later refactored for clearer trust boundaries

## Validation Checklist

- Tagging from `main` triggers the workflow and only tagging does so
- Unapproved runs cannot access signing or publish secrets
- Built packages no longer show `Unknown Packager`
- Repo metadata and packages are signed with the dedicated release subkey
- ISO and checksum files land in the expected R2 paths
- Downloaded ISO hashes match the published checksum
- The published release can be reproduced or at least traced to a specific commit, tag, workflow run, and signing fingerprint

## Open Decisions

- Final tag naming scheme
- Whether to also create GitHub Releases automatically
- Whether `latest.iso` should always track the newest tag or only stable releases
- Whether beta and stable releases should publish to separate R2 prefixes
