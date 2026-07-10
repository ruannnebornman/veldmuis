# Contributing

Veldmuis is currently a solo-maintainer project. Contributions and issue reports
are welcome, but the project uses GitHub issues and pull requests primarily as
an audit trail.

## Before Opening An Issue

Read:

- [Support](SUPPORT.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Security Policy](SECURITY.md)
- [NVIDIA 580xx Support](docs/nvidia.md), if graphics are involved

Use the closest issue template and include enough evidence for the maintainer
to reproduce or classify the problem.

## Issue Quality Bar

Good issues include:

- A clear problem statement.
- Veldmuis release tag or ISO name.
- Whether this is a live ISO, fresh install, or installed system.
- Hardware or VM details.
- Installer selections, especially graphics and extras.
- Exact commands and output.
- Logs or screenshots when relevant.
- Expected behavior and actual behavior.

Do not include private keys, account tokens, secrets, private service URLs, or
other sensitive data.

## Suggested Triage Fields

When turning an issue into actionable work, add or record:

- Impact: blocker, high, medium, or low.
- Area: docs, release, installer, packages, graphics, boot, security, or
  infrastructure.
- Scope: the files or behavior expected to change.
- Acceptance criteria: how the issue will be considered complete.
- Verification: commands, manual checks, or release checks that prove the fix.

## Pull Requests

Do not open a pull request unless there is a concrete change ready to review.

Pull requests should:

- Keep branch names, titles, descriptions, commit messages, and generated docs
  focused on the technical change.
- Describe the technical change.
- Include verification steps.
- Avoid unrelated refactors.
- Avoid changing release, publish, or protected settings unless that is the
  explicit purpose of the work.

The maintainer is the only merge authority.
