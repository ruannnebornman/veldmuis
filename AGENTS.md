# Project Agent Instructions

- Keep repository artifacts provider-neutral. Do not include assistant, model,
  vendor, or tool identifiers in branch names, commit messages, PR titles, PR
  descriptions, generated documentation, issue text, release notes, or comments
  unless explicitly requested.
- Use neutral branch names such as `feature/...`, `fix/...`, `chore/...`,
  `audit/...`, or `release/...`.
- Use neutral PR titles and commit messages that describe the technical change
  only.
- Do not disclose which assistant or automation tool produced a change in
  project artifacts.
- Do not create or open a pull request unless explicitly asked in the current
  task. If a pull request is the next logical step, ask first.
- Never merge pull requests, enable auto-merge, approve pull requests, or mark
  pull requests ready for review. The maintainer is the only merge authority.
- Do not close or delete pull requests or branches unless explicitly asked.
- For this solo-maintainer project, keep PRs as the review and audit trail, but
  do not require independent approval while there is only one maintainer. Prefer
  status checks and explicit human review when available.
- Do not commit, push, create releases, publish packages, or change protected
  settings unless explicitly asked.
- After starting a pipeline or workflow, do not monitor, poll, wait for, or
  report its progress unless explicitly asked in the current task. A request to
  start a pipeline or workflow authorizes only its dispatch.
- Before reporting repository validation as successful, run
  `./development/check-repo-hygiene.sh` with ShellCheck installed. If the script
  reports that ShellCheck was skipped, describe validation as incomplete.
