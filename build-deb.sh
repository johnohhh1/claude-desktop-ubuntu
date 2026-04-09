#!/usr/bin/env bash
set -euo pipefail

#===============================================================================
# build-deb.sh — Build Claude Desktop .deb for Ubuntu from Windows MSIX
#
# Usage: ./build-deb.sh --exe /path/to/Claude-Setup-x64.exe
#        ./build-deb.sh --msix /path/to/Claude.msix
#
# Requires: dpkg-dev, nodejs, npm, python3, file, unzip (or 7z)
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

# Defaults
MSIX_PATH=""
VERSION=""
ARCH="amd64"

usage() {
    echo "Usage: $0 --exe <path> | --msix <path>"
    echo "  --exe   Path to Claude-Setup-x64.exe or .msixbundle"
    echo "  --msix  Path to extracted .msix file"
    echo "  --version  Override version string (auto-detected from MSIX)"
    exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --exe|--msix) MSIX_PATH="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[[ -z "$MSIX_PATH" ]] && { echo "Error: --exe or --msix required"; usage; }
[[ -f "$MSIX_PATH" ]] || { echo "Error: File not found: $MSIX_PATH"; exit 1; }

echo "=== Claude Desktop Linux .deb Builder ==="
echo "Source: $MSIX_PATH"

#-------------------------------------------------------------------------------
# Step 1: Extract MSIX
#-------------------------------------------------------------------------------
EXTRACT_DIR="$SCRIPT_DIR/extract"
STAGING_DIR="$SCRIPT_DIR/staging"
DIST_DIR="$SCRIPT_DIR/dist"

rm -rf "$EXTRACT_DIR" "$STAGING_DIR"
mkdir -p "$EXTRACT_DIR" "$STAGING_DIR" "$DIST_DIR"

echo "[1/6] Extracting MSIX..."

file_type=$(file -b "$MSIX_PATH")
if [[ "$file_type" == *"Zip"* ]] || [[ "$MSIX_PATH" == *.msix* ]] || [[ "$MSIX_PATH" == *.exe ]]; then
    unzip -q -o "$MSIX_PATH" -d "$EXTRACT_DIR" 2>/dev/null \
        || 7z x -y -o"$EXTRACT_DIR" "$MSIX_PATH" >/dev/null \
        || { echo "Error: Cannot extract. Install unzip or 7z."; exit 1; }
else
    echo "Error: Unrecognized file type: $file_type"
    exit 1
fi

# If this was a bundle, find the x64 MSIX inside
if ls "$EXTRACT_DIR"/*.msix &>/dev/null; then
    X64_MSIX=$(find "$EXTRACT_DIR" -name "*x64*" -o -name "*amd64*" | head -1)
    if [[ -z "$X64_MSIX" ]]; then
        X64_MSIX=$(find "$EXTRACT_DIR" -name "*.msix" | head -1)
    fi
    echo "  Found inner MSIX: $(basename "$X64_MSIX")"
    INNER_DIR="$EXTRACT_DIR/inner"
    mkdir -p "$INNER_DIR"
    unzip -q -o "$X64_MSIX" -d "$INNER_DIR" 2>/dev/null \
        || 7z x -y -o"$INNER_DIR" "$X64_MSIX" >/dev/null
    EXTRACT_DIR="$INNER_DIR"
fi

#-------------------------------------------------------------------------------
# Step 2: Auto-detect version
#-------------------------------------------------------------------------------
echo "[2/6] Detecting version..."
if [[ -z "$VERSION" ]]; then
    # Try AppxManifest.xml
    if [[ -f "$EXTRACT_DIR/AppxManifest.xml" ]]; then
        VERSION=$(grep -oP 'Version="\K[^"]+' "$EXTRACT_DIR/AppxManifest.xml" | head -1) || true
    fi
    # Fallback: directory name or filename
    if [[ -z "$VERSION" ]]; then
        VERSION=$(echo "$MSIX_PATH" | grep -oP '\d+\.\d+\.\d+' | head -1) || true
    fi
    [[ -z "$VERSION" ]] && VERSION="0.0.0"
fi
echo "  Version: $VERSION"

# Convert Windows version to deb-friendly format
DEB_VERSION=$(echo "$VERSION" | sed 's/\./-/3')

#-------------------------------------------------------------------------------
# Step 3: Install Linux Electron
#-------------------------------------------------------------------------------
echo "[3/6] Installing Linux Electron..."
ELECTRON_DIR="$STAGING_DIR/usr/lib/claude-desktop/node_modules/electron"
mkdir -p "$ELECTRON_DIR"

# Use npm to get the correct Electron version
cd "$STAGING_DIR/usr/lib/claude-desktop"
npm init -y --silent >/dev/null 2>&1
npm install electron --no-save --silent 2>/dev/null
cd "$SCRIPT_DIR"

#-------------------------------------------------------------------------------
# Step 4: Place app payload and Linux-specific files
#-------------------------------------------------------------------------------
echo "[4/6] Placing app payload and Linux patches..."

APP_RESOURCES="$ELECTRON_DIR/dist/resources"

# Copy the app.asar from extracted MSIX
if [[ -f "$EXTRACT_DIR/resources/app.asar" ]]; then
    cp "$EXTRACT_DIR/resources/app.asar" "$APP_RESOURCES/app.asar"
elif [[ -f "$EXTRACT_DIR/app.asar" ]]; then
    cp "$EXTRACT_DIR/app.asar" "$APP_RESOURCES/app.asar"
else
    echo "Error: app.asar not found in extracted MSIX"
    exit 1
fi

# Copy app.asar.unpacked if it exists
for dir in "$EXTRACT_DIR/resources/app.asar.unpacked" "$EXTRACT_DIR/app.asar.unpacked"; do
    if [[ -d "$dir" ]]; then
        cp -r "$dir" "$APP_RESOURCES/app.asar.unpacked"
        break
    fi
done

# Replace @ant/claude-native with our Linux stub
NATIVE_DIR="$APP_RESOURCES/app.asar.unpacked/node_modules/@ant/claude-native"
mkdir -p "$NATIVE_DIR"
cp "$SRC_DIR/claude-native-linux.js" "$NATIVE_DIR/index.js"

# Copy locale/resource files from extracted MSIX if present
for f in "$EXTRACT_DIR/resources/"*.json; do
    [[ -f "$f" ]] && cp "$f" "$APP_RESOURCES/" 2>/dev/null || true
done

# Copy launcher scripts
mkdir -p "$STAGING_DIR/usr/bin"
mkdir -p "$STAGING_DIR/usr/lib/claude-desktop"
cp "$SRC_DIR/claude-desktop" "$STAGING_DIR/usr/bin/claude-desktop"
cp "$SRC_DIR/launcher-common.sh" "$STAGING_DIR/usr/lib/claude-desktop/launcher-common.sh"
chmod +x "$STAGING_DIR/usr/bin/claude-desktop"

# Desktop entry
mkdir -p "$STAGING_DIR/usr/share/applications"
cp "$SRC_DIR/claude-desktop.desktop" "$STAGING_DIR/usr/share/applications/"

# Icons — extract from MSIX or use placeholders
for size in 16 24 32 48 64 256; do
    icon_dir="$STAGING_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    # Try to find icons in extracted MSIX
    src_icon=$(find "$EXTRACT_DIR" -name "*${size}*" -name "*.png" 2>/dev/null | head -1)
    if [[ -n "$src_icon" ]]; then
        cp "$src_icon" "$icon_dir/claude-desktop.png"
    elif [[ -f "$SCRIPT_DIR/icons/${size}.png" ]]; then
        cp "$SCRIPT_DIR/icons/${size}.png" "$icon_dir/claude-desktop.png"
    fi
done

#-------------------------------------------------------------------------------
# Step 5: Create DEBIAN control file
#-------------------------------------------------------------------------------
echo "[5/6] Creating package metadata..."
mkdir -p "$STAGING_DIR/DEBIAN"
cat > "$STAGING_DIR/DEBIAN/control" << EOF
Package: claude-desktop
Version: ${DEB_VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, xdg-utils, libatspi2.0-0, libsecret-1-0
Recommends: bubblewrap, socat
Suggests: qemu-system-x86, virtiofsd
Maintainer: johnohhh1
Description: Claude Desktop for Linux
 Anthropic's Claude Desktop application repackaged for Ubuntu Linux.
 Includes Wayland support, XWayland fallback, Linux-native claude-native
 stub, and comprehensive diagnostic tooling.
EOF

# Post-install: update desktop database
cat > "$STAGING_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
EOF
chmod 755 "$STAGING_DIR/DEBIAN/postinst"

#-------------------------------------------------------------------------------
# Step 6: Build the .deb
#-------------------------------------------------------------------------------
echo "[6/6] Building .deb package..."
DEB_NAME="claude-desktop_${DEB_VERSION}_${ARCH}.deb"
dpkg-deb --build "$STAGING_DIR" "$DIST_DIR/$DEB_NAME"

echo ""
echo "=== Build Complete ==="
echo "Package: $DIST_DIR/$DEB_NAME"
echo ""
echo "Install with:"
echo "  sudo apt-get install ./$DIST_DIR/$DEB_NAME"
echo ""
echo "Then run:"
echo "  claude-desktop"
echo ""
echo "Diagnostics:"
echo "  claude-desktop --doctor"

# Cleanup
rm -rf "$EXTRACT_DIR" "$STAGING_DIR"
