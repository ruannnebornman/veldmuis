# Release Notes Convention

Veldmuis release notes should live in this directory.

## File Naming

- Use one file per release tag
- The file name must match the tag exactly

Examples:

- `v1.4.0.md`
- `2026.04.md`

## Current Versioning Direction

- Legacy stable releases use semantic-version tags like `v1.4.1`
- Monthly automated snapshot releases use `YYYY.MM` tags like `2026.04`
- Keep legacy semver release notes under their exact `v...` tag names
- Keep monthly snapshot release notes under their exact `YYYY.MM` tag names
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
