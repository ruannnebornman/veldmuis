# GitHub Release Environment Setup

Use this checklist before relying on `.github/workflows/release-iso.yml`.

## 1. Create The Protected Environment

- In GitHub, open the repository settings
- Go to `Environments`
- Create an environment named `release`
- Add required reviewers
- Enable `Prevent self-review` if your plan supports it

This environment is where the release workflow expects signing and publish credentials to live.

## 2. Add Environment Secrets

Add these as `release` environment secrets:

- `VELDMUIS_GPG_PRIVATE_KEY`
  The armored private key material for the dedicated CI signing subkey
- `VELDMUIS_GPG_FPR`
  The fingerprint of that signing key
- `CF_R2_ACCESS_KEY_ID`
  The Cloudflare R2 access key id used for uploads
- `CF_R2_SECRET_ACCESS_KEY`
  The matching Cloudflare R2 secret access key

Recommended security model:

- Use a dedicated release signing subkey, not the primary certifying key
- Scope the R2 credentials to the release bucket only
- Rotate the temporary test credentials out before first real release

### Export The Signing Secret From Your Local Keyring

The current Veldmuis key already follows the right structure for this:

- primary key for certification
- separate signing subkey for release signing

Export the CI-safe secret material with:

```bash
cd ~/Documents/veldmuis
./development/key-rotation/export-ci-subkey.sh
```

That writes these files under `~/.local/share/veldmuis/keyring-private/github-release-secrets/`:

- `VELDMUIS_GPG_PRIVATE_KEY.asc`
  Upload the file contents as the `VELDMUIS_GPG_PRIVATE_KEY` secret
- `VELDMUIS_GPG_FPR.txt`
  Upload the file contents as the `VELDMUIS_GPG_FPR` secret

The export contains secret subkeys only. It does not include the primary certifying secret key.

## 3. Add Environment Variables

Add these as `release` environment variables:

- `CF_R2_ACCOUNT_ID`
  The Cloudflare account id for the R2 endpoint
- `CF_R2_BUCKET`
  The bucket name that receives ISO uploads
- `CF_R2_PREFIX`
  Optional. Defaults to `iso`
- `CF_R2_PUBLIC_BASE_URL`
  Optional. Public download base URL used in the workflow summary
  Example: `https://downloads.veldmuislinux.org/iso`
- `VELDMUIS_PACKAGER`
  Optional. Defaults to `Veldmuis Linux <veldmuis@veldmuislinux.org>`

## 4. Tagging Model

The workflow lives on `main`, but it does not run for ordinary pushes to `main`.

It runs when:

- a tag matching `v*` is pushed
- the workflow is triggered manually with an existing tag name

Examples:

- `v1.3.2-beta1`
- `v1.4.0`
- `v2026.03.26`

## 5. First Dry Run

Recommended first test:

- Keep using the temporary R2 test bucket
- Push a prerelease-style tag
- Approve the `release` environment when prompted
- Confirm the ISO, checksum, and manifest land in the expected R2 prefix
- Confirm prerelease tags do not overwrite `latest.*`

## 6. First Real Release

Before the first real release:

- Replace the temporary R2 credentials with long-lived scoped release credentials
- Replace any temporary bucket name with the real release bucket
- Configure a public custom domain for R2 if you want public URLs in the workflow summary
- Store the dedicated CI signing subkey instead of any temporary signing material

## 7. After CI Signing Is Verified

Once the GitHub release workflow has successfully signed and published a test release:

- move the full offline key backup to secure storage
- remove the local Veldmuis secret key material from this machine with:

```bash
cd ~/Documents/veldmuis
./development/key-rotation/clean-env.sh
```
