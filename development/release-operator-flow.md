# Veldmuis Release Operator Flow

This document defines the intended human and CI workflow for Veldmuis releases.

## Release Contract

- Every pushed tag matching `v*` is a release event
- There should not be a separate manual GitHub Release creation step after tagging
- A successful tagged release workflow should:
  - build the ISO
  - publish the ISO artifacts to Cloudflare R2
  - create or update the matching GitHub Release entry

This keeps the mental model simple: if a maintainer creates a release tag, the repository should treat that tag as the source of truth for the release.

## Maintainer Rule

- Do not push `v*` tags casually
- Only create a `v*` tag when the tagged commit is intended to become a published release
- Ordinary work should merge to `main` without tags

## GitHub Enforcement

Recommended GitHub-side enforcement:

- Add a tag ruleset for `v*`
- Restrict creations so only approved maintainers can create release tags
- Restrict updates so release tags cannot be silently moved
- Restrict deletions so release history cannot be quietly removed

Recommended workflow-side enforcement:

- The `Release ISO` workflow should create or update a GitHub Release automatically for every successful `v*` tag
- The workflow should fail if required release notes input is missing

## Release Notes Source Of Truth

Recommended convention:

- Keep one notes file per release tag under `development/release-notes/`
- File name should match the tag exactly

Examples:

- `development/release-notes/v1.4.0.md`
- `development/release-notes/v1.4.1-beta1.md`

Recommended contents:

- short highlights at the top written by a maintainer
- optional upgrade notes or known issues
- generated changelog content appended by GitHub Release notes generation later

This gives Veldmuis both:

- human-written highlights
- machine-generated change summaries from merged pull requests

## Practical Release Steps

1. Merge release-ready work into `main`.
2. Add or update the matching release notes file in `development/release-notes/`.
3. Push the notes commit to `main`.
4. Create and push the release tag from that commit.
5. Approve the protected `release` environment if prompted.
6. Let the workflow publish the artifacts and create the GitHub Release entry.

## Future Workflow Policy

The release workflow should eventually enforce all of the following:

- only `v*` tags trigger release publishing
- the tag must point to a commit on `main`
- the matching `development/release-notes/<tag>.md` file must exist in the tagged commit
- a GitHub Release entry must be created or updated for the tag after a successful publish

At that point, tagging becomes the only required human release action.
