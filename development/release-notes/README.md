# Release Notes Convention

Veldmuis release notes should live in this directory.

## File Naming

- Use one file per release tag
- The file name must match the tag exactly

Examples:

- `2026.04.md`
- `2026.04.22.md`

## Current Versioning Direction

- Scheduled snapshot releases use `YYYY.MM` tags like `2026.04`
- Manual snapshot releases can use `YYYY.MM.DD` tags like `2026.04.22`
- Keep snapshot release notes under their exact date-based tag names
- Do not create new beta or alpha release tags unless the release plan changes deliberately

## Legacy Release Notes

- `v2026.04.1.md` and `v2026.04.2.md` match historical release tags.
- Keep legacy release-note files only when they match an existing tag exactly.
- Do not use the old `vYYYY.MM.N` pattern for new snapshot releases.

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

The release workflow can later prepend this content to automatically generated GitHub Release notes.
