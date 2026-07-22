# Veldmuis Archiso Profile

This directory contains the `archiso` profile used to build the Veldmuis
live/install ISO.

## Scope

- UEFI-only ISO boot.
- `systemd-boot` loader entries.
- Local `veldmuis-core` and `veldmuis-extra` package repositories embedded into
  the live image by the build helper.
- Candidate offline builds also embed a signed `veldmuis-offline` repository
  containing the complete official Arch package closure.
- Calamares exposed as the graphical installer in the live Plasma session.
- Normal and safe-graphics live boot entries.

## Design Notes

- The live session uses a passwordless `live` user for installer convenience.
  This is live-media-only behavior.
- The ISO embeds the signed Veldmuis package repositories, but the current
  installer still resolves Arch packages from Arch mirrors.
- `VELDMUIS_ISO_MODE=offline` adds an offline-install marker. In that mode the
  Calamares bootstrap requires all three embedded repositories and never adds
  an HTTP or HTTPS package source. The normal build mode remains the current
  network installer until the offline candidate completes release testing.
- Broader project architecture and support boundaries are documented in
  `../../docs/architecture.md` and `../../SUPPORT.md`.
