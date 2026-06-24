# Release Notes Convention

Veldmuis release notes should live in this directory.

## File Naming

- Use one file per release tag
- The file name must match the tag exactly

Examples:

- `2026.04.md`
- `2026.04.22.md`
- `2026.04.22.2.md`

## Supported Tags

- Scheduled monthly releases use `YYYY.MM` tags like `2026.04`
- The first manual release on a UTC date uses `YYYY.MM.DD`
- Additional releases on that date use `YYYY.MM.DD.N`, starting at `.2`
- Keep release notes under their exact date-based tag names
- No other release tag format is supported

Release tags are immutable. If a published release needs a correction, fix the
source and create the next release tag for that UTC date. Never move, delete,
or reuse a published tag.

Create release tags only through the release workflow. Direct tag pushes are
unsupported because same-day sequence ordering is validated by the workflow.

Veldmuis retains only the current ISO at the public download URL. Historical
GitHub releases retain notes, checksums, manifests, and commit metadata but do
not link to an ISO.

## Release Checklist

1. Confirm `main` contains every intended change and is pushed.
2. Choose the next unused tag for the UTC date.
3. Add an optional release-note file matching the exact tag.
4. Dispatch the release workflow once.
5. Confirm the tag, manifest commit, ISO filename, and checksum filename match.
6. Confirm the latest download URL serves the newly published ISO.

Do not rerun, replace, or delete a published release. Use the next same-day
sequence when a correction is needed.

## Suggested Structure

```md
# Highlights

- Short user-facing improvements
- Important fixes

# Notes

- Known issues
- Upgrade notes
- Anything maintainers want visible above the generated changelog
```

The release workflow prepends matching content to its generated GitHub release
notes.
