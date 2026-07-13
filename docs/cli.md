# CLI

The CLI entrypoint is `wrtstack` (repo root). All build logic lives there; `setup.sh` is one-time setup only.

CLI behavior rules (entrypoint, help-as-data, output tags, exit codes, confirmations) are generic and authoritative in [.agentstartstack/docs/cli-conventions.md](../.agentstartstack/docs/cli-conventions.md); help-file layout for `docs/help/*.txt` is in [.agentstartstack/docs/cli-help.md](../.agentstartstack/docs/cli-help.md). This file covers only what is specific to wrtstack.

## Usage

```bash
# First-time setup (once per machine)
./setup.sh && source ~/.bashrc

# Build
wrtstack build gw-wrt
wrtstack build office-wrt

# Build + flash
wrtstack flash gw-wrt --device=/dev/sdb
wrtstack flash office-wrt               # prompts for device if omitted

# Options
wrtstack build gw-wrt --jobs=8
wrtstack help
```

## How router config is selected

**Mode A (production):** The most recent `.tar.gz` in `backups/<router>/` is extracted into the OpenWRT `files/` overlay. The backup is authoritative -- hostname, IPs, VLANs, WiFi, WireGuard keys, etc. come from it.

**Mode B (first build / no backup):** `HOSTNAME`, `LAN_IP`, `SSH_PUBKEY` are read from the env file. Generates a minimal `network` + `system` UCI config and writes the SSH pubkey to `authorized_keys`. Set the production identity via LuCI after first boot.

## Adding a new router

1. Create `env/<name>.env`
2. Create `backups/<name>/` with `.gitkeep`
3. `wrtstack build <name>` works automatically

## Agent notes

- The `HOSTNAME` bash builtin is `unset` before sourcing env files to prevent it from shadowing the env var.
- `backups/**/*.tar.gz` are intentionally gitignored; never suggest committing them.
- Active-run guard for this project: `pgrep -af 'wrtstack (build|flash)'` (`ACTIVE_GUARD_PGREP` in `.agentstartstack.env`). The rules for live CLI runs -- no handoff, no `git pull` on canonical, no competing for the SD card or serial device while a run is active -- are generic: see [.agentstartstack/docs/workflow.md](../.agentstartstack/docs/workflow.md#3-active-cli-sessions-agents--mandatory).