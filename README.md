# Veldmuis Linux

Crafted in the veld, built in the open.

Veldmuis Linux is an Arch-based KDE Plasma distribution with a signed package flow, a Calamares installer, and a systemd-boot-based install path.

## Official Links

- Website: https://veldmuislinux.org/
- Source, issues, and releases: https://github.com/ruannnebornman/veldmuis
- Issue tracker: https://github.com/ruannnebornman/veldmuis/issues

## Safety

Official Veldmuis communication currently happens through the website and GitHub repository above.

Veldmuis does not currently have official outside affiliations, community platforms, or fundraising pages. If that changes, it will be announced through those official links.

## Repository Layout

- `archiso/veldmuis/`
  Archiso profile used to build the live image
- `development/`
  Helper scripts for local package, repo, ISO, VM, USB, and publishing workflows
- `packages/`
  Package definitions for the Veldmuis stack and installer integration
- `repos/`
  Local pacman repo output generated during development and ignored from Git

## Core Packages

- `veldmuis-release`
- `veldmuis-base`
- `veldmuis-common`
- `veldmuis-boot`
- `veldmuis-displaymanager`
- `veldmuis-desktop-kde`
- `veldmuis-multimedia`
- `veldmuis-branding`
- `veldmuis-desktop`

## Development

The package tree also includes the Calamares packaging and configuration used to build install media:

- `calamares`
- `veldmuis-calamares-config`
- `veldmuis-keyring`
- `veldmuis-mirrorlist`
- `veldmuis-devel`
