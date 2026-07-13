#!/usr/bin/env bash
# =============================================================================
# setup.sh -- One-time setup for the BPI-R4 OpenWRT builder
#
# - Installs apt build dependencies
# - Initializes the openwrt-bpi-r4 git submodule
# - Creates the backups/ directory structure
# - Adds the 'wrtstack' command to ~/.local/bin
#
# Run once after cloning. Safe to re-run (all steps are idempotent).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
CLI="${SCRIPT_DIR}/wrtstack"

RED='\033[0;31m'
GRN='\033[0;32m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

info()    { echo -e "${CYN}[INFO]${RST}  $*"; }
success() { echo -e "${GRN}[OK]${RST}    $*"; }
error()   { echo -e "${RED}[ERROR]${RST} $*" >&2; exit 1; }
banner()  { echo -e "\n${BLD}${CYN}=== $* ===${RST}\n"; }

require_not_root() {
    [[ "${EUID}" -ne 0 ]] \
        || error "Do not run as root. sudo is invoked internally where required."
}

install_deps() {
    banner "Build dependencies"

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

    local missing=()
    for pkg in "${pkgs[@]}"; do
        dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null \
            | grep -q "install ok installed" || missing+=("${pkg}")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        success "All ${#pkgs[@]} build dependencies already installed."
        return
    fi

    info "${#missing[@]} package(s) to install: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}"
    success "Build dependencies installed."
}

init_submodule() {
    banner "OpenWRT submodule"

    info "Syncing openwrt-bpi-r4 submodule to latest upstream..."
    git -C "${SCRIPT_DIR}" submodule update --init --remote openwrt-bpi-r4
    success "Submodule up to date."
}

select_submodule_tag() {
    banner "OpenWRT release tag"

    local sub="${SCRIPT_DIR}/openwrt-bpi-r4"

    info "Fetching tags from upstream..."
    git -C "${sub}" fetch --tags --quiet

    local current
    current=$(git -C "${sub}" describe --tags --exact-match 2>/dev/null \
        || git -C "${sub}" rev-parse --short HEAD)

    mapfile -t tags < <(git -C "${sub}" tag --sort=-version:refname | head -5)

    if [[ ${#tags[@]} -eq 0 ]]; then
        info "No tags found in submodule; staying on current ref (${current})."
        return
    fi

    local latest="${tags[0]}"

    info "Current submodule ref: ${current}"
    echo ""
    echo "  Recent tags:"
    for tag in "${tags[@]}"; do
        printf "    %s\n" "${tag}"
    done
    echo ""

    if [[ "${current}" == "${latest}" ]]; then
        success "Already on latest tag (${latest})."
        return
    fi

    read -rp "Switch to latest tag (${latest})? [y/N] " answer
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
        git -C "${sub}" checkout "${latest}" --quiet
        info "Updating nested submodules..."
        git -C "${sub}" submodule update --init --recursive
        success "Switched submodule to ${latest} with all nested submodules."
        info "To record this: git add openwrt-bpi-r4 && git commit -m \"pin openwrt to ${latest}\""
    else
        info "Keeping current ref: ${current}"
    fi
}

create_dirs() {
    banner "Directory structure"

    local made=0
    for d in backups/gw-wrt backups/office-wrt; do
        if [[ ! -d "${SCRIPT_DIR}/${d}" ]]; then
            mkdir -p "${SCRIPT_DIR}/${d}"
            touch "${SCRIPT_DIR}/${d}/.gitkeep"
            (( made++ )) || true
        fi
    done

    if [[ "${made}" -eq 0 ]]; then
        success "backups/ directories already exist."
    else
        success "Created ${made} backup director(y/ies)."
        info "Place LuCI .tar.gz exports in backups/gw-wrt/ or backups/office-wrt/."
    fi
}

add_symlink() {
    banner "Shell command (wrtstack)"

    local local_bin="${HOME}/.local/bin"
    local link="${local_bin}/wrtstack"

    mkdir -p "${local_bin}"
    chmod +x "${CLI}"

    # Always re-create the symlink so it tracks the current repo location.
    if [[ -e "${link}" || -L "${link}" ]]; then
        rm -f "${link}"
    fi
    ln -s "${CLI}" "${link}"
    success "Created symlink: ${link} -> ${CLI}"

    if [[ ":${PATH}:" != *":${local_bin}:"* ]]; then
        if ! grep -q "export PATH=.*\.local/bin" "${HOME}/.bashrc" 2>/dev/null; then
            {
                echo ""
                echo "# Add ~/.local/bin to PATH for wrtstack command"
                echo "export PATH=\"\${HOME}/.local/bin:\${PATH}\""
            } >> "${HOME}/.bashrc"
            success "Added ~/.local/bin to PATH in ~/.bashrc"
        fi
    fi
}

main() {
    require_not_root

    echo ""
    echo -e "${BLD}${CYN}BPI-R4 OpenWRT Builder -- Setup${RST}"
    echo ""

    install_deps
    init_submodule
    select_submodule_tag
    create_dirs
    add_symlink

    echo ""
    echo -e "${GRN}${BLD}Setup complete.${RST}"
    echo ""
    echo "  Reload your shell:     source ~/.bashrc  (if ~/.local/bin was just added to PATH)"
    echo "  Build gateway router:  wrtstack build gw-wrt"
    echo "  Build office AP:       wrtstack build office-wrt"
    echo "  Flash gw-wrt:          wrtstack flash gw-wrt --device=/dev/sdb"
    echo ""
}

main "$@"
