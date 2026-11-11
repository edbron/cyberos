# CyberOS default file manager + transfer mechanism: fim + filetransferd

**Status:** Approved · **Date:** 2026-09-26

## Why

CyberOS's "Files" app is a 321-line QML surface (`Files.qml`) with no copy/move
daemon behind it. Two already-built, already-tested projects replace it:

- `tui-file-manager` (`fim`): a Rust TUI file manager, Arch-native, themed from
  the same live theme file CyberOS's Quickshell writes.
- `file-transfer` (`filetransferd` / `ftctl`): a standalone systemd `--user`
  daemon that survives a crashing file manager, with a Quickshell bar chip.

`fim` delegates all copy/move/paste to `ftctl`, so the two ship together.
After this change, CyberOS ships no GTK file manager and no other transfer
tool; `fim` + `ftctl` are the only ones baked into the image. A user may
`pacman -S` a different one after install — that's explicitly out of scope
to prevent.

## Components

1. **`fim` package** — built from the PKGBUILD already in `tui-file-manager/`,
   added to the custom package set the way other locally-built packages are
   (see `aur/packages.txt` pattern), then listed in `profile/packages.x86_64`.
2. **`filetransferd` + `ftctl`** — vendor `daemon/filetransferd.py` and
   `daemon/ftctl.py` into `profile/airootfs/usr/local/bin/`, executable,
   invoked by absolute path per this repo's "no shell, no `$PATH` search"
   convention. `rsync` and `python3` added to `packages.x86_64` if not
   already present (`python3` is; `rsync` is not — added).
3. **systemd `--user` unit** — render `systemd/filetransferd.service.in`
   into `profile/airootfs/etc/systemd/user/filetransferd.service`, enabled
   for all users at build time via a symlink under
   `profile/airootfs/etc/systemd/user/default.target.wants/`, the user-unit
   equivalent of how `power-profiles-daemon.service` etc. are enabled under
   `multi-user.target.wants/`.
4. **Launcher wiring** — delete `Files.qml`, `cyberos-files`,
   `cyberos-files.desktop`. Add `cyberos-fim` wrapper script
   (`exec foot -- fim "${1:-$HOME}"`) and `cyberos-fim.desktop`
   (`MimeType=inode/directory;`, `Categories=System;FileManager;`). Update
   `Launcher.qml`'s Files entry to call the new script. Add a Hyprland
   float/window rule for the fim terminal window, matching the existing
   `float-cloud-drives` pattern, so it opens as a floating window rather than
   tiling.
5. **Transfer bar chip** — vendor `Panel.qml`, `Service.qml`, `Model.js`,
   `TransferIcon.qml` from `file-transfer/` into
   `profile/airootfs/etc/skel/.config/quickshell/bar/` and `.../popups/`,
   registered in the bar's chip list next to Cloud Drives / Monitor Arrange,
   on by default. Any filename/path text it renders goes through
   `Text.PlainText` per `tests/quickshell.bats`'s existing guard, since a
   transferred filename is data this desktop does not control.
6. **`zenity`** — file-transfer's `integration/send-to-transfer-manager.sh`
   is for GTK file managers (Nautilus/Thunar "send to" actions) CyberOS
   doesn't ship. Not vendored; `fim` already calls `ftctl` directly.
7. **Tests** (`tests/`, bats) — add assertions:
   - `fim` is the registered `inode/directory` handler (desktop file present,
     `Files.qml`/`cyberos-files` absent).
   - `filetransferd.service` is enabled by default (symlink present).
   - No other file-manager package (`nautilus`, `thunar`, `pcmanfm`, `nnn`,
     `ranger`) appears in `profile/packages.x86_64` or the custom package
     list — regression guard for "only" per user's requirement, without a
     runtime enforcement mechanism (a user may still install one after boot).
   - New bar chip's transfer filename text uses `Text.PlainText`
     (extends `tests/quickshell.bats`).
8. **Docs** — update `docs/SPEC.md`'s app list (Files/Images/Mixer →
   Files is now `fim`+`ftctl`, not QML), `CHANGELOG.md`, `README.md` where
   they enumerate desktop apps.
9. **`STATUS.md` / `REPORT.md`** — add both to `.gitignore` (untracked).
   `STATUS.md` is written by this session at the end of implementation, and
   states explicitly for Antigravity: run `./build.sh`, then `./test-vm.sh`,
   do live testing of `fim` (open, navigate, copy/move/paste, delete, theme)
   and the transfer bar chip in the CyberOS VM, write results into
   `REPORT.md`, and follow this repo's `CLAUDE.md`/`CONTRIBUTING.md`
   conventions (no AI co-author trailers, no em dash, `area: summary` commit
   style) for anything it commits.

## Out of scope

- Any runtime/install-time block preventing a user from installing another
  file manager after the fact.
- Porting `fim`'s own `install.sh`/`update.sh`/`uninstall.sh` logic — the ISO
  bakes the binary in directly; those scripts are for a standalone Arch
  install and stay in their own repos, unused by CyberOS's build.
- Any change to how `cyberos-cloud-drives` or `cyberos-monitor-arrange` work.

## Testing

`bats tests/` must pass. `./build.sh` then `./test-vm.sh` is required before
claiming this works, per this repo's standing rule that a green unit suite
does not verify an installer/boot-path change — delegated to Antigravity via
`STATUS.md` as described above.
