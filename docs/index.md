# Veldmuis Documentation

This directory is the source of truth for project documentation that is too
large for the repository README.

If you are preparing a new system, start with the installation guide. If
Veldmuis is already installed, use the updating and troubleshooting guides.

## Install And Use Veldmuis

- [Installing Veldmuis](installing.md)
  Requirements, ISO verification, boot media, installer choices, first boot,
  and installation logs.
- [Updating Veldmuis](updating.md)
  Rolling-release behavior, full system upgrades, reboot guidance, mirrors,
  and NVIDIA precautions.
- [Package composition](packages.md)
  Default and optional package groups, including current package defaults.
- [NVIDIA 580xx support](nvidia.md)
  Current NVIDIA legacy driver support boundary, update risk, and recovery
  notes.
- [Troubleshooting](troubleshooting.md)
  Recovery paths for install, boot, graphics, package, and update issues.

## Support And Trust

- [Support scope](../SUPPORT.md)
  Supported surfaces, unsupported cases, issue requirements, and where to
  report problems.
- [Security and verification](../SECURITY.md)
  Official sources, signing keys, package signatures, release artifacts, and
  download checks.

## Understand And Contribute

- [Architecture](architecture.md)
  High-level package, repository, ISO, installer, and release flow.
- [Contributing and issue triage](../CONTRIBUTING.md)
  Issue quality bar, triage fields, and pull request expectations.

## Build And Release

- [Building packages and ISOs](building.md)
  Local and CI-oriented build flow for packages, repositories, AUR artifacts,
  and ISO images.
- [Release process](release.md)
  Tag formats, release workflow behavior, published artifacts, and release-note
  expectations.

## Documentation Policy

Keep documentation in this repository until the public manual is large enough
to justify a separate docs site. The website can link here first; a generated
docs site can be added later from these same source files.

Documentation should describe the current repository behavior. Historical
release notes can be used as context, but current package definitions,
installer configuration, workflows, and scripts are the source of truth.
