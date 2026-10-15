#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 /path/to/claude-desktop_<version>_amd64.deb [output-dir] [--sign <key-id>] [--public-key <path>]" >&2
	exit 1
}

[[ $# -ge 1 ]] || usage

DEB_PATH=""
OUT_DIR="apt"
SIGN_KEY_ID="${APT_GPG_KEY_ID:-}"
PUBLIC_KEY_PATH="${APT_PUBLIC_KEY_PATH:-}"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--sign)
			SIGN_KEY_ID="${2:-}"
			shift 2
			;;
		--public-key)
			PUBLIC_KEY_PATH="${2:-}"
			shift 2
			;;
		-h|--help)
			usage
			;;
		*)
			POSITIONAL+=("$1")
			shift
			;;
	esac
done

[[ ${#POSITIONAL[@]} -ge 1 && ${#POSITIONAL[@]} -le 2 ]] || usage

DEB_PATH="$(readlink -f "${POSITIONAL[0]}")"
if [[ ${#POSITIONAL[@]} -eq 2 ]]; then
	OUT_DIR="${POSITIONAL[1]}"
fi

if [[ -n "$PUBLIC_KEY_PATH" ]]; then
	PUBLIC_KEY_PATH="$(readlink -f "$PUBLIC_KEY_PATH")"
fi

[[ -f "$DEB_PATH" ]] || {
	echo "Error: .deb not found: $DEB_PATH" >&2
	exit 1
}

command -v dpkg-scanpackages >/dev/null 2>&1 || {
	echo "Error: dpkg-scanpackages is required (install dpkg-dev)." >&2
	exit 1
}

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/pool/main" "$OUT_DIR/dists/stable/main/binary-amd64"

cp "$DEB_PATH" "$OUT_DIR/pool/main/"

pushd "$OUT_DIR" >/dev/null
dpkg-scanpackages --multiversion pool > dists/stable/main/binary-amd64/Packages
gzip -kf dists/stable/main/binary-amd64/Packages

cat > dists/stable/Release <<EOF
Origin: johnohhh1
Label: claude-desktop-ubuntu
Suite: stable
Codename: stable
Architectures: amd64
Components: main
Description: Unofficial Claude Desktop for Ubuntu apt repository
Date: $(LC_ALL=C date -Ru)
EOF

for algo in MD5Sum SHA256; do
	echo "$algo:" >> dists/stable/Release
	while IFS= read -r relpath; do
		if [[ "$algo" == "MD5Sum" ]]; then
			sum="$(md5sum "$relpath" | awk '{print $1}')"
		else
			sum="$(sha256sum "$relpath" | awk '{print $1}')"
		fi
		size="$(stat -c '%s' "$relpath")"
		printf " %s %16s %s\n" "$sum" "$size" "$relpath" >> dists/stable/Release
	done < <(find dists/stable -type f \( -name 'Packages' -o -name 'Packages.gz' \) | sort)
done

if [[ -n "$SIGN_KEY_ID" ]]; then
	command -v gpg >/dev/null 2>&1 || {
		echo "Error: gpg is required for signing." >&2
		exit 1
	}
	gpg --batch --yes --armor --detach-sign \
		--local-user "$SIGN_KEY_ID" \
		-o dists/stable/Release.gpg dists/stable/Release
	gpg --batch --yes --clearsign \
		--local-user "$SIGN_KEY_ID" \
		-o dists/stable/InRelease dists/stable/Release
fi

if [[ -n "$PUBLIC_KEY_PATH" ]]; then
	[[ -f "$PUBLIC_KEY_PATH" ]] || {
		echo "Error: public key not found: $PUBLIC_KEY_PATH" >&2
		exit 1
	}
	cp "$PUBLIC_KEY_PATH" claude-desktop-archive-keyring.gpg
fi

touch .nojekyll
popd >/dev/null

echo "APT repository written to: $OUT_DIR"
