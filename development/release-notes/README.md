# Release Notes Convention

Veldmuis release notes should live in this directory.

## File Naming

- Use one file per release tag
- The file name must match the tag exactly

Examples:

- `v1.4.0.md`

## Current Versioning Direction

- The next real public release should be `v1.4.0`
- After that, increment stable releases as normal semantic versions
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
