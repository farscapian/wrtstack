# docs (wrtstack)

Project-specific agent guidance. Generic workflow, the `ass` handoff CLI, CLI conventions, and security live in the **.agentstartstack** submodule under `.agentstartstack/docs/`.

## Session startup

1. Create a session worktree, then `ass adopt <path>` (runs `scripts/init_claude_session.sh` / `scripts/init_grok_session.sh` to align it)
2. Read root `CLAUDE.md`; load 1-3 files from this directory for the task

## Contents

| File | Covers |
|------|--------|
| [architecture.md](architecture.md) | Layout, design rules, BE14 WiFi fix, submodules |
| [cli.md](cli.md) | `wrtstack` commands, router modes, new router setup |
| [configuration.md](configuration.md) | `env/*.env` format and variables |
| [help/](help/) | `wrtstack` CLI help text (see `.agentstartstack/docs/cli-help.md`) |

## Suggested load patterns

| Task type | Files |
|-----------|-------|
| Build / flash / SD card | `cli.md`, `.agentstartstack/docs/workflow.md` |
| Router config / env files | `configuration.md`, `cli.md` |
| Architecture / BE14 WiFi | `architecture.md` |
| openwrt-bpi-r4 submodule | `architecture.md` |
| New shell script | `.agentstartstack/docs/conventions.md`, `.agentstartstack/docs/code-quality.md` |
| CLI behavior / help files | `.agentstartstack/docs/cli-conventions.md`, `.agentstartstack/docs/cli-help.md` |
| Handoff to the human | `.agentstartstack/docs/ass.md`, `.agentstartstack/docs/workflow.md` |
