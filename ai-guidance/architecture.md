# Architecture

## Project purpose

Custom OpenWRT 25.12 image builder for Banana Pi BPI-R4 routers (MediaTek MT7988A / Filogic 880). Produces flashable SD card images and sysupgrade images with configuration baked in at build time.

Two routers in production:
- **gw** -- gateway/main router, domain `ancapistan.io`, multi-VLAN (homenet, serversNet, guestNet, UIotNet), WireGuard, DDNS
- **office-wrt** -- secondary AP, no DHCP/firewall/dnsmasq, 802.11r fast roaming via DAWN

## Repository layout

```
wrtstack/
├── agentstartstack/           # git submodule -- shared AI agent guidance
├── setup.sh                   # One-time setup: deps, submodule init, ~/.local/bin symlink
├── wrtstack                   # CLI tool -- the primary entrypoint
├── env/
│   ├── gw-wrt.env             # Package list + Mode B identity vars for gateway router
│   └── office-wrt.env         # Package list + Mode B identity vars for office AP
├── backups/
│   ├── gw-wrt/                # LuCI config backups for gw-wrt (gitignored *.tar.gz)
│   └── office-wrt/            # LuCI config backups for office-wrt (gitignored *.tar.gz)
├── ai-guidance/               # Project-specific agent docs
└── openwrt-bpi-r4/            # git submodule -> github.com/openwrt/openwrt (heads/main)
```

## Key design rules

- **Never run as root.** Both `setup.sh` and `wrtstack` enforce this; `sudo` is used internally.
- **`backups/**/*.tar.gz` are gitignored** -- they may contain WiFi PSKs, VPN keys, etc.
- **`env/*.env` files ARE tracked in git** -- they contain only package lists and optional first-boot identity (no secrets).
- **Do not modify `openwrt-bpi-r4/`** -- it is the upstream OpenWRT source managed as a submodule.
- **Build is always incremental** -- safe to run repeatedly; only changed components rebuild.

## BE14 WiFi TX-power fix

The BPI-R4-NIC-BE14 ships with a defective EEPROM that caps TX power at ~6-7 dBm. wrtstack uses the upstream OpenWRT fix (25.12.3+, PR #22447): a device tree overlay (`mt7988a-bananapi-bpi-r4-wifi-be14`) that provides correct calibration data. wrtstack bakes `/etc/uci-defaults/99-bpi-r4-be14-wifi` into every image; this script calls `fw_setenv bootconf_extra mt7988a-bananapi-bpi-r4-wifi-be14` on first boot. U-Boot picks up the overlay on the next boot, restoring TX power to ~20 dBm. The router **auto-reboots ~10 seconds after first boot** (the uci-defaults script schedules `reboot` in the background before exiting so the script is deleted first, preventing a reboot loop).

## Submodule workflow (openwrt-bpi-r4)

```bash
# Initial clone
git clone --recurse-submodules git@github.com:farscapian/wrtstack.git

# After cloning without --recurse-submodules, or after setup.sh
git submodule update --init

# Update submodule to latest upstream
git submodule update --remote openwrt-bpi-r4
git add openwrt-bpi-r4 && git commit -m "bump openwrt submodule"
```

Do not modify files under `openwrt-bpi-r4/` except via upstream submodule bumps.