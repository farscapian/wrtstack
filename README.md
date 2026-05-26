# openwrt-builder

Idempotent OpenWRT 25.12 image builder for the **Banana Pi BPI-R4** (MediaTek MT7988A / Filogic 880) with the BPI-R4-NIC-BE14 WiFi 7 card.

Produces a bootable SD card image and a sysupgrade `.itb` with configuration baked in at build time. Supports two routers — a gateway (`gw`) and a secondary AP (`office-wrt`) — each with their own package set and optional LuCI config backup.

## Hardware

| Component | Detail |
|-----------|--------|
| Board | Banana Pi BPI-R4 |
| SoC | MediaTek MT7988A (Filogic 880) |
| WiFi card | BPI-R4-NIC-BE14 (mt7996 / WiFi 7) |
| OpenWRT target | `mediatek/filogic` |
| OpenWRT profile | `bananapi_bpi-r4` |

## Prerequisites

- Ubuntu 24.04+ or 26.04 (apt-based)
- ~25 GB free disk space
- Internet access
- Run as a **normal user** (not root)

Clone with submodule:

```bash
git clone --recurse-submodules git@github.com:farscapian/openwrt-builder.git
cd openwrt-builder
```

## Usage

### Mode A — from a LuCI config backup (production workflow)

Config identity (hostname, IP, network interfaces, WiFi) is sourced entirely from the backup tarball. Pass `--config-backup` and optionally `--flash` to write directly to an SD card.

```bash
# Build + flash gateway router
./build-bpi-r4-openwrt.sh \
    --config-backup=configs/gw-wrt/backup-gw-2026-04-13.tar.gz \
    --env=configs/gw-wrt/gw-packages.env \
    --flash --device=/dev/sdb

# Build + flash office AP
./build-bpi-r4-openwrt.sh \
    --config-backup=configs/office-wrt/backup-office-wrt-2026-04-13.tar.gz \
    --env=configs/office-wrt/office-packages.env \
    --flash --device=/dev/sdb
```

### Mode B — explicit flags (first build or no backup)

```bash
./build-bpi-r4-openwrt.sh \
    --hostname=gw \
    --lan-ip=192.168.4.2 \
    --ssh-pubkey="ssh-ed25519 AAAA..." \
    --env=configs/gw-wrt/gw-packages.env
```

Valid `--lan-ip` range: `192.168.4.2` – `192.168.4.9`.

### All options

| Flag | Description |
|------|-------------|
| `--workdir=DIR` | Build directory (default: `./openwrt-bpi-r4`) |
| `--jobs=N` | Parallel make jobs (default: `nproc`) |
| `--env=FILE` | Package env file |
| `--config-backup=FILE` | LuCI-exported `.tar.gz` backup (Mode A) |
| `--hostname=NAME` | Router hostname (Mode B) |
| `--lan-ip=A.B.C.D` | LAN IP in `192.168.4.2–9` (Mode B) |
| `--ssh-pubkey=KEY` | SSH public key for root login (Mode B) |
| `--flash` | Flash SD card image after build |
| `--device=DEV` | Block device for `--flash`, e.g. `/dev/sdb` |

## Env files

Each router has a `configs/<name>/<name>-packages.env` defining extra packages:

```bash
PACKAGES="hostapd-openssl dawn luci-app-dawn kmod-wireguard wireguard-tools ..."
PACKAGES_REMOVE="wpad-basic-wolfssl wpad-wolfssl wpad-openssl"
```

Only `PACKAGES` and `PACKAGES_REMOVE` are accepted; any other variable causes an error.

## Output images

Built to `openwrt-bpi-r4/bin/targets/mediatek/filogic/`:

| File | Use |
|------|-----|
| `*-bananapi_bpi-r4-sdcard.img.gz` | Bootable SD card image |
| `*-bananapi_bpi-r4-squashfs-sysupgrade.itb` | LuCI / `sysupgrade` over-the-air |

## mt76 EEPROM TX-power fix

The BPI-R4-NIC-BE14 ships with a factory-defective EEPROM that caps 2.4 GHz and 5 GHz TX power at ~6–7 dBm. The build script fetches a patch from immortalwrt that restores output to ~20 dBm by falling back to firmware defaults when the EEPROM value is out of range. The patch is sha256-verified on every run and only re-applied if changed upstream.

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

Domain: `ancapistan.io` · WireGuard VPN · DDNS (Namecheap) · WPA3-SAE + 802.11r

### office-wrt (secondary AP)

| Interface | Address | Role |
|-----------|---------|------|
| br-lan.1 | 192.168.1.2/24 | LAN (gw: 192.168.1.1) |
| br-lan.20 | 192.168.2.2/24 | homenet |
| br-lan.30 | DHCP | serversNet |
| br-lan.60 | 192.168.6.2/24 | guestNet |

Dnsmasq, firewall, and odhcpd are disabled — pure AP mode. Fast roaming via 802.11r / DAWN (`mobility_domain=a1b2` across all radios).

## Idempotency

Every run is safe to repeat:

- **apt**: no-op for already-installed packages
- **git**: fetches + fast-forwards; never clobbers local changes
- **EEPROM patch**: sha256-gated; skipped if unchanged
- **files/ overlay**: rebuilt from scratch each run
- **`.config`**: regenerated from base profile + env file each run
- **make**: incremental; only changed components rebuilt

## Submodule

`openwrt-bpi-r4/` tracks [`openwrt/openwrt`](https://github.com/openwrt/openwrt) at a pinned commit on `heads/main`.

```bash
# Update to latest upstream
git submodule update --remote openwrt-bpi-r4
git add openwrt-bpi-r4
git commit -m "bump openwrt submodule"
```
