# Signing-Key Operations

These tools maintain the existing Veldmuis signing key. They do not generate,
replace, revoke, or delete keys, change repository trust, publish artifacts, or
communicate with hosted services.

## Current Key Set

The repository distributes only the public key material under
`packages/veldmuis-keyring`.

```text
Primary fingerprint:        022A 2A63 9A21 666F 1F48  BD5E BD3E AF48 5786 AAEF
Signing-subkey fingerprint: E76D 738D 74AA 940D 429B  D9F5 BC27 E50C B16F 2302
Created:                    2026-03-21
Expires:                    2031-03-20
```

The primary fingerprint is the stable identity recorded in
`veldmuis-trusted`. The signing subkey performs normal package and repository
signing. A release does not require a new key or a key swap.

Hosted release automation expects a secret signing-subkey export in
`VELDMUIS_GPG_PRIVATE_KEY` and the primary fingerprint in
`VELDMUIS_GPG_FPR`. The repository does not contain that secret export and
cannot show whether the hosted values are present or current.

## Encrypted Backup

`backup-key.sh` exports the complete secret key, public key, ownertrust,
revocation certificate, fingerprint marker, and a snapshot of the public
keyring. Plaintext staging uses a temporary mode-`0700` directory and is
removed on exit. The published archive is symmetrically encrypted with GnuPG,
verified before it is moved into place, and written with mode `0600`.

Run it only on the trusted machine that holds the complete secret key:

```sh
./development/key-rotation/backup-key.sh \
  --output /secure/storage/veldmuis-keyring-backup.tar.gpg
```

The default output is outside the repository at
`~/.local/share/veldmuis/keyring-backup.tar.gpg`. The script refuses to place
secret material in the source checkout. Prefer the interactive passphrase
prompt. For controlled recovery testing, a mode-`0600` passphrase file may be
supplied with `--passphrase-file`; do not store that file beside the archive.

An existing password-protected ZIP can remain as a legacy recovery copy. Check
offline that it uses modern AES encryption rather than legacy ZipCrypto, that
the password is strong and unique, and that the archive actually contains the
documented key. Creating a new encrypted backup does not alter an existing
backup.

Maintain at least two encrypted copies in separate secure locations. Record
the fingerprint and archive format separately, but never record the recovery
passphrase in this repository.

## Verify Or Restore A Backup

Verification decrypts into a temporary directory, validates every manifest
entry, cross-checks all public and trusted fingerprints, and imports the backup
into an isolated temporary GnuPG home. It does not import anything into the
operator's normal GnuPG home:

```sh
./development/key-rotation/restore-key.sh --verify \
  /secure/storage/veldmuis-keyring-backup.tar.gpg
```

Restoration first performs the same checks, then requires the complete primary
fingerprint to be entered or supplied explicitly:

```sh
./development/key-rotation/restore-key.sh --restore \
  /secure/storage/veldmuis-keyring-backup.tar.gpg
```

Restore imports the secret key and ownertrust and writes the local fingerprint
marker. It does not overwrite repository files, build packages, publish
artifacts, or change trust. Perform a periodic restore exercise on an offline
recovery system and compare the resulting fingerprint with this document.

## Export The Automation Signing Subkey

The automation export deliberately excludes the primary certifying secret:

```sh
./development/key-rotation/export-ci-subkey.sh
```

Before writing output, the command requires the local marker, committed trusted
fingerprint, public key, and available secret key to identify the same primary
key. It imports the export into an isolated temporary GnuPG home and verifies
that it can create a detached signature. Output is placed outside the
repository with restrictive permissions.

Treat the export as a short-lived secret. After configuring and testing the
protected release environment through the normal maintainer process, delete the
local export directory securely. The script itself does not update hosted
secrets.

## Future Key Changes

There is intentionally no whole-key generation or broad key-deletion helper in
this directory. A future change must use a reviewed, staged runbook rather than
a one-command swap.

- Routine signing-subkey rotation keeps the current primary fingerprint. Add
  and distribute the new public signing subkey before using it for repository
  signatures.
- Primary-key replacement requires a transition keyring authenticated by the
  still-trusted old key, an update window for installed systems, and validation
  from an installation using the previous public image.
- Suspected compromise requires a separate emergency response: stop signing,
  preserve evidence, revoke the affected material with the offline primary
  where possible, publish an authenticated transition, and document the impact.

Do not add an old primary fingerprint to `veldmuis-revoked` or begin signing
with a replacement primary until the transition path has been tested end to
end.
