# Veldmuis Security Audit Plan

This plan is for auditing the local Veldmuis build and release pipeline, with a focus on package provenance, signing, ISO trust, and installer/runtime privilege boundaries.

## Scope

- Package build entry points under `development/`
- Package metadata and signatures under `packages/` and `repos/`
- ISO build flow under `development/build-archiso.sh`
- VM and USB release workflows under `development/rebuild-iso-vm.sh` and `development/rebuild-iso-usb.sh`
- Key generation, backup, restore, and rotation under `development/key-rotation/`
- Installer/bootstrap behavior in `packages/veldmuis-calamares-config/`

## Immediate Tracked Item

### PACKAGER metadata is unset

- Status: Open
- Priority: Low
- Type: Traceability and supply-chain hygiene
- Observed state: locally built packages currently show `Packager : Unknown Packager`
- Why it matters: this is not a direct exploit on its own, but it weakens provenance, auditability, and operator accountability
- Correct implementation note: this is normally set through `makepkg` configuration or environment, not inside a PKGBUILD
- Candidate remediation:
  - Set `PACKAGER` in `/etc/makepkg.conf` on trusted builder hosts
  - Or create a repo-owned makepkg config overlay and pass it consistently to all build entry points
  - Use a canonical identity such as `Veldmuis Linux <veldmuis@veldmuislinux.org>`
- Validation:
  - Build a package
  - Run `pacman -Qip <package file>`
  - Confirm `Packager` is no longer `Unknown Packager`

## Audit Tracks

### 1. Build provenance and package metadata

- Verify every build path produces attributable package metadata
- Confirm source checksums and source pinning are present and reviewed
- Check whether build configuration is consistent across VM, USB, local repo, and key-rotation rebuild flows
- Review whether package signing is mandatory before anything enters `repos/`
- Evaluate reproducibility and whether build outputs vary unexpectedly by host

### 2. Signing keys and secret handling

- Review where the signing key lives on builder machines and which scripts read it
- Review backup and restore handling for the private key and ownertrust
- Confirm revocation workflow is documented and testable
- Revisit the tradeoff of non-interactive signing versus key-at-rest protection
- Confirm the active fingerprint marker cannot silently drift from the actual signing key in use

### 3. Local repo and publication security

- Verify `repo-add` usage, detached signatures, and database signing
- Confirm only expected packages are copied into the local repo
- Check whether stale or unsigned artifacts can be published accidentally
- Review repo publishing workflow and mirror/update integrity expectations

### 4. ISO trust chain

- Review how the local repo is embedded into the ISO
- Verify pacman keyring population during ISO build
- Confirm the ISO build cannot silently consume stale cached package artifacts
- Review root-required build steps and their attack surface on the host

### 5. Installer and privileged execution review

- Audit Calamares bootstrap scripts and helper scripts for quoting, command injection, and unsafe shell patterns
- Review privilege boundaries between live session, installer, chroot, and target system
- Verify network/bootstrap sources are explicit and trustworthy
- Review post-install configuration paths that modify trust stores, pacman config, or keys

### 6. Operational release checks

- Align operational release work with `development/tagged-release-pipeline-plan.md`
- Keep the protected release workflow under review: `.github/workflows/release-iso.yml`
- Keep the GitHub release environment setup under review: `development/release-environment-setup.md`
- Define a release checklist for package signatures, ISO checksum publication, and verification steps
- Add a verification pass that checks package metadata, signatures, and key fingerprints before release
- Ensure VM and USB smoke tests are part of release readiness
- Define incident response steps for key compromise, mirror compromise, or unsigned artifact discovery

## Execution Order

1. Capture a baseline of current package metadata, signatures, repo state, and key usage.
2. Fix low-risk provenance gaps first, including `PACKAGER`.
3. Review signing-key storage, backup, restore, and revocation flows.
4. Review build scripts and installer scripts for unsafe privilege or shell behavior.
5. Verify release artifacts end-to-end with VM and USB test flows.
6. Turn the final checklist into a repeatable pre-release gate.

## Evidence To Collect During Audit

- `pacman -Qip` output from representative built packages
- `gpg --list-secret-keys` and current fingerprint marker value
- Repo contents and detached signatures under `repos/`
- ISO build logs and package source logs
- Installer logs from a clean VM run

## Done Criteria

- All package builds have attributable metadata
- Signing and revocation workflows are documented and tested
- Release artifacts are signed and verifiable
- High-risk installer or build-script issues are either fixed or tracked with owners
- A repeatable release security checklist exists and is being used
