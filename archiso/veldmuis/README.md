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

- the profile includes `bootstrap_packages.x86_64`
- the profile ships the minimal `efiboot/loader/` files required by current `mkarchiso`
- the profile is UEFI-only on purpose

Use the top-level helper script to build it:

- `/home/kaazrot/Documents/Code/veldmuis/scripts/build-archiso.sh`
