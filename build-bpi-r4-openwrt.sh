#!/usr/bin/env bash
# =============================================================================
# build-bpi-r4-openwrt.sh
#
# Idempotent build script for OpenWRT 25.12 targeting the Banana Pi BPI-R4
# (MediaTek MT7988A / Filogic 880) with the BPI-R4-NIC-BE14 WiFi 7 card.
#
# Includes the mt76 TX-power EEPROM fix, restoring 2.4/5 GHz output from
# the factory-defective 6–7 dBm cap to the correct ~20 dBm.
#
# Router identity is configured in one of two modes, controlled by whether
# --config-backup is passed:
#
#   Mode A — Config backup (LuCI .tar.gz export):
#     --config-backup=FILE   Extract backup into files/ overlay; baked into
#                            image. Backup is treated as authoritative.
#                            --hostname, --lan-ip, --ssh-pubkey are IGNORED
#                            (with a warning if provided).
#
#   Mode B — Explicit flags (no backup):
#     --hostname=NAME        Router hostname (required)
#     --lan-ip=A.B.C.D      LAN IP address, must be in 192.168.4.2–9 range
#                            (required)
#     --ssh-pubkey=KEY       SSH public key string for root login (required)
#
# Usage:
#   ./build-bpi-r4-openwrt.sh [OPTIONS]
#
# Options:
#   --workdir=DIR            Build directory
#                            (default: <script-dir>/openwrt-bpi-r4)
#   --jobs=N                 Parallel make jobs (default: nproc)
#   --env=FILE               Path to packages env file (see Env File below)
#   --config-backup=FILE     LuCI-exported config tarball (.tar.gz)
#   --hostname=NAME          Router hostname          [Mode B only]
#   --lan-ip=A.B.C.D         LAN IP (192.168.4.2–9)  [Mode B only]
#   --ssh-pubkey=KEY         SSH public key string    [Mode B only]
#   --flash                  Flash SD card image after build
#   --device=DEV             Block device to flash, e.g. /dev/sdb
#                            (required with --flash)
#   --help                   Show this help and exit
#
# Env File (shell variable assignments, passed via --env=FILE):
#   PACKAGES="pkg1 pkg2 pkg3"          # extra packages to include
#   PACKAGES_REMOVE="ppp ppp-mod-pppoe" # packages to explicitly exclude
#
#   Lines beginning with # are ignored. Only PACKAGES and PACKAGES_REMOVE
#   are accepted; any other variable causes an error.
#
# Idempotency:
#   - apt: no-op for already-installed packages
#   - git: fetches + fast-forwards if repo exists; never clobbers
#   - EEPROM patch: sha256-compared; only updated if upstream changed
#   - files/ overlay: rebuilt from scratch each run (fully deterministic)
#   - .config: regenerated from base + env file each run
#   - make: incremental; only changed components rebuilt
#
# Target images (in <workdir>/bin/targets/mediatek/filogic/):
#   *-bananapi_bpi-r4-sdcard.img.gz           <- SD card image (bootable)
#   *-bananapi_bpi-r4-squashfs-sysupgrade.itb  <- sysupgrade image
#
# Requirements:
#   - Ubuntu 24.04+ / 26.04 (apt-based)
#   - ~25 GB free disk space
#   - Internet access
#   - Run as a normal user (NOT root); sudo is invoked internally
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 1. Constants
# -----------------------------------------------------------------------------

OPENWRT_VERSION="25.12"
OPENWRT_BRANCH="openwrt-25.12"
OPENWRT_REPO="https://github.com/openwrt/openwrt.git"

TARGET="mediatek"
SUBTARGET="filogic"
PROFILE="bananapi_bpi-r4"

EEPROM_PATCH_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/package/kernel/mt76/patches/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch"
EEPROM_PATCH_FILE="100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch"

# Valid LAN IP range: 192.168.4.2 – 192.168.4.9
LAN_IP_NETWORK="192.168.4"
LAN_IP_MIN=2
LAN_IP_MAX=9
LAN_NETMASK="255.255.252.0"   # /22
LAN_GATEWAY="${LAN_IP_NETWORK}.1"

BASE_PACKAGES=(
    kmod-mt7996e
    kmod-mt76-connac
    mt7996-firmware
    luci
    luci-ssl
    uhttpd
    uhttpd-mod-ubus
    block-mount
    kmod-fs-ext4
    kmod-fs-vfat
    kmod-usb-storage
    e2fsprogs
    fdisk
    pciutils
)

# Resolve script directory so workdir default is relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
WORKDIR="${SCRIPT_DIR}/openwrt-bpi-r4"
JOBS=$(nproc)
ENV_FILE=""
CONFIG_BACKUP=""
OPT_HOSTNAME=""
OPT_LAN_IP=""
OPT_SSH_PUBKEY=""
DO_FLASH=false
FLASH_DEVICE=""

# Populated after env file load
EXTRA_PACKAGES=()
REMOVE_PACKAGES=()

# Populated by report_images, consumed by flash_sdcard
SDCARD_IMG_PATH=""

# Colours
RED='\033[0;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

# -----------------------------------------------------------------------------
# 2. Helpers
# -----------------------------------------------------------------------------

info()    { echo -e "${CYN}[INFO]${RST}  $*"; }
success() { echo -e "${GRN}[OK]${RST}    $*"; }
warn()    { echo -e "${YEL}[WARN]${RST}  $*"; }
error()   { echo -e "${RED}[ERROR]${RST} $*" >&2; exit 1; }
banner()  { echo -e "\n${BLD}${CYN}=== $* ===${RST}\n"; }

usage() {
    sed -n '/^# Usage:/,/^# Requirements:/p' "$0" | sed 's/^# \?//'
    exit 0
}

require_not_root() {
    [[ "${EUID}" -ne 0 ]] \
        || error "Do not run as root. sudo is invoked internally where required."
}

sha256_of() { sha256sum "$1" | awk '{print $1}'; }

# -----------------------------------------------------------------------------
# 3. Argument parsing
# -----------------------------------------------------------------------------

parse_args() {
    for arg in "$@"; do
        case "${arg}" in
            --workdir=*)        WORKDIR="${arg#*=}" ;;
            --jobs=*)           JOBS="${arg#*=}" ;;
            --env=*)            ENV_FILE="$(realpath "${arg#*=}" 2>/dev/null || echo "${arg#*=}")" ;;
            --config-backup=*)  CONFIG_BACKUP="$(realpath "${arg#*=}" 2>/dev/null || echo "${arg#*=}")" ;;
            --hostname=*)       OPT_HOSTNAME="${arg#*=}" ;;
            --lan-ip=*)         OPT_LAN_IP="${arg#*=}" ;;
            --ssh-pubkey=*)     OPT_SSH_PUBKEY="${arg#*=}" ;;
            --flash)            DO_FLASH=true ;;
            --device=*)         FLASH_DEVICE="${arg#*=}" ;;
            --help|-h)          usage ;;
            *) error "Unknown argument: '${arg}'. Use --help for usage." ;;
        esac
    done

    # Flash validation
    if [[ "${DO_FLASH}" == true ]]; then
        [[ -n "${FLASH_DEVICE}" ]] \
            || error "--flash requires --device=/dev/sdX."
        [[ -b "${FLASH_DEVICE}" ]] \
            || error "Flash device '${FLASH_DEVICE}' is not a block device."
    fi

    # Mode A: config backup provided
    if [[ -n "${CONFIG_BACKUP}" ]]; then
        [[ -f "${CONFIG_BACKUP}" ]] \
            || error "Config backup not found: ${CONFIG_BACKUP}"

        # Warn if Mode B flags were also passed — they'll be ignored
        local ignored_flags=()
        [[ -n "${OPT_HOSTNAME}"   ]] && ignored_flags+=("--hostname")
        [[ -n "${OPT_LAN_IP}"    ]] && ignored_flags+=("--lan-ip")
        [[ -n "${OPT_SSH_PUBKEY}" ]] && ignored_flags+=("--ssh-pubkey")
        if [[ ${#ignored_flags[@]} -gt 0 ]]; then
            warn "--config-backup is set; the following flags will be IGNORED:"
            for f in "${ignored_flags[@]}"; do warn "  ${f}"; done
        fi

    # Mode B: explicit flags required
    else
        local missing=()
        [[ -n "${OPT_HOSTNAME}"   ]] || missing+=("--hostname")
        [[ -n "${OPT_LAN_IP}"    ]] || missing+=("--lan-ip")
        [[ -n "${OPT_SSH_PUBKEY}" ]] || missing+=("--ssh-pubkey")
        if [[ ${#missing[@]} -gt 0 ]]; then
            error "Without --config-backup, the following flags are required:\n  ${missing[*]}\nUse --help for usage."
        fi

        # Validate LAN IP is within the allowed range
        validate_lan_ip "${OPT_LAN_IP}"

        # Validate hostname: RFC 1123 — letters, digits, hyphens; no leading/trailing hyphen
        if ! [[ "${OPT_HOSTNAME}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
            error "Invalid hostname '${OPT_HOSTNAME}'. Must be alphanumeric with optional internal hyphens."
        fi

        # Validate SSH pubkey looks like an SSH public key
        if ! [[ "${OPT_SSH_PUBKEY}" =~ ^(ssh|ecdsa)-[a-zA-Z0-9-]+ ]]; then
            error "SSH pubkey does not look like a valid SSH public key (should start with e.g. 'ssh-ed25519', 'ssh-rsa', 'ecdsa-sha2-...')."
        fi
    fi
}

validate_lan_ip() {
    local ip="$1"
    # Must be dotted-quad
    if ! [[ "${ip}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        error "Invalid IP address format: '${ip}'"
    fi
    local o1="${BASH_REMATCH[1]}"
    local o2="${BASH_REMATCH[2]}"
    local o3="${BASH_REMATCH[3]}"
    local o4="${BASH_REMATCH[4]}"

    # Must be in the 192.168.4.x network
    if [[ "${o1}.${o2}.${o3}" != "${LAN_IP_NETWORK}" ]]; then
        error "LAN IP '${ip}' must be in the ${LAN_IP_NETWORK}.0/22 network (${LAN_IP_NETWORK}.${LAN_IP_MIN}–${LAN_IP_MAX})."
    fi

    # Last octet must be in range
    if (( o4 < LAN_IP_MIN || o4 > LAN_IP_MAX )); then
        error "LAN IP last octet '${o4}' is out of range. Must be ${LAN_IP_MIN}–${LAN_IP_MAX} (${LAN_IP_NETWORK}.${LAN_IP_MIN}–${LAN_IP_NETWORK}.${LAN_IP_MAX})."
    fi
}

# -----------------------------------------------------------------------------
# 4. Env file loading
# -----------------------------------------------------------------------------

load_env_file() {
    if [[ -z "${ENV_FILE}" ]]; then
        info "No --env file specified; using base package set only."
        return
    fi

    [[ -f "${ENV_FILE}" ]] || error "Env file not found: ${ENV_FILE}"

    banner "Env file: ${ENV_FILE}"

    # Source directly — the env file is a plain bash script.
    # shellcheck disable=SC1090
    source "${ENV_FILE}"

    # Flatten any newlines to spaces, then word-split into arrays.
    local flat_pkg flat_rem
    flat_pkg=$(echo "${PACKAGES:-}"        | tr '\n' ' ')
    flat_rem=$(echo "${PACKAGES_REMOVE:-}" | tr '\n' ' ')
    read -ra EXTRA_PACKAGES  <<< "${flat_pkg}" || true
    read -ra REMOVE_PACKAGES <<< "${flat_rem}" || true

    [[ ${#EXTRA_PACKAGES[@]}  -gt 0 ]] && info "Extra packages:   ${EXTRA_PACKAGES[*]}"
    [[ ${#REMOVE_PACKAGES[@]} -gt 0 ]] && info "Packages removed: ${REMOVE_PACKAGES[*]}"

    success "Env file loaded."
}

# -----------------------------------------------------------------------------
# 5. Build host dependencies (idempotent via apt)
# -----------------------------------------------------------------------------

install_deps() {
    banner "1. Build host dependencies"

    local pkgs=(
        build-essential gcc g++ binutils
        git git-core subversion
        libncurses5-dev libncursesw5-dev
        zlib1g-dev unzip xz-utils bzip2 zstd liblzma-dev
        libssl-dev
        gawk gettext flex bison
        wget curl rsync cpio
        file time quilt patch diffutils swig ccache
        python3 python3-dev python3-distutils-extra python3-setuptools
        perl
        libelf-dev
        pv
    )

    # Check which packages are missing without touching apt or sudo.
    # dpkg-query exits 0 only if the package is installed and configured.
    local missing=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null \
                | grep -q "install ok installed"; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        success "All ${#pkgs[@]} build-host packages already installed."
        return
    fi

    info "${#missing[@]} package(s) missing: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}"

    success "Build-host dependencies satisfied."
}

# -----------------------------------------------------------------------------
# 6. Clone / update source (idempotent)
# -----------------------------------------------------------------------------

clone_source() {
    banner "2. OpenWRT ${OPENWRT_VERSION} source"

    mkdir -p "${WORKDIR}"

    if [[ -d "${WORKDIR}/.git" ]]; then
        info "Repo already exists at ${WORKDIR} — updating..."
        cd "${WORKDIR}"

        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        if [[ "${current_branch}" != "${OPENWRT_BRANCH}" ]]; then
            warn "Switching branch: '${current_branch}' → '${OPENWRT_BRANCH}'"
            git checkout "${OPENWRT_BRANCH}"
        fi

        git fetch origin
        git pull --ff-only origin "${OPENWRT_BRANCH}"
        success "Source up-to-date at $(git rev-parse --short HEAD)."
    else
        info "Cloning ${OPENWRT_REPO} → ${WORKDIR}..."
        git clone \
            --branch "${OPENWRT_BRANCH}" \
            --single-branch \
            --depth=1 \
            "${OPENWRT_REPO}" \
            "${WORKDIR}"
        cd "${WORKDIR}"
        success "Cloned at $(git rev-parse --short HEAD)."
    fi
}

# -----------------------------------------------------------------------------
# 7. EEPROM TX-power patch (idempotent via sha256)
# -----------------------------------------------------------------------------

apply_eeprom_patch() {
    banner "3. BE14 WiFi TX-power EEPROM fix"

    cd "${WORKDIR}"
    local patch_dir="package/kernel/mt76/patches"
    local patch_dest="${patch_dir}/${EEPROM_PATCH_FILE}"

    mkdir -p "${patch_dir}"

    local tmp_patch
    tmp_patch=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${tmp_patch}'" RETURN

    info "Fetching patch from immortalwrt..."
    wget -q -O "${tmp_patch}" "${EEPROM_PATCH_URL}" \
        || error "Failed to download EEPROM patch."

    grep -q "mt7996" "${tmp_patch}" \
        || error "Downloaded file does not reference mt7996 — URL may be stale."

    if [[ -f "${patch_dest}" ]]; then
        local old_sha new_sha
        old_sha=$(sha256_of "${patch_dest}")
        new_sha=$(sha256_of "${tmp_patch}")
        if [[ "${old_sha}" == "${new_sha}" ]]; then
            success "Patch unchanged (sha256: ${old_sha:0:12}…). Skipping."
            return
        fi
        warn "Patch updated upstream — replacing."
        warn "  Old: ${old_sha:0:12}…  New: ${new_sha:0:12}…"
    fi

    cp "${tmp_patch}" "${patch_dest}"
    success "Patch written → ${patch_dest}"
    head -6 "${patch_dest}" | sed 's/^/    /'
    echo ""
}

# -----------------------------------------------------------------------------
# 8. Feeds (always run; feeds track their own state)
# -----------------------------------------------------------------------------

update_feeds() {
    banner "4. Package feeds"
    cd "${WORKDIR}"
    info "Updating feeds..."
    ./scripts/feeds update -a
    info "Installing feed packages..."
    ./scripts/feeds install -a
    success "Feeds up-to-date."
}

# -----------------------------------------------------------------------------
# 9. Router configuration overlay (files/)
#
# OpenWRT's build system merges everything under <workdir>/files/ into the
# image root at build time.  We rebuild this directory from scratch on every
# run so it is always consistent with the current flags / backup.
# -----------------------------------------------------------------------------

build_files_overlay() {
    banner "5. Router configuration overlay (files/)"
    cd "${WORKDIR}"

    local files_dir="${WORKDIR}/files"
    local sentinel="${WORKDIR}/.files_overlay_sha256"

    # Compute a fingerprint of the current inputs so we can skip
    # rebuilding the overlay when nothing has changed between runs.
    local current_sig
    if [[ -n "${CONFIG_BACKUP}" ]]; then
        current_sig="backup:$(sha256_of "${CONFIG_BACKUP}")"
    else
        current_sig="flags:${OPT_HOSTNAME}:${OPT_LAN_IP}:${OPT_SSH_PUBKEY}"
    fi

    if [[ -f "${sentinel}" \
            && "$(cat "${sentinel}")" == "${current_sig}" \
            && -d "${files_dir}" ]]; then
        success "Overlay unchanged — skipping rebuild."
        return
    fi

    info "Overlay inputs changed — rebuilding files/..."
    rm -rf "${files_dir}"
    mkdir -p "${files_dir}"

    if [[ -n "${CONFIG_BACKUP}" ]]; then
        # -----------------------------------------------------------------
        # Mode A: Extract LuCI backup tarball into files/
        #
        # LuCI exports are standard sysupgrade tarballs: tar.gz with paths
        # rooted at / (entries like ./etc/config/network).  We extract
        # directly into files/ so the build system overlays them correctly.
        # -----------------------------------------------------------------
        info "Mode A: extracting config backup → ${files_dir}/"
        info "Source: ${CONFIG_BACKUP}"

        # Validate it's a valid gzip tar before extracting
        tar -tzf "${CONFIG_BACKUP}" > /dev/null 2>&1 \
            || error "Config backup '${CONFIG_BACKUP}' is not a valid .tar.gz archive."

        tar -xzf "${CONFIG_BACKUP}" -C "${files_dir}"

        # Show what was extracted
        info "Extracted paths:"
        find "${files_dir}" -type f | sed "s|${files_dir}||" | sort | sed 's/^/    /'

        # Record the input fingerprint so subsequent runs can skip this step.
        echo "${current_sig}" > "${sentinel}"
        success "Config backup extracted into overlay."

    else
        # -----------------------------------------------------------------
        # Mode B: Generate minimal config from explicit flags
        #
        # We write UCI-format config files into files/etc/config/ and an
        # authorized_keys file into files/etc/dropbear/.
        # These are the only files OpenWRT needs on first boot to have the
        # correct identity — everything else uses compiled-in defaults.
        # -----------------------------------------------------------------
        info "Mode B: generating config from --hostname / --lan-ip / --ssh-pubkey"

        mkdir -p "${files_dir}/etc/config"
        mkdir -p "${files_dir}/etc/dropbear"
        mkdir -p "${files_dir}/root/.ssh"

        # -- network config -----------------------------------------------
        # Sets the LAN interface to a static IP in the 192.168.4.0/22 subnet.
        # br-lan is the default bridge interface on the BPI-R4 profile.
        cat > "${files_dir}/etc/config/network" << EOF
# Generated by build-bpi-r4-openwrt.sh
# Hostname: ${OPT_HOSTNAME}  LAN IP: ${OPT_LAN_IP}

config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'auto'

config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	option ipaddr '${OPT_LAN_IP}'
	option netmask '${LAN_NETMASK}'
	option gateway '${LAN_GATEWAY}'
	list dns '1.1.1.1'
	list dns '8.8.8.8'

config interface 'wan'
	option device 'eth1'
	option proto 'dhcp'

config interface 'wan6'
	option device 'eth1'
	option proto 'dhcpv6'
EOF

        # -- system config ------------------------------------------------
        cat > "${files_dir}/etc/config/system" << EOF
# Generated by build-bpi-r4-openwrt.sh

config system
	option hostname '${OPT_HOSTNAME}'
	option timezone 'UTC'
	option ttylogin '0'
	option log_size '64'
	option urandom_seed '0'

config timeserver 'ntp'
	option enabled '1'
	option enable_server '0'
	list server '0.openwrt.pool.ntp.org'
	list server '1.openwrt.pool.ntp.org'
	list server '2.openwrt.pool.ntp.org'
	list server '3.openwrt.pool.ntp.org'
EOF

        # -- SSH authorized_keys ------------------------------------------
        # Dropbear reads /etc/dropbear/authorized_keys (system-wide root key)
        # and /root/.ssh/authorized_keys.  We write to both for maximum
        # compatibility across OpenWRT versions.
        printf '%s\n' "${OPT_SSH_PUBKEY}" \
            > "${files_dir}/etc/dropbear/authorized_keys"
        chmod 600 "${files_dir}/etc/dropbear/authorized_keys"

        cp "${files_dir}/etc/dropbear/authorized_keys" \
           "${files_dir}/root/.ssh/authorized_keys"
        chmod 700 "${files_dir}/root/.ssh"
        chmod 600 "${files_dir}/root/.ssh/authorized_keys"

        info "Generated files:"
        find "${files_dir}" -type f | sed "s|${files_dir}||" | sort | sed 's/^/    /'

        # Record the input fingerprint so subsequent runs can skip this step.
        echo "${current_sig}" > "${sentinel}"
        success "Configuration overlay generated."
        info "  Hostname: ${OPT_HOSTNAME}"
        info "  LAN IP:   ${OPT_LAN_IP}/${LAN_NETMASK} (gateway: ${LAN_GATEWAY})"
        info "  SSH key:  ${OPT_SSH_PUBKEY:0:40}…"
    fi
}

# -----------------------------------------------------------------------------
# 10. Build configuration (.config — regenerated every run)
# -----------------------------------------------------------------------------

configure_build() {
    banner "6. Build configuration (.config)"
    cd "${WORKDIR}"

    info "Composing package list..."

    {
        echo "# Target"
        echo "CONFIG_TARGET_${TARGET}=y"
        echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y"
        echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${PROFILE}=y"
        echo ""
        echo "# Image types"
        echo "CONFIG_TARGET_ROOTFS_EXT4FS=y"
        echo "CONFIG_TARGET_IMAGES_GZIP=y"
        echo ""
        echo "# Base packages"
        for pkg in "${BASE_PACKAGES[@]}"; do
            echo "CONFIG_PACKAGE_${pkg}=y"
        done

        if [[ ${#EXTRA_PACKAGES[@]} -gt 0 ]]; then
            echo ""
            echo "# Extra packages (from --env)"
            for pkg in "${EXTRA_PACKAGES[@]}"; do
                echo "CONFIG_PACKAGE_${pkg}=y"
            done
        fi

        if [[ ${#REMOVE_PACKAGES[@]} -gt 0 ]]; then
            echo ""
            echo "# Explicitly excluded packages (from --env)"
            for pkg in "${REMOVE_PACKAGES[@]}"; do
                echo "# CONFIG_PACKAGE_${pkg} is not set"
            done
        fi
    } > .config

    info "Expanding with make defconfig..."
    make defconfig

    success "Configuration written."
    echo ""
    echo "    Base packages:    ${#BASE_PACKAGES[@]}"
    echo "    Extra packages:   ${#EXTRA_PACKAGES[@]}"
    echo "    Excluded:         ${#REMOVE_PACKAGES[@]}"
    echo ""
    info "To customise interactively: cd ${WORKDIR} && make menuconfig"
}

# -----------------------------------------------------------------------------
# 11. Build (incremental)
# -----------------------------------------------------------------------------

build_image() {
    banner "7. Building image  (first run: 45–90 min; incremental: faster)"
    cd "${WORKDIR}"

    info "Parallel jobs: ${JOBS}"
    info "Log:           ${WORKDIR}/build.log"
    echo ""

    if ! make -j"${JOBS}" V=s 2>&1 | tee build.log; then
        echo ""
        echo -e "${RED}Build failed. Last 80 lines of build.log:${RST}" >&2
        tail -80 "${WORKDIR}/build.log" >&2
        exit 1
    fi

    success "Build complete."
}

# -----------------------------------------------------------------------------
# 12. Report output images
# -----------------------------------------------------------------------------

report_images() {
    banner "8. Output images"
    cd "${WORKDIR}"

    local img_dir="bin/targets/${TARGET}/${SUBTARGET}"
    [[ -d "${img_dir}" ]] \
        || error "Image output directory not found: ${WORKDIR}/${img_dir}"

    local sdcard_img sysupgrade_img
    sdcard_img=$(find "${img_dir}" -name "*bananapi_bpi-r4*sdcard*.img.gz" \
                    2>/dev/null | sort | tail -1)
    sysupgrade_img=$(find "${img_dir}" -name "*bananapi_bpi-r4*sysupgrade*" \
                        2>/dev/null | sort | tail -1)

    echo ""
    if [[ -n "${sdcard_img}" ]]; then
        success "SD card image:    ${WORKDIR}/${sdcard_img}"
        echo "    Size: $(du -h "${sdcard_img}" | cut -f1)"
    else
        warn "SD card image not found — check build output."
    fi

    if [[ -n "${sysupgrade_img}" ]]; then
        success "Sysupgrade image: ${WORKDIR}/${sysupgrade_img}"
        echo "    Size: $(du -h "${sysupgrade_img}" | cut -f1)"
    else
        warn "Sysupgrade image not found."
    fi

    local router_ip="${OPT_LAN_IP:-<ip-from-backup>}"
    echo ""
    info "Manual flash:"
    echo "    gunzip -c ${WORKDIR}/${sdcard_img} \\"
    echo "        | sudo dd bs=4M status=progress conv=fsync of=/dev/sdX"
    echo ""
    info "First-boot access:"
    echo "    http://${router_ip}      (LuCI)"
    echo "    ssh root@${router_ip}    (SSH)"
    echo ""

    SDCARD_IMG_PATH="${sdcard_img}"
}

# -----------------------------------------------------------------------------
# 13. Flash (optional)
# -----------------------------------------------------------------------------

flash_sdcard() {
    banner "9. Flashing to ${FLASH_DEVICE}"

    [[ -n "${SDCARD_IMG_PATH}" ]] || error "No SD card image path available."
    cd "${WORKDIR}"

    # Refuse to flash the host system disk
    local sys_disk
    sys_disk=$(findmnt -n -o SOURCE / | sed 's/p\?[0-9]*$//')
    [[ "${FLASH_DEVICE}" != "${sys_disk}" ]] \
        || error "Refusing: ${FLASH_DEVICE} is the system root disk (${sys_disk})."

    echo ""
    warn "Target device: ${FLASH_DEVICE}"
    warn "Image:         ${WORKDIR}/${SDCARD_IMG_PATH}"
    warn "ALL DATA ON ${FLASH_DEVICE} WILL BE ERASED."
    echo ""
    read -rp "Type 'yes' to proceed: " confirm
    [[ "${confirm}" == "yes" ]] || { info "Aborted."; exit 0; }

    info "Unmounting partitions on ${FLASH_DEVICE}..."
    local part
    while IFS= read -r part; do
        if [[ -n "${part}" ]] && mountpoint -q "${part}" 2>/dev/null; then
            info "  Unmounting ${part}..."
            sudo umount "${part}"
        fi
    done < <(lsblk -ln -o PATH "${FLASH_DEVICE}" | tail -n +2)

    info "Writing image..."
    if command -v pv &>/dev/null; then
        gunzip -c "${SDCARD_IMG_PATH}" \
            | pv -s "$(gzip -l "${SDCARD_IMG_PATH}" | awk 'NR==2{print $2}')" \
            | sudo dd bs=4M conv=fsync of="${FLASH_DEVICE}"
    else
        gunzip -c "${SDCARD_IMG_PATH}" \
            | sudo dd bs=4M status=progress conv=fsync of="${FLASH_DEVICE}"
    fi

    sync
    echo ""
    success "Flash complete."

    local router_ip="${OPT_LAN_IP:-<ip-from-backup>}"
    local router_host="${OPT_HOSTNAME:-<hostname-from-backup>}"
    echo ""
    info "Post-flash checklist:"
    echo "  1. SW4 dip switch → ON  (enables BE14 PCIe power)"
    echo "  2. LuCI:  http://${router_ip}"
    echo "  3. SSH:   ssh root@${router_ip}   (key auth; set a root password via LuCI)"
    echo "  4. Hostname will be: ${router_host}"
    echo "  5. Verify TX power:  iw dev  (expect ~20 dBm on 2.4G/5G)"
    echo "  6. If 6–7 dBm:       dmesg | grep mt7996  (EEPROM load messages)"
}

# -----------------------------------------------------------------------------
# 14. Main
# -----------------------------------------------------------------------------

main() {
    require_not_root
    parse_args "$@"
    load_env_file

    local mode="B (explicit flags)"
    [[ -n "${CONFIG_BACKUP}" ]] && mode="A (config backup: $(basename "${CONFIG_BACKUP}"))"

    echo ""
    echo -e "${BLD}BPI-R4 OpenWRT ${OPENWRT_VERSION} Build Script${RST}"
    echo -e "  Target:    ${TARGET}/${SUBTARGET} — ${PROFILE}"
    echo -e "  Workdir:   ${WORKDIR}"
    echo -e "  Jobs:      ${JOBS}"
    echo -e "  Env file:  ${ENV_FILE:-<none>}"
    echo -e "  Mode:      ${mode}"
    if [[ -z "${CONFIG_BACKUP}" ]]; then
        echo -e "  Hostname:  ${OPT_HOSTNAME}"
        echo -e "  LAN IP:    ${OPT_LAN_IP}"
        echo -e "  SSH key:   ${OPT_SSH_PUBKEY:0:40}…"
    fi
    echo -e "  Flash:     ${DO_FLASH}$( \
        [[ "${DO_FLASH}" == true ]] && echo " → ${FLASH_DEVICE}" || true)"
    echo ""

    install_deps
    clone_source
    apply_eeprom_patch
    update_feeds
    build_files_overlay     # <-- new; must run before configure_build
    configure_build
    build_image
    report_images

    [[ "${DO_FLASH}" == true ]] && flash_sdcard

    banner "All done"
    success "OpenWRT ${OPENWRT_VERSION} for BPI-R4 is ready."
    info "BE14 TX-power EEPROM fix is baked into the kernel module."
    info "Router configuration is baked into the image via files/ overlay."
}

main "$@"