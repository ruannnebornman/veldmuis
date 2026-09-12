# Global Agent Instructions - kaazrot

## Workspace
- Default code workspace: `/home/kaazrot/Documents/code/`
- Assume new work goes under there unless told otherwise.
- Environment: Arch Linux (veldmuis), Wayland, WezTerm, NVIDIA GTX 1080 Ti.
- This PC runs Veldmuis (installed OS), KDE Plasma Wayland session.
- Veldmuis repo checkout: `/home/kaazrot/Documents/code/veldmuis/` - check here for packaging/base decisions.
- Check per-project `AGENTS.md` first - it overrides this file.

## Repo map
- When user says "veldmuis", they mean the repo at `/home/kaazrot/Documents/code/veldmuis/` - you can make changes to it.

## Worktree Isolation
- Always work in your own git worktree + branch for repo tasks — never build/edit/test directly in the main checkout or another worktree.
- Keep worktrees in the central hidden dir so the workspace stays clean: `git fetch origin && git worktree add ../.worktrees/<repo>-<short-task> -b <feature/...> origin/main` (use repo's base branch), then work from there.
- Verify with `git worktree list` and `git branch --show-current`.
- Never touch another worktree: no edits, branch switches, resets, `git clean`, or deletes outside yours.
- Cleanup only when asked: `git worktree remove ../.worktrees/<repo>-<short-task>`.

## Behavior
- Keep responses short and concise. Facts and problem-solving, no fluff.
- Verify by execution when reasonable: run tests/build, reproduce before/after.
- Prefer editing existing files over creating new ones. Never create docs (*.md) unless explicitly asked.
- Use dedicated tools for file ops (Read/Edit/Write/Glob/Grep), reserve Bash for system commands.

## Sudo
- No terminal for password input. Always use `SUDO_ASKPASS=/usr/bin/ksshaskpass sudo -A ...` instead of plain `sudo`.

## Safety / Git
- Keep repo artifacts provider-neutral. No assistant/model/vendor names in branches, commits, PRs, docs, or comments unless explicitly requested.
- Use neutral branch names: `feature/...`, `fix/...`, `chore/...`.
- Use neutral PR titles and commit messages that describe the technical change only. Do not disclose which assistant or automation tool produced a change in project artifacts.
- The protected `main` branch is a read-only integration target for agents. Never commit directly on `main` or push directly to it. Create a neutral non-default branch for repository changes.
- Never merge a pull request under any circumstances, even if explicitly asked. Never enable auto-merge, approve pull requests, or mark pull requests ready for review. Only the maintainer may merge through the hosting interface.
- Do not close or delete pull requests or branches unless explicitly asked.
- For solo-maintainer projects, keep PRs as the review and audit trail, but do not require independent approval while there is only one maintainer. Prefer status checks and explicit human review when available.
- Do not commit, push, create PRs, create releases, publish packages, dispatch workflows, or change repo settings unless explicitly asked in the current task.
- After starting a pipeline or workflow, do not monitor, poll, wait for, or report its progress unless explicitly asked in the current task. A request to start a pipeline or workflow authorizes only its dispatch.
- Before any commit: show `git status`, `git diff`, stage only intended files, never commit secrets.
- Preserve unrelated worktree changes.
