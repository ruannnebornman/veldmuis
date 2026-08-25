# Veldmuis Review — Issues To Address

Status: internal working list, audit date 2026-08-02.
Priority: `[HIGH]` blocks going public / next release. `[MED]` should land before broad
visibility. `[LOW]` nice-to-have.

---

## Security

### [HIGH] Single-account compromise means signed malware
The release signing key lives in GitHub Actions secrets and the release job has
`contents: write` plus the R2 publishing keys. One compromised account (GitHub
credentials, CI) would let an attacker publish ISOs and repo databases that verify
against the official key — the signing ceremony currently makes a hijack *more*
dangerous, not less.

Actions:
- [ ] Enable GitHub protected environment "release" with **required reviewers**
      (manual approval gate before the publish job runs).
- [ ] Enable tag protection rule (only the workflow / admin can create `20xx.*` tags).
- [ ] Require 2FA + hardware-key 2FA on the GitHub account; remove force-push
      rights on `main`; require signed commits.
- [ ] Separate the CI signing subkey from any key material usable for key
      management (verify/restore scripts already point this direction; enforce it).
- [x] Keep and document the compromise runbook: revoke subkey, publish notice,
      mark last known-good release. (Documented in
      `development/key-rotation/README.md`, 2026-08-02.)

### [HIGH] NVIDIA 580xx AUR binaries signed without source audit
AUR-derived packages are validated as artifacts (license field, expected names)
but the code inside is not reviewed. Signing them extends project trust to
untrusted third-party build output.

Actions:
- [x] Switch `VELDMUIS_AUR_REF_MODE` default from `latest` to `locked` and
      review lock updates deliberately in release and scheduled refresh
      workflows (done 2026-08-02).
- [x] Record source hashes (upstream archive + AUR PKGBUILD at the locked ref)
      in the published build-inputs manifest, not just the git ref (done
      2026-08-02).
- [ ] Diff built package content against a reproducible re-build in a clean
      container before signing (even a best-effort diff catches tampering).
- [x] Document the residual risk in `docs/nvidia.md` in plain language (done
      2026-08-02).

### [MED] Non-reproducible builds (documented limitation)
Arch inputs are not pinned to an Arch Linux Archive snapshot, so artifacts can't
be byte-for-byte rebuilt. Combined with the previous item: signed binaries that
nobody can reproduce.

Actions:
- [x] Add ALA snapshot pinning as a roadmap item in `docs/building.md` with a
      concrete plan and rough cost (done 2026-08-02).
- [x] Until then, keep publishing the full build-inputs manifest and say
      explicitly what it does and doesn't guarantee (done 2026-08-02).

### [MED] Install-time Arch mirror ranking
`veldmuis-refresh-arch-mirrors` (reflector) rewrites the target mirrorlist from
mirrors selected at install time. Pacman signatures mitigate tampering, but the
mirror set is outside project control and the ranked list is written before the
first pacman run in some paths.

Actions:
- [x] Ship a conservative static fallback mirrorlist (known-good HTTPS mirror)
      used when reflector fails or network ranking is unreliable (done
      2026-08-02).
- [x] Document why this is safe (signature chain) in `docs/installing.md` so it
      doesn't look like an oversight (done 2026-08-02).

### [MED] SECURITY.md overpromises; no encryption for reports
- [x] "Acknowledge within seven days" with one maintainer is a target; make the
      language realistic (done 2026-08-02).
- [ ] Publish a PGP encryption key for private security reports so sensitive
      details aren't sent in plaintext via the GitHub form.

### [LOW] Bus-factor and key custody
- [ ] Document key custody and what happens to signing material if the project
      becomes inactive; the `development/key-rotation/` runbooks exist — link
      them from SECURITY.md and name a successor/escrow plan.

---

## Trust / PR (before broad visibility)

### [HIGH] Anonymity → link the real identity
The project currently has no human face; the repo profile is a bare username.
The personal site (https://ruannebornman.com/) already presents a real identity
with employment history and features Veldmuis as the crown project.

Status: addressed 2026-08-02 (README "Maintainer" section, SECURITY.md official
sources). Remaining: keep the personal site listed in Official Links on the
website, and keep the site's "Crown Project" section in sync.

### [HIGH] Project voice: veld at sunset, not personality
The repo reads uniformly formal (likely AI-assisted); combined with no identity
it reads as "LLM slop." The identity is a design decision: **Veldmuis is shaped
around the African veld at sunset** — its own voice, not the maintainer's.
The website carries the identity (amber-on-dusk palette, hero copy); the repo
docs do not yet match.

Actions:
- [x] Add a "Why Veldmuis" section in the project's voice (README) — warm,
      plain, unhurried; not corporate, not promotional. (done 2026-08-02)
- [x] Add a "Voice and tone" section to CONTRIBUTING.md describing the veld
      voice so future docs stay coherent. (done 2026-08-02)
- [ ] Write release notes as the project, not as a commit dump — one
      maintainer-authored paragraph per release about what changed and why
      (development/release-notes/).
- [ ] Add screenshots / an install walkthrough (GIF or short video) to the
      website; the site is the first impression.

### [HIGH] Sharpened value proposition
README says "not a replacement for Arch/EndeavourOS/Manjaro/CachyOS" — critics
will ask why it exists.

Status: addressed 2026-08-02 (README leads with "Why Veldmuis" and one clear
sentence). Keep the FAQ answer ("Why another Arch distribution?") in sync with
any scope changes.

### [MED] No community channel
- [ ] Create one community space (Discord server) and link it in README and
      on the site; set expectations for contribution in CONTRIBUTING.md.
- [ ] Add official social accounts (Twitter/X account in progress) to the
      site footer and README once live.
- [ ] List new official channels in SECURITY.md official sources so they don't
      get spoofed.
- [ ] When Discord/Twitter launch, update the "does not currently have official
      outside affiliations, community platforms" wording in README and
      SECURITY.md — it will no longer be true.

### [MED] Pre-empt the "rat" meme
Veldmuis means field mouse; the logo is a mouse; on some boards "rat" = RAT
(Remote Access Trojan).

Status: addressed 2026-08-02 — README FAQ leads with "Is Veldmuis a 'rat'?" and
disarms it in one paragraph.

### [MED] Website: GitHub link missing + maintainer identity
The site's hero only renders the "Try now" CTA; the "View Build" (GitHub) and
"Download ISO" CTAs exist in content but are not rendered, and the footer
trust link is not rendered either. There is also no maintainer identity on the
site.

Status: addressed 2026-08-02 (site renders all three hero CTAs, adds a
maintainer section linking the personal site and GitHub, and renders the
Official GitHub link in the footer).

### [MED] DistroWatch submission prep
- [ ] Prepare identity, screenshots, system requirements, and release notes
      before submitting; expect the project may be listed without ranking.
- [ ] Ensure the site has a real FAQ/installation quickstart so first-time
      visitors aren't sent to a one-sentence homepage.

---

## Already good — keep doing
- SHA-pinned actions and pinned builder container digest.
- Signature verification flow (verified end-to-end in audit: manifest sig
  checks out against the published key).
- `SigLevel = Required DatabaseRequired` on both Veldmuis repos.
- Repo hygiene check rejecting tracked secrets (`check-repo-hygiene.sh`).
- No curl|bash, no insecure download flags anywhere in the tree.
- Keyring ships only public material; AUR build stage has no signing key.

---

## Remaining Launch Plan

These items remain intentionally open after the 2026-08-02 repository hardening.
Completed work is recorded above and should not be reopened.

### Maintainer Decisions

- [ ] Confirm the static Arch fallback endpoint in
      `packages/veldmuis-mirrorlist/arch-mirrorlist-fallback`.
- [x] Confirm that scheduled package refreshes and installer releases should use
      locked AUR refs, with `latest` reserved for deliberate lock-file updates
      (confirmed 2026-08-02).

### GitHub And Key Controls

- [ ] Enable required reviewers on the protected `release` environment.
- [ ] Protect date-based release tags and require 2FA, hardware-key 2FA, signed
      commits, and no force-push access on `main`.
- [ ] Enable dismissal of stale pull-request approvals when a candidate SHA
      changes.
- [x] Keep automatic merge disabled for update PRs; low-risk candidates still
      require the maintainer to merge, while high-risk candidates require the
      full review and protected release gate.
- [ ] Enforce separation between the CI signing subkey and key-management
      material.
- [ ] Publish a project PGP key for encrypted vulnerability reports.
- [ ] Define signing-key custody, successor, and escrow arrangements if the
      project becomes inactive.

### Reproducibility And Supply Chain

- [ ] Diff NVIDIA packages against a clean best-effort rebuild before signing.
- [ ] Pin native and live-filesystem Arch inputs to an Arch Linux Archive
      snapshot and validate a rebuild against the recorded inputs.

### Public Launch Follow-Up

- [ ] Publish the Discord invite and Twitter/X handle once they are live, then
      list them in README.md, SECURITY.md, CONTRIBUTING.md, and the website.
- [ ] Keep maintainer-authored release notes, screenshots, and an install
      walkthrough current before broad visibility or a DistroWatch submission.

### Automated AUR Review And Approval

- [x] Create one open update PR per independently updateable package group,
      rather than one PR per detected AUR commit (implemented for NVIDIA
      580xx).
- [x] When a newer candidate arrives, update that package group's existing PR to
      the newest exact SHA, rerun all checks, and invalidate approval for the
      older SHA (workflow implemented; stale-approval dismissal still needs
      GitHub configuration).
- [x] Compare every candidate with the currently accepted lock, not only with a
      previous unapproved candidate; preserve superseded candidate reports for
      the audit trail.
- [x] Define the risk policy: low-risk candidates receive automated checks and
      are ready for maintainer merge, while high-risk candidates require PR
      review and the protected release environment.
- [ ] Email notifications for candidate PRs and approvals are deferred and are
      intentionally outside this change.
