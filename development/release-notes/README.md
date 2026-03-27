# Release Notes Convention

Veldmuis release notes should live in this directory.

## File Naming

- Use one file per release tag
- The file name must match the tag exactly

Examples:

- `v1.4.0.md`

## Current Versioning Direction

- Stable public releases use semantic-version tags like `v1.4.1`
- After `v1.4.1`, increment from the latest stable GitHub release
- Do not create new beta or alpha release tags unless the release plan changes deliberately

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
