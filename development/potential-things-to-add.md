# Potential Things To Add

This is a running list of ideas worth considering for Veldmuis, with the main tradeoffs and repo areas to touch.

## Current Candidates

### 1. Multilib Enabled For Pacman

Status:

- `multilib` already appears to be enabled in the repo config at `packages/veldmuis-release/veldmuis.conf`
- `multilib` is also present in the live ISO pacman template at `archiso/veldmuis/pacman.conf.template`

What to verify:

- A fresh installed system actually ends up with `multilib` available in `/etc/pacman.conf`
- The Calamares install path does not accidentally skip or overwrite the `Include = /etc/pacman.conf.d/veldmuis.conf` line
- `pacman` can install 32-bit dependencies after first boot without manual fixes

Likely files if changes are needed:

- `packages/veldmuis-release/veldmuis.conf`
- `packages/veldmuis-calamares-config/veldmuis-calamares-bootstrap.sh`
- `archiso/veldmuis/pacman.conf.template`

Why this matters:

- `multilib` is a prerequisite for a lot of gaming and compatibility packages
- It is especially relevant if `lutris`, Steam, Wine, and NVIDIA users are first-class use cases

### 2. Lutris Installed By Default

Main decision:

- Decide whether `lutris` belongs in the base default desktop experience, or whether it should live in a gaming-focused metapackage later

Things to consider:

- Bigger default install footprint
- Gaming-focused apps are useful for some users, but unnecessary for others
- Lutris is more compelling if `multilib` and the 32-bit graphics/runtime stack work cleanly out of the box
- NVIDIA users are likely to expose edge cases faster, especially around proprietary driver stacks and 32-bit userspace

Likely files if this becomes a default:

- `packages/veldmuis-desktop/PKGBUILD`
- `packages/veldmuis-multimedia/PKGBUILD`

Open question:

- Do we want a future `veldmuis-gaming` metapackage instead of continuously growing the default desktop install?

### 3. Discord Installed By Default

Main decision:

- Decide whether `discord` should be part of the default social/desktop experience, or whether it should stay optional

Things to consider:

- Preinstalling an account-centric proprietary app can be convenient, but not everyone wants it
- It increases the default package surface for every install
- If Veldmuis aims to feel ready-to-use immediately, this may be worth it
- If Veldmuis aims to stay lean, this may be better as an installer option later

Likely files if this becomes a default:

- `packages/veldmuis-desktop/PKGBUILD`

## General Checklist For Future Additions

Before making something default, check:

- Does it increase ISO size or installed size enough to matter?
- Does it need `multilib`, special drivers, or extra repos?
- Is it reliable offline during install, or does it assume internet?
- Does it fit the default Veldmuis identity, or is it better as an optional install choice?
- Does it create extra maintenance burden when Arch packaging changes?
- Should it live in `veldmuis-desktop`, `veldmuis-multimedia`, or a new metapackage?

## Good Next Steps

1. Verify `multilib` on a real fresh install and confirm no manual pacman edits are needed.
2. Decide whether `lutris` should be truly default or grouped into a future gaming metapackage.
3. Decide whether `discord` should be default or an installer-time optional app.
