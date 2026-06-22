# agentstartstack (wrtstack)

Project-specific agent guidance. Generic workflow, nut, conventions, and security live in the **.agentstartstack** submodule.

## Session startup

1. Run `scripts/init_grok_session.sh` or `scripts/init_claude_session.sh`
2. Read root `CLAUDE.md`; load 1-3 files from this directory for the task

## Suggested load patterns

| Task type | Files |
|-----------|-------|
| Build / flash / SD card | `cli.md`, `.agentstartstack/agentstartstack/workflow.md` |
| Router config / env files | `configuration.md`, `cli.md` |
| Architecture / BE14 WiFi | `architecture.md` |
| openwrt-bpi-r4 submodule | `architecture.md` |
| New shell script | `.agentstartstack/agentstartstack/conventions.md`, `code-quality.md` |
| Human Sync handoff | `.agentstartstack/agentstartstack/nut.md`, `workflow.md` |