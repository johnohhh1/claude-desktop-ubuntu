#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/johnohhh1/claude-desktop-ubuntu/gh-pages}"
LIST_FILE="/etc/apt/sources.list.d/claude-desktop-ubuntu.list"
KEYRING_FILE="/usr/share/keyrings/claude-desktop-archive-keyring.gpg"

usage() {
	echo "Usage: $0 [--apt|--release]"
	echo "  --apt      Configure the unsigned apt repo on gh-pages and install claude-desktop (default)"
	echo "  --release  Download the latest release .deb directly and install it"
}

require_root_tools() {
	command -v sudo >/dev/null 2>&1 || {
		echo "Error: sudo is required." >&2
		exit 1
	}
}

install_via_apt() {
	require_root_tools
	echo "Configuring apt source: $REPO_URL"
	curl -fsSL "$REPO_URL/claude-desktop-archive-keyring.gpg" | sudo tee "$KEYRING_FILE" >/dev/null
	echo "deb [signed-by=$KEYRING_FILE] $REPO_URL stable main" | sudo tee "$LIST_FILE" >/dev/null
	sudo apt-get update
	sudo apt-get install -y claude-desktop
	echo
	echo "Installed claude-desktop from the signed gh-pages apt repo."
}

install_via_release() {
	require_root_tools
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' EXIT

	echo "Resolving latest release asset..."
	url="$(python3 - <<'PY'
import json
import sys
import urllib.request

api = "https://api.github.com/repos/johnohhh1/claude-desktop-ubuntu/releases/latest"
with urllib.request.urlopen(api) as r:
    data = json.load(r)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(".deb"):
        print(asset["browser_download_url"])
        break
else:
    sys.exit("No .deb asset found in the latest release")
PY
)"

	deb_path="$tmpdir/claude-desktop_latest_amd64.deb"
	curl -fsSL "$url" -o "$deb_path"
	sudo apt-get install -y "$deb_path"
	echo
	echo "Installed the latest release asset directly."
}

mode="apt"
case "${1:-}" in
	""|--apt) ;;
	--release) mode="release" ;;
	-h|--help) usage; exit 0 ;;
	*) usage; exit 1 ;;
esac

case "$mode" in
	apt) install_via_apt ;;
	release) install_via_release ;;
esac
