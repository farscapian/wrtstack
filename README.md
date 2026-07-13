# openwrt-builder

OpenWRT 25.12 image builder for the **Banana Pi BPI-R4** (MediaTek MT7988A / Filogic 880) with the BPI-R4-NIC-BE14 WiFi 7 card.

Produces bootable SD card images and sysupgrade `.itb` files with configuration baked in at build time. A CLI tool (`wrtstack`) handles build and flash operations for each router in the fleet.

## Hardware

| Component | Detail |
|-----------|--------|
| Board | Banana Pi BPI-R4 |
| SoC | MediaTek MT7988A (Filogic 880) |
| WiFi card | BPI-R4-NIC-BE14 (mt7996 / WiFi 7) |
| OpenWRT target | `mediatek/filogic` |
| OpenWRT profile | `bananapi_bpi-r4` |

## Quick start

```bash
# Clone with submodule
git clone --recurse-submodules git@github.com:farscapian/wrtstack.git
cd wrtstack

# One-time setup: install deps, init submodule, add shell alias
./setup.sh
source ~/.bashrc

# Build
wrtstack build gw-wrt
wrtstack build office-wrt

# Build + flash
wrtstack flash gw-wrt --device=/dev/sdb
wrtstack flash office-wrt            # prompts for device if omitted
```

## Prerequisites

- Ubuntu 24.04+ or 26.04 (apt-based)
- ~25 GB free disk space
- Internet access
- Run as a **normal user** (not root)

## CLI reference

```
wrtstack build <router> [OPTIONS]    Build firmware image
wrtstack flash <router> [OPTIONS]    Build then flash to SD card
wrtstack help                        Show help
```

| Option | Description |
|--------|-------------|
| `--device=/dev/sdX` | Block device for flash (or prompted interactively) |
| `--jobs=N` | Parallel make jobs (default: `nproc`) |
| `--workdir=DIR` | Build directory (default: `openwrt-bpi-r4/`) |

## Routers

| Name | Role | Env file | Backup dir |
|------|------|----------|------------|
| `gw-wrt` | Gateway router | `env/gw-wrt.env` | `backups/gw-wrt/` |
| `office-wrt` | Office AP | `env/office-wrt.env` | `backups/office-wrt/` |

## How config is selected

### Mode A -- LuCI backup (production workflow)

Drop a LuCI-exported `.tar.gz` into `backups/<router>/`. The most recent one is auto-selected and extracted into the OpenWRT `files/` overlay. The backup is authoritative for all identity (hostname, IPs, VLANs, WiFi, WireGuard keys, etc.).

```bash
# Generate a backup: LuCI -> System -> Backup / Flash Firmware -> Download backup
cp ~/Downloads/backup-gw-*.tar.gz backups/gw-wrt/
wrtstack flash gw-wrt --device=/dev/sdb
```

### Mode B -- env vars (first build or recovery)

When no backup exists, `HOSTNAME`, `LAN_IP`, and `SSH_PUBKEY` in the env file are used to generate a minimal first-boot config. Set the full production configuration via LuCI after first boot.

```bash
# Uncomment in env/gw-wrt.env:
# HOSTNAME=gw
# LAN_IP=192.168.4.2
# SSH_PUBKEY="ssh-ed25519 AAAA..."
wrtstack build gw-wrt
```

## Env files

Each router has `env/<router>.env` defining its build config:

```bash
# Mode B identity -- used only when no backup exists in backups/<router>/
#HOSTNAME=gw
#LAN_IP=192.168.4.2
#SSH_PUBKEY="ssh-ed25519 AAAA..."

PACKAGES="hostapd-openssl dawn luci-app-dawn ..."
PACKAGES_REMOVE="wpad-basic-wolfssl wpad-wolfssl wpad-openssl"
```

Env files are tracked in git (they contain no secrets -- backup tarballs hold sensitive material and are gitignored).

## Output images

Built to `openwrt-bpi-r4/bin/targets/mediatek/filogic/`:

| File | Use |
|------|-----|
| `*-bananapi_bpi-r4-sdcard.img.gz` | Bootable SD card image |
| `*-bananapi_bpi-r4-squashfs-sysupgrade.itb` | LuCI / `sysupgrade` OTA |

## BE14 WiFi TX-power fix

The BPI-R4-NIC-BE14 ships with a factory-defective EEPROM that caps 2.4 GHz and 5 GHz TX power at ~6-7 dBm. wrtstack uses the upstream OpenWRT fix (landed in 25.12.3): a device tree overlay (`mt7988a-bananapi-bpi-r4-wifi-be14`) that provides correct calibration data.

wrtstack bakes `/etc/uci-defaults/99-bpi-r4-be14-wifi` into every image. On first boot, this script runs `fw_setenv bootconf_extra mt7988a-bananapi-bpi-r4-wifi-be14`. U-Boot loads the overlay on the next boot, restoring TX power to ~20 dBm.

The router **auto-reboots ~10 seconds after first boot** to activate the overlay -- no manual reboot needed. After the second boot, verify with `iw dev` (expect ~20 dBm) and `fw_printenv bootconf_extra`.

## Network topology

### gw (gateway router)

| Interface | Address | Role |
|-----------|---------|------|
| br-lan.1 | 192.168.1.1 | LAN |
| br-lan.20 | 192.168.2.1 | homenet VLAN |
| br-lan.30 | 192.168.3.1 | serversNet VLAN |
| br-lan.60 | 192.168.6.1 | guestNet VLAN |
| br-lan.70 | 192.168.8.1 | UIotNet VLAN |
| WAN | DHCP | Uplink |

Domain: `ancapistan.io` | WireGuard VPN | DDNS (Namecheap) | WPA3-SAE + 802.11r

### office-wrt (secondary AP)

| Interface | Address | Role |
|-----------|---------|------|
| br-lan.1 | 192.168.1.2/24 | LAN (gw: 192.168.1.1) |
| br-lan.20 | 192.168.2.2/24 | homenet |
| br-lan.30 | DHCP | serversNet |
| br-lan.60 | 192.168.6.2/24 | guestNet |

Dnsmasq, firewall, and odhcpd disabled -- pure AP mode. Fast roaming via 802.11r / DAWN (`mobility_domain=a1b2` across all radios).

## Adding a new router

```bash
# 1. Create env file
cp env/office-wrt.env env/new-router.env
# edit env/new-router.env

# 2. Create backup directory
mkdir -p backups/new-router
touch backups/new-router/.gitkeep

# 3. Build
wrtstack build new-router
```

## Submodule

`openwrt-bpi-r4/` tracks [`openwrt/openwrt`](https://github.com/openwrt/openwrt) at a pinned commit.

```bash
# Update to latest upstream
git submodule update --remote openwrt-bpi-r4
git add openwrt-bpi-r4
git commit -m "bump openwrt submodule"
```

## Idempotency

Every `wrtstack build` run is safe to repeat:

- **apt**: no-op for already-installed packages
- **files/ overlay**: sha256-gated; rebuilt only when backup or env vars change
- **`.config`**: regenerated from profile + env on every run
- **make**: incremental; only changed components rebuild
