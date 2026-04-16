<p align="center">
  <img src="assets/nanoclaw-logo.png" alt="NanoClaw" width="400">
</p>

---
# Claude Desktop for Ubuntu Linux

[![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04%20tested-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Linux](https://img.shields.io/badge/Linux-x86__64-333333?logo=linux&logoColor=white)](https://kernel.org/)
[![Wayland](https://img.shields.io/badge/Display-Wayland%20%2F%20X11-1793D1)](#features)
[![Cowork](https://img.shields.io/badge/Cowork-Supported-8A2BE2)](#cowork-support)
[![Deb Package](https://img.shields.io/badge/Package-.deb-0A66C2)](#build)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Works%20on%20Ubuntu%20Linux-2EA44F)](#what-this-is)

**Not a wrapper. Not a web view.** This repackages the official Anthropic Windows binary — the same app Windows and macOS users get — and runs it natively on Ubuntu Linux with Wayland support, proper desktop integration, a full Linux-native `@ant/claude-native` implementation, and **Cowork mode**.

Built and tested on Ubuntu 26.04 "Noble" with kernel 7.0, RTX 5070, NVIDIA driver 580, both X11 and Wayland (via XWayland).

**Tags:** `claude-desktop` `ubuntu` `linux` `electron` `wayland` `x11` `cowork` `deb` `anthropic` `desktop-app` `msix`

## Quick Jump

- [What This Is](#what-this-is)
- [What The Build Does](#what-the-build-does)
- [Features](#features)
- [Cowork Support](#cowork-support)
- [Prerequisites](#prerequisites)
- [Build](#build)
- [Install](#install)
- [Launch](#launch)
- [Environment Variables](#environment-variables)
- [Diagnostics](#diagnostics)
- [Known Limitations](#known-limitations)
- [How It Differs From Other Linux Ports](#how-it-differs-from-other-linux-ports)
- [Related Projects](#related-projects)
- [License](#license)

## What This Is

Anthropic ships Claude Desktop for macOS and Windows. Linux gets Claude Code (terminal) but no desktop app. This project extracts the official Windows MSIX package, replaces platform-specific components with Linux equivalents, and produces a proper `.deb` package you can install, update, and uninstall like any other system package.

## What The Build Does

1. Extracts the official Claude Desktop Windows MSIX bundle
2. Pulls out the `app.asar` (the real app logic — untouched)
3. Replaces `@ant/claude-native` with a Linux stub that uses Electron's native Linux APIs
4. Integrates [claude-cowork-linux](https://github.com/johnzfitch/claude-cowork-linux) stubs for Cowork support (`@ant/claude-swift` stub + platform gate patch)
5. Adds a launcher with full Wayland/X11 detection and XWayland fallback
6. Patches Electron app metadata with `desktopName=claude-desktop.desktop` so native Wayland is identified correctly by GNOME
7. Normalizes MSIX unpacked paths such as `%40ant` to `@ant` so native modules resolve correctly on Linux
8. Adds cleanup logic for stale locks, orphaned cowork daemons, and stale sockets
9. Includes a `--doctor` diagnostic command
10. Packages everything as a proper `.deb` — `claude-desktop`

## Features

- **Wayland support** — auto-detects Wayland, falls back to X11 via XWayland for global hotkey support. Set `CLAUDE_USE_WAYLAND=1` for native Wayland mode.
- **Native Wayland desktop identity fix** — patches Electron `desktopName` so GNOME shows the correct app name and icon instead of generic `electron`.
- **Niri auto-detection** — compositor with no XWayland support is auto-forced to native Wayland.
- **Frame Fix patches** — fixes BrowserWindow frame behavior, menu bar visibility, and Linux-specific Electron quirks.
- **`@ant/claude-native` Linux stub** — replaces the Windows/macOS native module with functional Linux equivalents (progress bar, flash frame, maximize detection) instead of silent no-ops.
- **Cowork mode** — runs Cowork directly on the host, no VM needed. See [Cowork Support](#cowork-support).
- **Stale lock cleanup** — automatically removes orphaned SingletonLock files from crashes.
- **Cowork daemon management** — detects and kills orphaned `cowork-vm-service` daemons that block relaunches.
- **`--doctor` diagnostics** — run `claude-desktop --doctor` to check your environment, display server, sandbox permissions, MCP config, disk space, and Cowork readiness.
- **Desktop integration** — proper `.desktop` entry, icon set (16x16 through 256x256), and `claude://` URL scheme handler.

## Cowork Support

Cowork mode is enabled using the approach from [**johnzfitch/claude-cowork-linux**](https://github.com/johnzfitch/claude-cowork-linux). That project figured out the key insight: on Linux, you don't need the macOS Virtualization.framework VM at all — stub `@ant/claude-swift`, run Claude Code directly on the host, and translate VM paths to host paths.

This deb integrates that approach at build time:

| Step | What happens |
|:-----|:------------|
| **Swift stub** | `@ant/claude-swift` is replaced with a JavaScript stub that spawns Claude Code directly |
| **Platform patch** | The cowork platform gate is patched to return `{status: "supported"}` on Linux |
| **Path translation** | VM paths (`/sessions/...`) are translated to host paths transparently |
| **Direct execution** | Claude Code spawns on the host — no QEMU, no Hyper-V, no Virtualization.framework |
| **Sessions symlink** | `/sessions` is symlinked to `~/.config/Claude/local-agent-mode-sessions/sessions` |

Full credit to **[@johnzfitch](https://github.com/johnzfitch)** for the reverse-engineering work that made this possible. This project would not have Cowork support without [claude-cowork-linux](https://github.com/johnzfitch/claude-cowork-linux).

## Prerequisites

```bash
sudo apt-get install -y dpkg-dev nodejs npm python3 file
```

You also need a Claude Desktop Windows MSIX bundle. Obtain the official `Claude-Setup-x64.exe` or `.msix` from Anthropic's distribution.

Preferred source artifact:

- **Use a real `.msix` or `.msixbundle` whenever possible.**
- The Windows `Claude Setup.exe` bootstrapper is not the preferred input for this builder. Anthropic's newer EXE bootstrapper may download the MSIX at install time instead of embedding the full app payload.
- If you only have the bootstrapper EXE, fetch the real MSIX first or update the builder to resolve Anthropic's download endpoint.

## Build

```bash
git clone git@github.com:johnohhh1/claude-desktop-ubuntu.git
cd claude-desktop-ubuntu
./build-deb.sh --msix /path/to/Claude.msix
```

Alternative inputs supported by the script:

```bash
./build-deb.sh --msix /path/to/Claude.msixbundle
./build-deb.sh --exe /path/to/Claude-Setup-x64.exe
```

Output lands in `dist/`:
```
dist/claude-desktop_<version>_amd64.deb
```

## Install

```bash
sudo apt-get install ./dist/claude-desktop_<version>_amd64.deb
```

## Launch

```bash
claude-desktop
```

Or find "Claude" in your application launcher.

For native Wayland testing:

```bash
CLAUDE_USE_WAYLAND=1 claude-desktop
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_USE_WAYLAND` | unset | Set to `1` for native Wayland (disables global hotkeys) |
| `CLAUDE_MENU_BAR` | `auto` | `visible`, `hidden`, or `auto` (Alt toggles) |
| `COWORK_VM_BACKEND` | auto-detect | `bwrap`, `kvm`, or `host` |

## Diagnostics

```bash
claude-desktop --doctor
```

Checks: display server, Electron binary, Chrome sandbox permissions, SingletonLock state, MCP config validity, Node.js version, desktop entry, disk space, Cowork isolation backend (bubblewrap/KVM), and orphaned daemons.

## Known Limitations

- **Computer Use** — the `ComputerUseTcc` handler is not registered on Linux. Anthropic's computer use feature (screen control via Cowork) does not work. This is the same gap on all Linux builds. See [portal-use](https://github.com/johnohhh1/portal-use) for a Wayland-native MCP alternative.
- **`FileSystem.whichApplication`** — `getAppInfoForFile` is a macOS-specific API; file-association lookups will throw non-fatal errors in logs. Does not affect functionality.
- **WebGL** — may show "blocklisted" errors on NVIDIA. Non-fatal, app works normally.
- **Bootstrapper EXE input** — Anthropic's newer Windows bootstrapper may not contain the full MSIX payload, so a direct `.msix` remains the most reliable build input.

## How It Differs From Other Linux Ports

| Project | Approach |
|---------|----------|
| [**johnzfitch/claude-cowork-linux**](https://github.com/johnzfitch/claude-cowork-linux) | Original Cowork-on-Linux solution. Extracts from macOS DMG, stubs `@ant/claude-swift`, patches the asar. Standalone install with its own launcher, test suite, and bubblewrap sandboxing. |
| **This project** | MSIX-to-deb packaging with Wayland launcher, Frame Fix patches, `@ant/claude-native` Linux stub, and claude-cowork-linux's Cowork stubs integrated into a `.deb` package. |

## Related Projects

- [claude-cowork-linux](https://github.com/johnzfitch/claude-cowork-linux) — the project that made Cowork on Linux possible
- [chatgpt_desktop_ubuntu](https://github.com/johnohhh1/chatgpt_desktop_ubuntu) — same MSIX-to-deb approach for ChatGPT Desktop
- [codex-ubuntu](https://github.com/johnohhh1/codex-ubuntu) — same approach for OpenAI Codex Desktop

## License

MIT — the build tooling and Linux-specific code in this repo. The Claude Desktop app binary (`app.asar`) is Anthropic's proprietary software and is NOT included in this repository.

Cowork stubs are sourced from [claude-cowork-linux](https://github.com/johnzfitch/claude-cowork-linux) (MIT).

## Repo

[github.com/johnohhh1/claude-desktop-ubuntu](https://github.com/johnohhh1/claude-desktop-ubuntu)

Issues and PRs welcome. If a new MSIX version breaks the build, open an issue with the version string.

---
*Tested on Ubuntu 26.04 "Noble" with kernel 7.0.0, RTX 5070, NVIDIA driver 580, CUDA 13.0.*
