#!/usr/bin/env bash
# Common launcher functions for Claude Desktop (AppImage and deb)
# This file is sourced by both launchers to avoid code duplication

# Setup logging directory and file
# Sets: log_dir, log_file
setup_logging() {
	log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-debian"
	mkdir -p "$log_dir" || return 1
	log_file="$log_dir/launcher.log"
}

# Log a message to the log file
log_message() {
	echo "$1" >> "$log_file"
}

# Detect display backend (Wayland vs X11)
# Sets: is_wayland, use_x11_on_wayland
detect_display_backend() {
	is_wayland=false
	[[ -n "${WAYLAND_DISPLAY:-}" ]] && is_wayland=true

	use_x11_on_wayland=true
	[[ "${CLAUDE_USE_WAYLAND:-}" == '1' ]] && use_x11_on_wayland=false

	# Auto-detect compositors that require native Wayland
	# Only Niri is auto-forced: it has no XWayland support.
	if [[ $is_wayland == true && $use_x11_on_wayland == true ]]; then
		local desktop="${XDG_CURRENT_DESKTOP:-}"
		desktop="${desktop,,}"

		if [[ -n "${NIRI_SOCKET:-}" || "$desktop" == *niri* ]]; then
			log_message "Niri detected - forcing native Wayland"
			use_x11_on_wayland=false
		fi
	fi
}

# Check if we have a valid display (not running from TTY)
check_display() {
	[[ -n $DISPLAY || -n $WAYLAND_DISPLAY ]]
}

# Build Electron arguments array based on display backend
# Arguments: $1 = "appimage" or "deb"
build_electron_args() {
	local package_type="${1:-deb}"
	electron_args=()

	[[ $package_type == 'appimage' ]] && electron_args+=('--no-sandbox')
	electron_args+=('--disable-features=CustomTitlebar')

	if [[ $is_wayland != true ]]; then
		log_message 'X11 session detected'
		return
	fi

	[[ $package_type == 'deb' || $package_type == 'nix' ]] \
		&& electron_args+=('--no-sandbox')

	if [[ $use_x11_on_wayland == true ]]; then
		log_message 'Using X11 backend via XWayland (for global hotkey support)'
		electron_args+=('--ozone-platform=x11')
	else
		log_message 'Using native Wayland backend (global hotkeys may not work)'
		electron_args+=('--enable-features=UseOzonePlatform,WaylandWindowDecorations')
		electron_args+=('--ozone-platform=wayland')
		electron_args+=('--enable-wayland-ime')
		electron_args+=('--wayland-text-input-version=3')
	fi
}

# Kill orphaned cowork-vm-service daemon processes
cleanup_orphaned_cowork_daemon() {
	local cowork_pids
	cowork_pids=$(pgrep -f 'cowork-vm-service\.js' 2>/dev/null) \
		|| return 0

	local pid cmdline
	for pid in $(pgrep -f 'claude-desktop' 2>/dev/null); do
		cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) \
			|| continue
		[[ $cmdline == *cowork-vm-service* ]] && continue
		return 0
	done

	for pid in $cowork_pids; do
		kill "$pid" 2>/dev/null || true
	done
	log_message "Killed orphaned cowork-vm-service daemon (PIDs: $cowork_pids)"
}

# Clean up stale SingletonLock
cleanup_stale_lock() {
	local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Claude"
	local lock_file="$config_dir/SingletonLock"

	[[ -L $lock_file ]] || return 0

	local lock_target
	lock_target="$(readlink "$lock_file" 2>/dev/null)" || return 0
	local lock_pid="${lock_target##*-}"
	[[ $lock_pid =~ ^[0-9]+$ ]] || return 0

	if kill -0 "$lock_pid" 2>/dev/null; then
		return 0
	fi

	rm -f "$lock_file"
	log_message "Removed stale SingletonLock (PID $lock_pid no longer running)"
}

# Clean up stale cowork-vm-service socket
cleanup_stale_cowork_socket() {
	local sock="${XDG_RUNTIME_DIR:-/tmp}/cowork-vm-service.sock"
	[[ -S $sock ]] || return 0

	if command -v socat &>/dev/null; then
		if socat -u OPEN:/dev/null UNIX-CONNECT:"$sock" 2>/dev/null; then
			return 0
		fi
	else
		if [[ -z $(find "$sock" -mmin +1440 2>/dev/null) ]]; then
			return 0
		fi
		log_message "No socat available; removing old socket (>24h)"
	fi

	rm -f "$sock"
	log_message "Removed stale cowork-vm-service socket"
}

# Set common environment variables
setup_electron_env() {
	local package_type="${1:-deb}"
	if [[ $package_type != 'nix' ]]; then
		export ELECTRON_FORCE_IS_PACKAGED=true
	fi
	export ELECTRON_USE_SYSTEM_TITLE_BAR=1
}

#===============================================================================
# Doctor Diagnostics
#===============================================================================

_doctor_colors() {
	if [[ -t 1 ]]; then
		_green='\033[0;32m' _red='\033[0;31m' _yellow='\033[0;33m'
		_bold='\033[1m' _reset='\033[0m'
	else
		_green='' _red='' _yellow='' _bold='' _reset=''
	fi
}

_cowork_distro_id() {
	local id='unknown'
	if [[ -f /etc/os-release ]]; then
		local line
		while IFS= read -r line; do
			if [[ $line == ID=* ]]; then
				id="${line#ID=}"
				id="${id//\"/}"
				break
			fi
		done < /etc/os-release
	fi
	printf '%s' "$id"
}

_cowork_pkg_hint() {
	local distro="$1" tool="$2" pkg_cmd
	case "$distro" in
		debian|ubuntu) pkg_cmd='sudo apt install' ;;
		fedora)        pkg_cmd='sudo dnf install' ;;
		arch)          pkg_cmd='sudo pacman -S' ;;
		*) printf '%s' "Install $tool using your package manager"; return ;;
	esac
	local pkg
	case "$tool" in
		qemu)
			case "$distro" in
				debian|ubuntu) pkg='qemu-system-x86 qemu-utils' ;;
				fedora)        pkg='qemu-kvm qemu-img' ;;
				arch)          pkg='qemu-full' ;;
			esac ;;
		*) pkg="$tool" ;;
	esac
	printf '%s' "$pkg_cmd $pkg"
}

_pass() { echo -e "${_green}[PASS]${_reset} $*"; }
_fail() { echo -e "${_red}[FAIL]${_reset} $*"; _doctor_failures=$((_doctor_failures + 1)); }
_warn() { echo -e "${_yellow}[WARN]${_reset} $*"; }
_info() { echo -e "       $*"; }

# Run all diagnostic checks — see installed launcher-common.sh for full implementation
# This is the abbreviated version; the installed package contains the complete diagnostics
run_doctor() {
	local electron_path="${1:-}"
	local _doctor_failures=0
	_doctor_colors

	echo -e "${_bold}Claude Desktop Diagnostics${_reset}"
	echo '================================'
	echo

	# Package version
	if command -v dpkg-query &>/dev/null; then
		local pkg_version
		pkg_version=$(dpkg-query -W -f='${Version}' claude-desktop 2>/dev/null) || true
		if [[ -n $pkg_version ]]; then
			_pass "Installed version: $pkg_version"
		else
			_warn 'claude-desktop not found via dpkg (AppImage?)'
		fi
	fi

	# Display server
	if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
		_pass "Display server: Wayland (WAYLAND_DISPLAY=$WAYLAND_DISPLAY)"
		_info "Desktop: ${XDG_CURRENT_DESKTOP:-unknown}"
		if [[ "${CLAUDE_USE_WAYLAND:-}" == '1' ]]; then
			_info 'Mode: native Wayland (CLAUDE_USE_WAYLAND=1)'
		else
			_info 'Mode: X11 via XWayland (default)'
		fi
	elif [[ -n "${DISPLAY:-}" ]]; then
		_pass "Display server: X11 (DISPLAY=$DISPLAY)"
	else
		_fail "No display server detected"
	fi

	# Electron binary
	if [[ -n $electron_path && -x $electron_path ]]; then
		_pass "Electron: found at $electron_path"
	else
		_fail "Electron binary not found at $electron_path"
	fi

	# SingletonLock
	local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Claude"
	local lock_file="$config_dir/SingletonLock"
	if [[ -L $lock_file ]]; then
		local lock_target lock_pid
		lock_target="$(readlink "$lock_file" 2>/dev/null)" || true
		lock_pid="${lock_target##*-}"
		if [[ $lock_pid =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
			_pass "SingletonLock: held by running process (PID $lock_pid)"
		else
			_warn "SingletonLock: stale lock found (PID $lock_pid)"
		fi
	else
		_pass 'SingletonLock: no lock file (OK)'
	fi

	# MCP config
	local mcp_config="$config_dir/claude_desktop_config.json"
	if [[ -f $mcp_config ]]; then
		if command -v python3 &>/dev/null && \
		   python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$mcp_config" 2>/dev/null; then
			_pass "MCP config: valid JSON ($mcp_config)"
		else
			_fail "MCP config: invalid JSON"
		fi
	fi

	# Node.js
	if command -v node &>/dev/null; then
		_pass "Node.js: $(node --version 2>/dev/null)"
	else
		_warn 'Node.js: not found (required for MCP servers)'
	fi

	# Cowork Mode
	echo
	echo -e "${_bold}Cowork Mode${_reset}"
	echo '----------------'

	if command -v bwrap &>/dev/null; then
		_pass 'bubblewrap: found'
	else
		_warn 'bubblewrap: not found'
	fi

	if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
		_pass 'KVM: accessible'
	elif [[ -e /dev/kvm ]]; then
		_info 'KVM: exists but not accessible'
	fi

	# Summary
	echo
	if ((_doctor_failures == 0)); then
		echo -e "${_green}${_bold}All checks passed.${_reset}"
	else
		echo -e "${_red}${_bold}${_doctor_failures} check(s) failed.${_reset}"
	fi

	return "$_doctor_failures"
}
