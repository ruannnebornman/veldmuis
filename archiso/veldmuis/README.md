# Veldmuis Archiso Profile

This is the first `archiso` scaffold for Veldmuis Linux.

Current intent:

- UEFI-only
- `systemd-boot` ISO boot path
- build against the local `veldmuis-core` and `veldmuis-extra` repos
- install the current Veldmuis desktop package stack onto the live medium

This first profile is deliberately minimal.
It is meant to get a real ISO building against your package model before adding live-session polish or installer automation.

Important:

- the profile uses `packages.x86_64` for the live package set
- the profile ships the minimal `efiboot/loader/` files required by current `mkarchiso`
- the profile is UEFI-only on purpose
- the live image exposes Calamares as the default Veldmuis installer

Use the development helper script from the repo root to build it:

- `development/build-archiso.sh`

Repeatable VM smoke-test notes currently live in the surrounding workspace
docs archive.
