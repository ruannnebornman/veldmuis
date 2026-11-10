# Review Findings And Fix Plan

Working list for the issues found in the full repository review. Items are
ordered by severity and intended to be fixed one at a time.

- Review base: `470e282` (`main`, 2026-11-10)
- Scope: repository source, package definitions, installer, archiso profile,
  release workflows, installed-system defaults, and hosted repository settings.
- This is a maintainer working document, not a support promise.

## How To Use This List

Each item has an ID, priority, evidence, impact, recommended fix, and a
verification step. Fix one item per branch/PR unless two items are inseparable.
Tick the checkbox only when the fix is merged and verified.

## Priority Legend

| Priority | Meaning |
| --- | --- |
| P0 | Fix before handing the image to another person. Breaks fresh installs or is a security default. |
| P1 | Should fix before a public release or before calling the project finished. |
| P2 | Important hardening, reliability, or packaging quality. |
| P3 | Housekeeping, documentation, or cosmetic. |

## Suggested Order

1. R1 fresh-install login shell
2. R2 screen lock, R3 KWallet, R4 CPU/power defaults, R5 mpv defaults
3. R6 signing approval gate
4. R7/R8 publication ordering
5. R9 USB write safety, R10 EFI fallback, R11 swap default
6. R12–R14 packaging and live-image quality
7. R15–R21 security and supply-chain hardening
8. R22–R30 documentation and housekeeping

## Confirmed Decisions

| ID | Decision | Status |
| --- | --- | --- |
| R1 | Keep the `fish` dependency; add it to `veldmuis-common`. | Done in PR #95 |
| R2 | Enable autolock and lock-on-resume with a 10-minute timeout. | Done in PR #96 |
| R3 | Keep KWallet disabled and document the intended secrets workflow. | Done in PR #97 |
| R4 | Remove the custom CPU service; set performance once on first boot through PPD; remove forced PowerDevil overrides. | Done in PR #100 (stacked on #96) |
| R5 | Remove `volume=0` and `loop-file=inf` from the system mpv config. | Done in PR #98 |
| R6 | Accept the merge-to-main signing model and document the trade-off. | Pending |
| R7 | Publish and verify the new release/channel first, then prune older releases. | Pending |
| R8 | Upload new payloads, upload/verify the new database, then delete unreferenced old payloads. | Pending |
| R9 | Require typed device confirmation, check removable, allow explicit `--force`. | Pending |
| R10 | Enable the EFI fallback loader. | Pending |
| R11 | Raise the minimum RAM to 8 GiB; keep no swap. | Pending |
| R12 | Leave the opt-in sync integration as-is and document the caveat; downgrade to P3. | Pending |
| R13 | Keep the `/etc/os-release` override, add `VERSION_ID=rolling`, document `/usr/lib`. | Pending |
| R14 | Make muis the default terminal everywhere; remove konsole from the default set but keep it installable. | Pending |
| R15 | Document the Arch database-signature limitation in `SECURITY.md`. | Pending |
| R16 | Deferred: handle the independent trust anchor through the website at the end. | Deferred |
| R17 | Disable Actions PR approval and enable Dependabot alerts/security updates. | Pending |
| R18 | Document the PAT and its reason; no token change now. | Pending |
| R19 | Use the runner’s preinstalled AWS CLI and fail if absent. | Pending |
| R20 | Validate the NVIDIA dependency package before the root install and require recipe-review discipline. | Pending |
| R21 | Add a scheduled Calamares upstream watcher and document the fork. | Pending |
| R22 | Fix the docs and the extras QML label. | Pending |
| R23 | Document that historical metadata is retained but ISO bytes are pruned. | Pending |
| R24 | Document the reproducibility limitation. | Pending |
| R25 | Keep Secure Boot documented and add a visible installer/download warning. | Pending |
| R26 | Document the network-installer limitation. | Pending |
| R27 | Document the SBOM as a package inventory. | Pending |
| R28 | Document the signed manifest as the trust anchor, not the tag. | Pending |
| R29 | Add a failed-publication runbook entry. | Pending |
| R30 | Add conservative systemd hardening to the mirror refresh service. | Pending |

---

## P0 — Fix Before Handing It To Anyone

### R1. Fresh installs use `/usr/bin/fish` but fish is not installed

- [ ] Fix and verify on a clean VM install

**Evidence**

- `packages/veldmuis-calamares-config/modules/users.conf:28` sets
  `shell: "/usr/bin/fish"`.
- No package in the `veldmuis-desktop` dependency chain depends on `fish`:
  `packages/veldmuis-common/PKGBUILD`, `packages/veldmuis-desktop-kde/PKGBUILD`,
  and `packages/veldmuis-calamares-config/installer-package-sets.sh` do not
  include it.
- On an installed system, `pacman -Qi fish` reports
  `Install Reason: Explicitly installed` and `Required By: None`.

**Impact**

`useradd -s /usr/bin/fish` creates the user, but the login shell does not
exist. The GUI session may still start, but TTY/SSH login, `su -`, `sudo -i`,
and anything using `$SHELL` will fail. This is the first issue a friend will
hit on a fresh install.

**Recommended fix**

Add `fish` to the `depends` array in `packages/veldmuis-common/PKGBUILD` and
bump `pkgrel`. Update the package list in `docs/packages.md`. Alternatively,
set the Calamares shell back to `/bin/bash` until fish is a real dependency.

**Verification**

Install from a fresh VM, log in on a TTY, and confirm:

```sh
getent passwd "$USER"
echo "$SHELL"
fish --version
sudo -i true
```

### R2. Screen locking is disabled globally by default

- [ ] Fix

**Evidence**

`packages/veldmuis-branding/kscreenlockerrc:2-4`:

```ini
Autolock=false
LockOnResume=false
Timeout=0
```

Installed to `/etc/xdg/kscreenlockerrc`, so every new user inherits it.

**Impact**

An unattended session never locks, including after resume. This is a security
default, not a cosmetic preference.

**Recommended fix**

Set `Autolock=true`, `LockOnResume=true`, and a sane `Timeout` (for example
300 seconds). Keep the live ISO unlocked through the live profile, not through
the installed-system branding package.

**Verification**

Fresh user session: lock manually, then confirm idle and resume both lock.

---

## P1 — Should Fix Before A Public Release

### R3. KWallet is disabled globally by default

- [ ] Fix or document the decision

**Evidence**

`packages/veldmuis-branding/kwalletrc:2-3` sets `Enabled=false` and
`First Use=false`.

**Impact**

Secrets handling degrades. Combined with shipping `ksshaskpass`, users either
get repeated prompts or weaker fallback storage.

**Recommended fix**

Enable KWallet by default, or document explicitly why Veldmuis disables it and
what users should use instead.

### R4. CPU is forced to “performance” by default and fights power-profiles-daemon

- [ ] Fix

**Evidence**

- `packages/veldmuis-desktop-kde/cpu-max-performance.service:8` sets
  `powerprofilesctl set performance` and writes `performance` to
  `scaling_governor` and `energy_performance_preference`.
- Enabled by `packages/veldmuis-desktop-kde/veldmuis-desktop-kde.install:4`
  and `packages/veldmuis-calamares-config/modules/services-systemd.conf`.
- `packages/veldmuis-branding/powerdevilrc:2-3,6-7,10-11` disables dim and
  suspend on AC.

**Impact**

Laptops run hot, throttle, and lose battery life. The unit also conflicts with
`power-profiles-daemon`, which is enabled at the same time.

**Recommended fix**

Do not enable the unit by default. Make it an explicit opt-in package or a
user-selected performance profile. Do not override PPD unconditionally, and
guard the sysfs writes against missing cpufreq/EPP paths.

### R5. `mpv` defaults are muted and loop forever

- [ ] Fix

**Evidence**

`packages/veldmuis-multimedia/mpv.conf:2,5`:

```ini
volume=0
loop-file=inf
```

**Impact**

Every video opened with mpv starts muted and loops forever. This is a
surprising system-wide default.

**Recommended fix**

Remove both settings, or make them opt-in/user-local.

### R6. Merge to `main` is effectively a signing operation

- [ ] Fix

**Evidence**

- `.github/workflows/package-repo-refresh.yml` runs daily with
  `environment: release` and signs/publishes when `main` changes.
- The hosted `release` environment currently has only a branch policy and no
  required reviewers (checked through the GitHub API on 2026-11-10).
- The release signing key and R2 write credentials are stored as environment
  secrets.

**Impact**

A compromised maintainer account, or any merged PKGBUILD change, can result in
signed and published packages without a separate human approval step.

**Recommended fix**

Pick one:

- Require a reviewer/manual approval on the `release` environment.
- Split signing into a separate manually dispatched workflow.
- Add a second maintainer or a release approver.
- Move the key to an offline or hardware-backed signing step.

**Verification**

Confirm the environment protection rule in GitHub shows the intended approval
gate, then run the refresh path end to end.

### R7. Release storage is pruned before the new release is published

- [ ] Fix

**Evidence**

- `.github/workflows/release.yml:454` runs `prune-release-storage.sh`.
- `.github/workflows/release.yml:456` publishes the new release afterwards.
- `development/prune-release-storage.sh:57-66` deletes every release object
  outside the new tag.
- `development/check-release-policy.sh` enforces this order.

**Impact**

The public channel still points at the previous release until publish promotes
the new one. If publish fails, is cancelled, or the runner dies after prune,
the channel points at deleted objects and the download is broken.

**Recommended fix**

Upload and verify the new immutable objects first, promote and verify the
channel, then prune older releases. Keep at least the previous release until
the new channel is verified.

### R8. Package repo sync deletes payloads before the new database is uploaded

- [ ] Fix

**Evidence**

`development/publish-r2-package-repo.sh:220-250` force-copies payloads, runs
`s3 sync --delete` (lines 236-240), then uploads the new DB/files. If the DB
upload fails, the old DB can reference deleted package blobs.

**Impact**

A failed database upload can leave clients with a database that references
missing package files.

**Recommended fix**

Upload new payloads, upload and verify the new database, then delete payloads
the new database no longer references. Keep the previous database until the new
one is verified.

### R9. USB write helper has no confirmation and no removable-device check

- [ ] Fix

**Evidence**

`development/rebuild-iso-usb.sh:213` only checks `-b`, and line 222 runs `dd`
to the target without an interactive confirmation. Auto-detection selects the
only USB disk automatically.

**Impact**

A typo in `USB_DEVICE`, or an unintended single USB disk, can destroy the wrong
device. A value like `/dev/nvme0n1` passes the current check.

**Recommended fix**

Require the operator to type the target device path, or at least verify
`/sys/block/<device>/removable` and refuse non-removable block devices.

### R10. EFI fallback bootloader is disabled

- [ ] Fix

**Evidence**

`packages/veldmuis-calamares-config/modules/bootloader.conf:14` sets
`installEFIFallback: false`.

**Impact**

If the firmware will not accept the NVRAM boot entry (full NVRAM, buggy
firmware), the installed system is unbootable.

**Recommended fix**

Enable the fallback loader for the installed system.

### R11. Default install has no swap while the minimum RAM is 2 GiB

- [ ] Fix

**Evidence**

`packages/veldmuis-calamares-config/modules/partition.conf:22` sets
`initialSwapChoice: none`, while `modules/welcome.conf` requires 2 GiB RAM.

**Impact**

KDE Plasma on a 2 GiB machine with no swap is likely to OOM.

**Recommended fix**

Default to a swap file or zram, or raise the documented RAM minimum.

---

## P2 — Hardening, Reliability, Packaging Quality

### R12. `veldmuis-sync` edits files owned by other packages

- [ ] Fix

**Evidence**

`packages/veldmuis-sync/veldmuis-sync.install` appends to `/etc/hosts` and
patches `/usr/lib/firefox/distribution/distribution.ini`. The
`syncthing.localhost` alias is unnecessary because `.localhost` already
resolves to loopback.

**Impact**

Firefox upgrades can overwrite the change, `pacman -Qkk firefox` reports it,
and the change is not reverted on package removal.

**Recommended fix**

Use a Firefox policy file under `/etc/firefox/policies` instead of editing the
distribution file. Drop the `/etc/hosts` edit and use `127.0.0.1:8384`.

### R13. `/etc/os-release` and `/usr/lib/os-release` disagree

- [ ] Fix or document

**Evidence**

`packages/veldmuis-release/PKGBUILD` installs a regular file at
`/etc/os-release`. On an installed system, `/usr/lib/os-release` still says
Arch Linux. `VERSION_ID` and `LOGO` are also missing.

**Impact**

Most tools read `/etc/os-release` first, but some read `/usr/lib/os-release`.
A reviewer will notice the mismatch.

**Recommended fix**

Document the override, or ship a consistent pair. Add `VERSION_ID` and `LOGO`
where appropriate.

### R14. Live ISO has no terminal emulator

- [ ] Fix or document

**Evidence**

`archiso/veldmuis/packages.x86_64` pulls `veldmuis-desktop`, whose metapackages
deliberately omit a terminal. `konsole` is only added to the installed target.

**Impact**

Users must use a TTY to collect installer logs. A GUI terminal would be
friendlier on a live image.

**Recommended fix**

Add `konsole` (or another small terminal) to the live package list, or document
the TTY path clearly.

### R15. Arch repository database signatures are optional

- [ ] Document as a limitation

**Evidence**

`docs/installing.md:107` and the live installer configuration use
`SigLevel = Required DatabaseOptional` for Arch repositories. Package
signatures remain required.

**Impact**

A compromised mirror or HTTPS path can select older, still-validly-signed
packages. This is rollback, not arbitrary injection.

**Recommended fix**

Document the limitation clearly. If Arch mirrors provide signed databases,
consider `DatabaseRequired`; otherwise keep the package-signature guarantee.

### R16. Trust bootstrap comes from the same repository

- [ ] Improve

**Evidence**

`SECURITY.md:65-84` fetches `veldmuis.gpg` and the fingerprint from the same
GitHub repository. If the repository is compromised, the key and the
instructions can be replaced together.

**Impact**

First-use trust depends on the repository being intact.

**Recommended fix**

Publish the fingerprint through an independent channel (website, DNS, signed
post, keyserver) and reference it from `SECURITY.md`.

### R17. Repository Actions settings can approve PRs; Dependabot alerts are off

- [ ] Fix

**Evidence**

- `can_approve_pull_request_reviews: true` on the hosted repository.
- Dependabot alerts and security updates are disabled.

**Impact**

Automation can approve pull requests, and SHA-pinned Actions do not receive
automated update PRs.

**Recommended fix**

Set `can_approve_pull_request_reviews` to `false`. Enable Dependabot alerts and
security updates for GitHub Actions.

### R18. `VELDMUIS_SYNC_TOKEN` is a long-lived PAT

- [ ] Improve

**Evidence**

`.github/workflows/muis-release-watch.yml` and
`.github/workflows/nvidia-recipe-watch.yml` use `secrets.VELDMUIS_SYNC_TOKEN`
with Contents and Pull requests write access.

**Impact**

A long-lived credential with repository write access is used by scheduled
workflows.

**Recommended fix**

Prefer a GitHub App with short-lived tokens, or document rotation and least
privilege for the PAT.

### R19. Release pipeline installs an unpinned AWS CLI from PyPI

- [ ] Fix

**Evidence**

`development/ensure-aws-cli.sh:6` runs
`python3 -m pip install --user awscli` without a version or hash pin.

**Impact**

The release pipeline trusts whatever PyPI serves at run time.

**Recommended fix**

Pin a version and verify a hash, or use a pinned container/action.

### R20. NVIDIA build grants a narrow root helper to the build user

- [ ] Review

**Evidence**

`development/run-ci-arch-builder.sh:150-161` grants the builder user passwordless
sudo for `development/install-nvidia-build-dependency.sh`, which installs a
package produced by that same build user. `docs/nvidia.md` states the payload
scan is a tripwire, not a gate.

**Impact**

A malicious vendored recipe could escalate to root inside the disposable build
container and tamper with artifacts before signing. There is no signing key in
that stage.

**Recommended fix**

Keep the current isolation, but treat recipe-sync PRs as security reviews and
consider validating the dependency package's checksum against a trusted
manifest before installing it as root.

### R21. Vendored Calamares fork will drift

- [ ] Track

**Evidence**

`packages/calamares/PKGBUILD` pins Calamares `3.3.14` with three local patches.
Calamares is not in the Arch repositories.

**Impact**

Security fixes and upstream behavior changes must be tracked manually.

**Recommended fix**

Document the fork and add a periodic upstream review step to the maintenance
checklist.

### R22. Documentation drift

- [ ] Fix

**Evidence**

- `docs/nvidia.md` says the recipe watcher opens an issue; the workflow opens a
  pull request.
- `docs/packages.md` has small dependency-list drift.
- `packages/veldmuis-calamares-config/branding/veldmuis/extras.qml` labels the
  development option “Code - OSS”, while `veldmuis-development` depends on the
  proprietary `code` package.

**Recommended fix**

Update the docs and the label to match the packages.

### R23. Historical ISOs are pruned

- [ ] Document as a limitation

**Evidence**

`development/prune-release-storage.sh` and `docs/release.md` delete older
release objects. Signed metadata remains, but the ISO bytes do not.

**Impact**

A signed historical release is not downloadable after a new release.

**Recommended fix**

Keep the current behavior if storage is the constraint, but state it plainly in
`SECURITY.md` and the download page.

### R24. Builds are not reproducible

- [ ] Document as a limitation

**Evidence**

Arch build inputs are not pinned to an Arch Linux Archive snapshot. The builder
image is a floating `archlinux:base-devel` tag resolved at run time.

**Impact**

Signed binaries cannot be rebuilt byte-for-byte.

**Recommended fix**

Keep the documented limitation, or pin an archive snapshot and record the full
build package set.

### R25. Secure Boot is not supported

- [ ] Document as a limitation

**Evidence**

The supported path is UEFI with systemd-boot and Secure Boot disabled.

**Impact**

Some users and some hardware will require Secure Boot. This is a support
boundary, not a bug.

**Recommended fix**

Keep it documented; do not imply Secure Boot support.

### R26. No offline installer

- [ ] Document as a limitation

**Evidence**

The current ISO is a network installer. Arch packages are resolved from Arch
mirrors at install time.

**Impact**

Installation requires a working internet connection.

**Recommended fix**

Keep it documented, or add a validated offline repository path as a separate
project.

---

## P3 — Housekeeping And Cosmetic

### R27. SPDX SBOM is low-fidelity

- [ ] Improve or document

**Evidence**

`development/generate-release-metadata.sh` writes `NOASSERTION` for package
download locations, licenses, and copyright, with no file hashes.

**Impact**

It is a valid SPDX 2.3 inventory, but it is not a high-fidelity SBOM. A
reviewer will ask.

**Recommended fix**

Document it as an inventory, or add package hashes and concluded licenses where
the data is available.

### R28. Release tags are not GPG-signed

- [ ] Improve or document

**Evidence**

`.github/workflows/release.yml` creates an annotated tag through the GitHub API.
The manifest is signed; the tag object is not.

**Impact**

Tag authenticity depends on GitHub account security rather than a signed tag.

**Recommended fix**

Sign the tag, or document that the signed manifest is the trust anchor.

### R29. A failed publication consumes the release tag

- [ ] Document

**Evidence**

`docs/release.md` states that a later external publication failure can consume
a tag and that recovery uses the next valid tag.

**Impact**

Operators must not reuse the failed tag. This is intentional but easy to
forget.

**Recommended fix**

Keep the documentation; consider a short runbook entry for failed publication.

### R30. Mirror refresh service is not hardened

- [ ] Improve

**Evidence**

`packages/veldmuis-mirrorlist/veldmuis-refresh-arch-mirrors.service` runs as
root with no systemd sandboxing directives.

**Impact**

The service parses remote mirror data and writes `/etc/pacman.d/mirrorlist` as
root.

**Recommended fix**

Add appropriate hardening (`NoNewPrivileges`, `ProtectSystem`, restricted
`ReadWritePaths`) where it does not break reflector.

---

## Already Good — Keep Doing This

- Signed packages and signed Veldmuis repository databases
  (`SigLevel = Required DatabaseRequired`).
- Keyring packaging with trusted/revoked lists and careful key-rotation,
  backup, restore, and CI-subkey export scripts.
- SHA-pinned GitHub Actions, `persist-credentials: false`, least-privilege
  workflow permissions.
- `check-repo-hygiene.sh`, `check-release-policy.sh`, and the local checksum
  checks.
- Immutable release paths, signed manifests, package inventory, SPDX SBOM,
  build-input records, and NVIDIA input hashes.
- Branch protection with required status checks, force-push and deletion
  disabled.
- Secret scanning and push protection enabled; no secrets in history.
- Private vulnerability reporting enabled.
- Honest scope and limitation documentation.

## Reviewer Questions To Be Ready For

- If the GitHub account is compromised, can a signed package be published?
  Currently yes: merge to `main` feeds the daily signed refresh (R6).
- Why is the screen unlocked by default? (R2)
- Why is KWallet off? (R3)
- Why is the CPU pinned at performance? (R4)
- Why does a fresh install use fish without installing it? (R1)
- Why does mpv start muted and loop? (R5)
- Why can’t I download last month’s signed ISO? (R23)
- Why does `/usr/lib/os-release` say Arch? (R13)
- Is the SBOM a real SBOM? (R27)
- How is the signing key protected? Software key in GitHub secrets, isolated
  signing stage, subkey-only export. Not hardware-backed.
- Can the ISO be rebuilt byte-for-byte? No (R24).
- Can Arch packages be rolled back? Yes, to older signed packages (R15).
- Why no Secure Boot? Documented limitation (R25).
- Why is the installer network-only? Current design (R26).

## Housekeeping Before Sharing The Working Tree

The Git tree is clean, but the local working tree still contains ignored
material that should not appear in a screen recording or a zip:

- `temp/` internal review notes and screenshots.
- `packages/*/pkg/` build outputs and `*.pkg.tar.zst`.
- `.opencode/` and `node_modules/`.
- `packages/*/pkg/.../.BUILDINFO` files that list the local build environment.

These are not tracked by Git. Move or remove them before recording or sharing a
copy of the directory.
