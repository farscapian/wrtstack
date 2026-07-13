# wrtstack -- AI Development Notes (index)

OpenWRT 25.12 image builder for Banana Pi BPI-R4. **Load topic files on demand -- do not read this entire index repeatedly.**

## Quick rules

- Branding: always lowercase `wrtstack`
- Text: ASCII-only in docs, logs, help, and code comments
- Agents work in session worktrees, NOT in the canonical local repo: `~/.claude/worktrees/wrtstack/<session-id>/` (Claude Code) or `~/.grok/worktrees/wrtstack/<session-id>/` (Grok). The CLI runs from the canonical repo, `~/Sync/mini_projects/wrtstack`
- Claude Code: NEVER edit files under `~/Sync/mini_projects/wrtstack` -- use absolute paths to your session worktree only
- ass does not create worktrees: the agent creates one, then `ass adopt <path>` makes it ass-aware and aligns it (this runs `scripts/init_claude_session.sh` / `scripts/init_grok_session.sh`). See [.agentstartstack/docs/workflow.md](.agentstartstack/docs/workflow.md)
- After changes: commit in the session worktree; the human runs `ass sync` then `git push origin main` (or `ass up`). NEVER `git push origin` from agents (see [.agentstartstack/docs/ass.md](.agentstartstack/docs/ass.md))
- Never `ass sync` or `git pull` on the canonical repo while `wrtstack build` or `wrtstack flash` is running (guard: `pgrep -af 'wrtstack (build|flash)'`)
- Do not modify `openwrt-bpi-r4/` -- upstream OpenWRT submodule only

## Generic guidance (.agentstartstack submodule)

| File | Load when |
|------|-----------|
| [.agentstartstack/docs/workflow.md](.agentstartstack/docs/workflow.md) | Repos, session worktrees, git sync, commit policy |
| [.agentstartstack/docs/ass.md](.agentstartstack/docs/ass.md) | `ass` / `ass up` handoff CLI |
| [.agentstartstack/docs/cli-conventions.md](.agentstartstack/docs/cli-conventions.md) | How a project CLI must behave (authoritative) |
| [.agentstartstack/docs/cli-help.md](.agentstartstack/docs/cli-help.md) | Help-file layout (`docs/help/*.txt`) |
| [.agentstartstack/docs/conventions.md](.agentstartstack/docs/conventions.md) | Naming, ASCII-only, output tags |
| [.agentstartstack/docs/terminal.md](.agentstartstack/docs/terminal.md) | Cursor/Codium copy-paste |
| [.agentstartstack/docs/security.md](.agentstartstack/docs/security.md) | Secrets, backups |
| [.agentstartstack/docs/code-quality.md](.agentstartstack/docs/code-quality.md) | shellcheck, git hooks |
| [.agentstartstack/docs/testing.md](.agentstartstack/docs/testing.md) | Pre-handoff checks |

## Project guidance

| File | Load when |
|------|-----------|
| [docs/architecture.md](docs/architecture.md) | Layout, design rules, BE14 WiFi fix, submodules |
| [docs/cli.md](docs/cli.md) | `wrtstack` commands, router modes, new router setup |
| [docs/configuration.md](docs/configuration.md) | `env/*.env` format and variables |

Full catalog: [docs/README.md](docs/README.md).

Origin: `git@github.com:farscapian/wrtstack.git`
