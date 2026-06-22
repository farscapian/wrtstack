# wrtstack -- AI Development Notes (index)

OpenWRT 25.12 image builder for Banana Pi BPI-R4. **Load topic files on demand -- do not read this entire index repeatedly.**

## Quick rules

- Branding: always lowercase `wrtstack` (repo directory is `openwrt` on Sync)
- Text: ASCII-only in docs, logs, help, and code comments
- Agents work in session clones, NOT in Sync: Grok -> `~/.grok/worktrees/mini-projects-openwrt/<session-id>/`; Claude Code -> `~/.claude/worktrees/mini-projects-openwrt/<session-id>/`; CLI runs from `~/Sync/mini_projects/openwrt`
- Claude Code: NEVER edit files under `~/Sync/mini_projects/openwrt` -- use absolute paths to your session clone only
- New Grok session: run `scripts/init_grok_session.sh`; new Claude Code session: run `scripts/init_claude_session.sh` (see `agentstartstack/ai-guidance/workflow.md`)
- After changes: commit in session clone; human runs `nut` then `git push origin main` (or `nutup`). NEVER `git push origin` from agents (see `agentstartstack/ai-guidance/nut.md`)
- Never `nut` or `git pull` on Sync while `wrtstack build` or `wrtstack flash` is running
- Do not modify `openwrt-bpi-r4/` -- upstream OpenWRT submodule only

## Generic guidance (agentstartstack submodule)

| File | Load when |
|------|-----------|
| [agentstartstack/ai-guidance/workflow.md](agentstartstack/ai-guidance/workflow.md) | Repos, session clones, git sync |
| [agentstartstack/ai-guidance/nut.md](agentstartstack/ai-guidance/nut.md) | `nut` / `nutup` handoff |
| [agentstartstack/ai-guidance/conventions.md](agentstartstack/ai-guidance/conventions.md) | Naming, ASCII-only, output tags |
| [agentstartstack/ai-guidance/terminal.md](agentstartstack/ai-guidance/terminal.md) | Cursor/Codium copy-paste |
| [agentstartstack/ai-guidance/security.md](agentstartstack/ai-guidance/security.md) | Secrets, backups |
| [agentstartstack/ai-guidance/code-quality.md](agentstartstack/ai-guidance/code-quality.md) | shellcheck, git hooks |
| [agentstartstack/ai-guidance/testing.md](agentstartstack/ai-guidance/testing.md) | Pre-handoff checks |

## Project guidance

| File | Load when |
|------|-----------|
| [ai-guidance/architecture.md](ai-guidance/architecture.md) | Layout, design rules, BE14 WiFi fix, submodules |
| [ai-guidance/cli.md](ai-guidance/cli.md) | `wrtstack` commands, router modes, new router setup |
| [ai-guidance/configuration.md](ai-guidance/configuration.md) | `env/*.env` format and variables |

Full catalog: [ai-guidance/README.md](ai-guidance/README.md).

Origin: `git@github.com:farscapian/wrtstack.git`