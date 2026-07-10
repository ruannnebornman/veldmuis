# Support

Veldmuis is a small public distribution engineering project. Support is handled
through the GitHub issue tracker on a best-effort basis.

## Supported Surfaces

Use the issue tracker for problems with:

- The current Veldmuis repository source.
- Current GitHub release metadata.
- The current public ISO.
- Veldmuis package definitions under `packages/`.
- The Veldmuis archiso profile.
- The Calamares installer configuration shipped by this repository.
- Veldmuis package repository configuration and keyring packaging.
- Veldmuis release and package build scripts.

Current target scope:

- x86_64.
- UEFI boot.
- systemd-boot.
- KDE Plasma desktop.
- The current package composition documented in [Package Composition](docs/packages.md).

## Out Of Scope

The issue tracker is not the right place for:

- General Arch Linux support unrelated to Veldmuis packaging or configuration.
- BIOS or legacy boot support.
- Unsupported historical ISO downloads.
- Third-party repositories, unofficial mirrors, or unofficial downloads.
- Custom local package mixes that cannot be traced back to Veldmuis packages.
- Hardware-specific issues with no logs, package versions, or reproduction
  details.

## Before Opening An Issue

Check:

- [Troubleshooting](docs/troubleshooting.md)
- [Security and verification](SECURITY.md)
- [Release process](docs/release.md)
- [NVIDIA 580xx support](docs/nvidia.md), if graphics are involved

Include:

- Veldmuis release tag or ISO name.
- Whether this is a live ISO, fresh install, or installed system.
- Hardware or VM details.
- Installer choices, especially graphics and extras.
- Exact command output or logs.
- Whether the issue reproduces after a full `sudo pacman -Syu`.

## Installer Logs

For installer issues from the live session, collect:

```text
/tmp/veldmuis-calamares-debug.log
/tmp/veldmuis-calamares-bootstrap.log
```

Do not paste secrets, private keys, account tokens, or private service URLs into
public issues.

## Security Reports

For security-sensitive issues, follow [Security Policy](SECURITY.md) instead of
posting exploit details publicly.
