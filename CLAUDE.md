# wrtstack -- AI Development Notes (index)

OpenWRT 25.12 image builder for Banana Pi BPI-R4. **Load topic files on demand -- do not read this entire index repeatedly.**

## Quick rules

- Branding: always lowercase `wrtstack` (repo directory is `wrtstack` on Sync)
- Text: ASCII-only in docs, logs, help, and code comments
- Agents work in session clones, NOT in Sync: Grok -> `~/.grok/worktrees/mini-projects-wrtstack/<session-id>/`; Claude Code -> `~/.claude/worktrees/mini-projects-wrtstack/<session-id>/`; CLI runs from `~/Sync/mini_projects/wrtstack`
- Claude Code: NEVER edit files under `~/Sync/mini_projects/wrtstack` -- use absolute paths to your session clone only
- New Grok session: run `scripts/init_grok_session.sh`; new Claude Code session: run `scripts/init_claude_session.sh` (see `.agentstartstack/agentstartstack/workflow.md`)
- After changes: commit in session clone; human runs `nut` then `git push origin main` (or `nutup`). NEVER `git push origin` from agents (see `.agentstartstack/agentstartstack/nut.md`)
- Never `nut` or `git pull` on Sync while `wrtstack build` or `wrtstack flash` is running
- Do not modify `openwrt-bpi-r4/` -- upstream OpenWRT submodule only

## Generic guidance (.agentstartstack submodule)

| File | Load when |
|------|-----------|
| [.agentstartstack/agentstartstack/workflow.md](.agentstartstack/agentstartstack/workflow.md) | Repos, session clones, git sync |
| [.agentstartstack/agentstartstack/nut.md](.agentstartstack/agentstartstack/nut.md) | `nut` / `nutup` handoff |
| [.agentstartstack/agentstartstack/conventions.md](.agentstartstack/agentstartstack/conventions.md) | Naming, ASCII-only, output tags |
| [.agentstartstack/agentstartstack/terminal.md](.agentstartstack/agentstartstack/terminal.md) | Cursor/Codium copy-paste |
| [.agentstartstack/agentstartstack/security.md](.agentstartstack/agentstartstack/security.md) | Secrets, backups |
| [.agentstartstack/agentstartstack/code-quality.md](.agentstartstack/agentstartstack/code-quality.md) | shellcheck, git hooks |
| [.agentstartstack/agentstartstack/testing.md](.agentstartstack/agentstartstack/testing.md) | Pre-handoff checks |

## Project guidance

| File | Load when |
|------|-----------|
| [agentstartstack/architecture.md](agentstartstack/architecture.md) | Layout, design rules, BE14 WiFi fix, submodules |
| [agentstartstack/cli.md](agentstartstack/cli.md) | `wrtstack` commands, router modes, new router setup |
| [agentstartstack/configuration.md](agentstartstack/configuration.md) | `env/*.env` format and variables |

Full catalog: [agentstartstack/README.md](agentstartstack/README.md).

Origin: `git@github.com:farscapian/wrtstack.git`