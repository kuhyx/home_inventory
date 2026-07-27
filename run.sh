#!/bin/bash
#
# ============================================================================
# run.sh — install Flutter if missing, build the web bundle, and launch the
# home_inventory desktop app (a Chrome app window served by a local wrapper).
#
# Usage: ./run.sh [--no-browser]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly AUR_FLUTTER_BIN_URL="https://aur.archlinux.org/flutter-bin.git"

BUILD_DIR=""
cleanup() {
    if [[ -n "${BUILD_DIR}" && -d "${BUILD_DIR}" ]]; then
        rm -rf "${BUILD_DIR}"
    fi
}
trap cleanup EXIT

log() { printf '==> %s\n' "$1"; }
err() { printf 'error: %s\n' "$1" >&2; }

# Echoes "arch" or "debian" depending on /etc/os-release; exits otherwise.
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        case "${ID:-}:${ID_LIKE:-}" in
            *arch*) echo "arch"; return ;;
            *debian*|*ubuntu*) echo "debian"; return ;;
        esac
    fi
    err "unsupported distro (expected Arch Linux or Ubuntu/Debian)"
    exit 1
}

require_non_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "run as a regular user with sudo access, not as root (makepkg/apt need that)"
        exit 1
    fi
}

# makepkg refuses to run as root, so flutter-bin is built directly from its
# AUR git repo rather than requiring an AUR helper (yay/paru) to be installed.
install_flutter_arch() {
    command -v flutter >/dev/null 2>&1 && return
    log "flutter not found; building flutter-bin from the AUR"
    sudo pacman -S --needed --noconfirm base-devel git
    BUILD_DIR="$(mktemp -d)"
    git clone --depth 1 "${AUR_FLUTTER_BIN_URL}" "${BUILD_DIR}/flutter-bin"
    (cd "${BUILD_DIR}/flutter-bin" && makepkg -si --noconfirm)
}

# Prefers a real apt package if the user's mirrors happen to carry one;
# Ubuntu/Debian have none in the standard repos as of writing, so this
# normally falls back to cloning the upstream Flutter SDK.
install_flutter_debian() {
    command -v flutter >/dev/null 2>&1 && return
    log "flutter not found; checking apt for a flutter package"
    sudo apt-get update -qq
    if apt-cache show flutter >/dev/null 2>&1; then
        sudo apt-get install -y flutter
        return
    fi
    log "no apt package named 'flutter'; cloning the Flutter SDK instead"
    local install_dir="${HOME}/development/flutter"
    if [[ ! -d "${install_dir}" ]]; then
        sudo apt-get install -y git curl
        git clone --depth 1 -b stable https://github.com/flutter/flutter.git "${install_dir}"
    fi
    export PATH="${install_dir}/bin:${PATH}"
    log "flutter installed at ${install_dir}; add 'export PATH=\"${install_dir}/bin:\$PATH\"' to your shell rc to make this permanent"
}

main() {
    require_non_root
    local distro
    distro="$(detect_distro)"

    case "${distro}" in
        arch)   install_flutter_arch ;;
        debian) install_flutter_debian ;;
    esac

    # Deliberately no clang/cmake/ninja/gtk3 here, unlike a stock Flutter
    # desktop project: this repo has no linux/ embedder directory and never
    # will (README). The desktop app is the *web* build in a Chrome app
    # window, so the GTK toolchain would be installed and never used.

    command -v flutter >/dev/null 2>&1 || { err "flutter still not on PATH after install"; exit 1; }

    cd "${SCRIPT_DIR}"
    flutter config --enable-web >/dev/null
    log "fetching pub packages"
    flutter pub get

    log "building the web bundle"
    flutter build web --release

    log "launching the app"
    # exec so Ctrl-C reaches the wrapper directly and it can stop its server.
    exec dart run bin/home_inventory_desktop.dart \
        --web-root "${SCRIPT_DIR}/build/web" "$@"
}

main "$@"
