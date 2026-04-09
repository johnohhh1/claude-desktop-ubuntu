# Claude Desktop for Ubuntu Linux

**Not a wrapper. Not a web view.** This repackages the official Anthropic Windows binary — the same app Windows and macOS users get — and runs it natively on Ubuntu Linux with Wayland support, proper desktop integration, and a full Linux-native `@ant/claude-native` implementation.

Built and tested on Ubuntu 26.04 "Noble" with kernel 7.0, RTX 5070, NVIDIA driver 580, both X11 and Wayland (via XWayland).

## What This Is

Anthropic ships Claude Desktop for macOS and Windows. Linux gets Claude Code (terminal) but no desktop app. This project extracts the official Windows MSIX package, replaces platform-specific components with Linux equivalents, and produces a proper `.deb` package you can install, update, and uninstall like any other system package.

## What The Build Does

1. Extracts the official Claude Desktop Windows MSIX bundle
2. Pulls out the `app.asar` (the real app logic — untouched)
3. Replaces `@ant/claude-native` with a Linux stub that uses Electron's native Linux APIs
4. Adds a launcher with full Wayland/X11 detection and XWayland fallback
5. Adds cleanup logic for stale locks, orphaned cowork daemons, and stale sockets
6. Includes a `--doctor` diagnostic command
7. Packages everything as a proper `.deb` — `claude-desktop`

## Features

- **Wayland support** — auto-detects Wayland, falls back to X11 via XWayland for global hotkey support. Set `CLAUDE_USE_WAYLAND=1` for native Wayland mode.
- **Niri auto-detection** — compositor with no XWayland support is auto-forced to native Wayland.
- **Frame Fix patches** — fixes BrowserWindow frame behavior, menu bar visibility, and Linux-specific Electron quirks.
- **`@ant/claude-native` Linux stub** — replaces the Windows/macOS native module with functional Linux equivalents (progress bar, flash frame, maximize detection) instead of silent no-ops.
- **Stale lock cleanup** — automatically removes orphaned SingletonLock files from crashes.
- **Cowork daemon management** — detects and kills orphaned `cowork-vm-service` daemons that block relaunches.
- **`--doctor` diagnostics** — run `claude-desktop --doctor` to check your environment, display server, sandbox permissions, MCP config, disk space, and Cowork readiness.
- **Desktop integration** — proper `.desktop` entry, icon set (16x16 through 256x256), and `claude://` URL scheme handler.

## Prerequisites

```bash
sudo apt-get install -y dpkg-dev nodejs npm python3 file
```

You also need a Claude Desktop Windows MSIX bundle. Obtain the official `Claude-Setup-x64.exe` or `.msix` from Anthropic's distribution.

## Build

```bash
git clone git@github.com:johnohhh1/claude-desktop-ubuntu.git
cd claude-desktop-ubuntu
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

## How It Differs From Other Linux Ports

| Project | Approach |
|---------|----------|
| **johnzfitch/claude-cowork-linux** | Reverse-engineers macOS Cowork VM layer, stubs `@ant/claude-swift` |
| **This project** | Direct MSIX extraction with Linux-native `@ant/claude-native` stub, Wayland launcher, Frame Fix patches |

## Related Projects

- [chatgpt_desktop_ubuntu](https://github.com/johnohhh1/chatgpt_desktop_ubuntu) — same MSIX-to-deb approach for ChatGPT Desktop
- [codex-ubuntu](https://github.com/johnohhh1/codex-ubuntu) — same approach for OpenAI Codex Desktop

## License

MIT — the build tooling and Linux-specific code in this repo. The Claude Desktop app binary (`app.asar`) is Anthropic's proprietary software and is NOT included in this repository.

## Repo

[github.com/johnohhh1/claude-desktop-ubuntu](https://github.com/johnohhh1/claude-desktop-ubuntu)

Issues and PRs welcome. If a new MSIX version breaks the build, open an issue with the version string.

---
*Tested on Ubuntu 26.04 "Noble" with kernel 7.0.0, RTX 5070, NVIDIA driver 580, CUDA 13.0.*
