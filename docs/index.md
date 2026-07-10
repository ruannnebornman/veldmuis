# Veldmuis Documentation

This directory is the source of truth for project documentation that is too
large for the repository README.

## Start Here

- [Architecture](architecture.md)
  High-level package, repository, ISO, installer, and release flow.
- [Security and verification](../SECURITY.md)
  Signing keys, package signatures, release artifacts, and download checks.
- [Support scope](../SUPPORT.md)
  Supported surfaces, unsupported cases, and where to report issues.

## Project Operations

- [Release process](release.md)
  Tag formats, release workflow behavior, published artifacts, and release-note
  expectations.
- [Building packages and ISOs](building.md)
  Local and CI-oriented build flow for packages, repositories, AUR artifacts,
  and ISO images.

## User and Package Notes

- [NVIDIA 580xx support](nvidia.md)
  Current NVIDIA legacy driver support boundary, update risk, and recovery
  notes.
- [Package composition](packages.md)
  Default and optional package groups, including current package defaults.
- [Troubleshooting](troubleshooting.md)
  Basic recovery paths for install, boot, graphics, package, and update issues.
- [Contributing and issue triage](../CONTRIBUTING.md)
  Issue quality bar, triage fields, and pull request expectations.

## Documentation Policy

Keep documentation in this repository until the public manual is large enough
to justify a separate docs site. The website can link here first; a generated
docs site can be added later from these same source files.

Documentation should describe the current repository behavior. Historical
release notes can be used as context, but current package definitions,
installer configuration, workflows, and scripts are the source of truth.
