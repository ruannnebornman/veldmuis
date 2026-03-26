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

### 4. Hosted ISO Builds Instead Of Local-Only Builds

Main decision:

- Move ISO generation off the developer workstation and into a hosted build pipeline, likely GitHub plus either a self-hosted Arch runner or another dedicated remote builder
- Preferred direction is now captured in `development/tagged-release-pipeline-plan.md`: workflow on `main`, trigger on release tags, gate release jobs with approvals, and publish artifacts to Cloudflare R2
- Draft implementation now exists in `.github/workflows/release-iso.yml`, with GitHub environment setup notes in `development/release-environment-setup.md`

Things to consider:

- GitHub-hosted runners are convenient, but `mkarchiso` and the current build flow may require privileges and environment assumptions that do not map cleanly onto stock hosted runners
- Release signing keys should not casually live on a random CI runner; this needs a clear key-management story
- If builds happen remotely, the output location, retention, and release publishing flow should be defined up front
- Current preferred publish behavior is to delete everything under the configured R2 release prefix before uploading the new ISO set, so the bucket does not accumulate old artifacts
- Remote builds would make release generation more repeatable and less dependent on one machine
- This is also a supply-chain and provenance improvement if the workflow produces consistent logs, checksums, signatures, and release artifacts

Open questions:

- Do we want GitHub Actions with a self-hosted runner, or a separate always-on build box that GitHub triggers?
- Should remote CI build unsigned artifacts only, with signing kept on a separate trusted release host?
- Do we want every push to build an ISO, or only tagged releases and manual dispatches?

Likely files if this is implemented:

- `.github/workflows/` for CI/release automation
- `development/build-archiso.sh`
- `development/build-local-repo.sh`
- `development/rebuild-iso-vm.sh`
- `development/key-rotation/`
- `README.md`

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
4. Decide what remote ISO build model Veldmuis should use: GitHub-hosted CI, GitHub-triggered self-hosted runner, or a separate release builder.
