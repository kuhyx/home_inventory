#!/bin/bash
# ============================================================================
# Builds home_inventory and installs it as an Arch Linux package via pacman.
# Run from anywhere — uses the directory of this script as the repo root.
# Requires: flutter, base-devel (provides makepkg), sudo for pacman.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The desktop app is a Flutter *web* build served by a small local wrapper.
# Flutter's Linux embedder only reaches ~20fps at 4K on this hardware, while
# the same Dart code in Chrome sustains ~144fps — see the README.
readonly WEB_DIR="$SCRIPT_DIR/build/web"
readonly WRAPPER_BUNDLE="$SCRIPT_DIR/build/cli/bundle"
readonly PKGNAME="home-inventory"
WORK_DIR="$(mktemp -d)"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# Parse version from pubspec.yaml (strip build number: 1.0.0+1 → 1.0.0)
PKGVER="$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" | sed 's/^version:[[:space:]]*//' | sed 's/+.*//')"
readonly PKGVER

echo "==> Building $PKGNAME $PKGVER (Flutter web release)..."
cd "$SCRIPT_DIR"
flutter build web --release

echo "==> Compiling the desktop wrapper..."
# AOT-compiled so the installed package needs no Dart SDK at run time.
# `dart build cli`, not `dart compile exe`: the package pulls in dependencies
# with native build hooks, which `dart compile` refuses to handle even though
# the wrapper itself uses none of them.
rm -rf "$SCRIPT_DIR/build/cli"
dart build cli -o "$SCRIPT_DIR/build/cli"

echo "==> Generating PKGBUILD..."
cat > "$WORK_DIR/PKGBUILD" <<EOF
pkgname=$PKGNAME
pkgver=$PKGVER
pkgrel=1
pkgdesc='Offline-first household inventory'
arch=('x86_64')
url='https://github.com/kuhyx/home_inventory'
license=('custom')
# No hard browser dependency. A Chrome-family browser renders the UI, but
# naming one as a dependency is wrong here: makepkg installs it, and this
# system has a policy that immediately removes 'chromium' again, which then
# fails dependency resolution. The wrapper discovers whatever browser is
# actually present (including Thorium) and reports clearly if none is.
depends=()
optdepends=('chromium: renders the app window'
            'google-chrome: renders the app window')
# Flutter release binaries are already stripped/AOT-compiled with no
# extractable DWARF debug info, so a split -debug package is pointless here
# and gdb-add-index just fails noisily on every binary.
# !strip is load-bearing: the wrapper is a Dart AOT executable with its
# snapshot embedded in the ELF, and stripping it discards that snapshot. The
# stripped binary still runs but is just the bare Dart VM, which prints a
# usage message instead of starting the app.
options=('!strip' '!debug')

package() {
    # Preserve the bundle's bin/ layout: the executable resolves the web
    # assets relative to its own path, at ../web.
    install -dm755 "\$pkgdir/opt/$PKGNAME"
    cp -r "$WRAPPER_BUNDLE/bin" "\$pkgdir/opt/$PKGNAME/bin"
    # lib/ only exists when a dependency ships a native library, and this
    # wrapper has none — verified: \`dart build cli\` emits bin/ alone here.
    # Copied conditionally so adding such a dependency later does not
    # silently produce a package that cannot start.
    if [ -d "$WRAPPER_BUNDLE/lib" ]; then
        cp -r "$WRAPPER_BUNDLE/lib" "\$pkgdir/opt/$PKGNAME/lib"
    fi
    chmod 755 "\$pkgdir/opt/$PKGNAME/bin/home_inventory_desktop"

    install -dm755 "\$pkgdir/opt/$PKGNAME/web"
    cp -r "$WEB_DIR/." "\$pkgdir/opt/$PKGNAME/web/"

    install -dm755 "\$pkgdir/usr/bin"
    cat > "\$pkgdir/usr/bin/$PKGNAME" <<'WRAPPER'
#!/bin/bash
exec /opt/$PKGNAME/bin/home_inventory_desktop "\$@"
WRAPPER
    chmod 755 "\$pkgdir/usr/bin/$PKGNAME"
}
EOF

echo "==> Installing package via makepkg..."
cd "$WORK_DIR"
makepkg -sif --noconfirm

# Remove stale wrappers that shadow /usr/bin/$PKGNAME from the package.
# ~/.local/bin and /usr/local/bin both precede /usr/bin in PATH.
if [[ -f "$HOME/.local/bin/$PKGNAME" ]]; then
    echo "==> Removing old ~/.local/bin/$PKGNAME..."
    rm "$HOME/.local/bin/$PKGNAME"
fi
if [[ -f "/usr/local/bin/$PKGNAME" ]]; then
    echo "==> Removing old /usr/local/bin/$PKGNAME (requires sudo)..."
    sudo rm "/usr/local/bin/$PKGNAME"
fi

echo "==> Installing the launcher icon and .desktop entry..."
bash "$SCRIPT_DIR/desktop/install_desktop_entry.sh"

echo "==> Done. '$PKGNAME' now runs version $PKGVER installed via pacman."
