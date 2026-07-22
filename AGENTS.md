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
- The protected `main` branch is a read-only integration target for agents.
  Never commit directly on `main` or push directly to it. Create a neutral
  non-default branch for repository changes.
- Agents are pre-authorized to create or switch non-default branches, commit
  scoped changes, push those branches, and open draft pull requests without
  asking for separate permission. Keep each pull request focused and report
  its URL to the maintainer.
- Never merge a pull request under any circumstances, even if a user explicitly
  asks for it. Never enable auto-merge, approve pull requests, or mark pull
  requests ready for review. Only the maintainer may merge through the hosting
  interface.
- Do not close or delete pull requests or branches unless explicitly asked.
- For this solo-maintainer project, keep PRs as the review and audit trail, but
  do not require independent approval while there is only one maintainer. Prefer
  status checks and explicit human review when available.
- Do not create releases, publish packages, dispatch workflows, or change
  protected settings unless explicitly asked in the current task.
- After starting a pipeline or workflow, do not monitor, poll, wait for, or
  report its progress unless explicitly asked in the current task. A request to
  start a pipeline or workflow authorizes only its dispatch.
- Before reporting repository validation as successful, run
  `./development/check-repo-hygiene.sh` with ShellCheck installed. If the script
  reports that ShellCheck was skipped, describe validation as incomplete.
