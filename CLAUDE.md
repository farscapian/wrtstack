# CLAUDE.md — openwrt-builder

## Project purpose

Custom OpenWRT 25.12 image builder for Banana Pi BPI-R4 routers (MediaTek MT7988A / Filogic 880). Produces flashable SD card images and sysupgrade images with baked-in configuration.

Two routers in production:
- **gw** — gateway/main router, domain `ancapistan.io`, multi-VLAN (homenet, serversNet, guestNet, UIotNet), WireGuard, DDNS
- **office-wrt** — secondary AP, no DHCP/firewall/dnsmasq, 802.11r fast roaming

## Repository layout

```
openwrt-builder/
├── build-bpi-r4-openwrt.sh        # Main idempotent build script (799 lines)
├── openwrt-bpi-r4/                # git submodule → github.com/openwrt/openwrt (heads/main)
└── configs/
    ├── gw-wrt/
    │   ├── gw-packages.env        # Extra packages for gateway router
    │   └── backup-gw-*.tar.gz     # LuCI config backup (gitignored — may contain secrets)
    └── office-wrt/
        ├── office-packages.env    # Extra packages for office AP
        └── backup-office-wrt-*.tar.gz
```

## Build invocations

Mode A — from LuCI backup (production workflow):
```bash
./build-bpi-r4-openwrt.sh \
    --config-backup=configs/gw-wrt/backup-gw-2026-04-13.tar.gz \
    --env=configs/gw-wrt/gw-packages.env \
    --flash --device=/dev/sdX
```

Mode B — explicit flags (first-time or no backup):
```bash
./build-bpi-r4-openwrt.sh \
    --hostname=gw \
    --lan-ip=192.168.4.2 \
    --ssh-pubkey="ssh-ed25519 AAAA..." \
    --env=configs/gw-wrt/gw-packages.env
```

## Key design rules

- **Never run as root.** The script invokes `sudo` internally where needed.
- **`--config-backup` is authoritative.** When provided, `--hostname`, `--lan-ip`, `--ssh-pubkey` are silently ignored.
- **LAN IP range**: `192.168.4.2–9` for Mode B. Production routers use their backup-embedded addresses.
- **`*.tar.gz` backups are gitignored** — they may contain WiFi PSKs, VPN keys, etc.
- **`*.env` files are gitignored** — keep them out of git too (may contain secrets via PACKAGES vars).
- The submodule tracks `openwrt/openwrt` at `heads/main`. Pinned to a specific commit; update deliberately with `git submodule update --remote`.

## EEPROM patch

The mt76 TX-power EEPROM fix (`100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch`) is fetched from immortalwrt and applied to the submodule's `package/kernel/mt76/patches/`. It is sha256-checked on every run — only re-applied if changed upstream. Without it, the BPI-R4-NIC-BE14 WiFi 7 card is capped at ~6–7 dBm instead of ~20 dBm.

## Submodule workflow

```bash
# Initial clone
git clone --recurse-submodules git@github.com:farscapian/openwrt-builder.git

# After cloning without --recurse-submodules
git submodule update --init

# Update submodule to latest upstream HEAD
git submodule update --remote openwrt-bpi-r4
git add openwrt-bpi-r4 && git commit -m "bump openwrt submodule"
```

## What Claude should know

- Do not modify files inside `openwrt-bpi-r4/` — it is the upstream OpenWRT tree managed as a submodule.
- `configs/**/*.tar.gz` and `*.env` files are intentionally gitignored; don't suggest committing them.
- The build script is idempotent by design; incremental rebuilds are expected and normal.
- OpenWRT packages for `gw` include WireGuard VPN, DDNS (Namecheap), Prometheus node exporter, DAWN roaming daemon, and full `hostapd-openssl` (required for WPA3-SAE + 802.11r).
