# fim + filetransferd as default file manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `fim` (Rust TUI file manager) + `filetransferd`/`ftctl` the only
file manager and transfer mechanism CyberOS ships, replacing the QML
`Files.qml` app, built into the ISO at build time.

**Architecture:** `fim` ships as a locally-built pacman package (its own
PKGBUILD, built the way `pixie-sddm-git`/`aether` already are). `filetransferd`
+ `ftctl` are vendored Python scripts under `/usr/local/bin`, matching how
`cyberos-cloud-drives` is vendored, backed by a systemd `--user` unit enabled
by default. A thin `cyberos-fim` wrapper opens `fim` in a floating `foot`
window, replacing `cyberos-files`. A Quickshell bar chip (vendored QML) shows
live transfer status.

**Tech Stack:** Bash (wrapper scripts, PKGBUILD, packages.x86_64), Python 3
(filetransferd/ftctl, unmodified from source repo), QML (Quickshell bar chip),
bats (tests).

**Spec:** `docs/superpowers/specs/2026-09-26-fim-file-manager-design.md`

## Global Constraints

- No `Co-Authored-By`/`Claude-Session` commit trailers; no em dash anywhere
  (commits, code, comments, docs).
- Commit subject: `area: imperative lower-case summary`, no trailing period,
  under ~70 chars.
- Never edit `profile/pacman.conf` (generated); never commit `work/`, `out/`,
  `repo/`, `aur/*.deb`.
- Every external tool call is an explicit argument list to a resolved
  absolute path or known binary name, never shell string concatenation or
  `shell=True`-equivalent.
- Text rendered from data this desktop does not control (filenames, paths)
  must be `textFormat: Text.PlainText` in any new QML.
- `bats tests/` must pass before any step is called done. `./build.sh` then
  `./test-vm.sh` are required to verify the ISO itself; STATUS.md hands that
  off to Antigravity, per repo convention that a green unit suite does not
  verify a boot-path/installer change.

## Review Focus

- A user opens `fim` from the launcher with `$HOME` not yet existing on a
  fresh install (edge case: wrapper must not crash if `$1` is empty; default
  to `$HOME`).
- `filetransferd.service` fails to start (missing `rsync`) — the bar chip
  must show "Daemon unreachable", not crash the panel; covered by existing
  `Service.qml` polling logic, verified by a bats assertion that `rsync` is
  actually in `packages.x86_64` (its absence is exactly this failure).
- Two file-manager desktop entries both claim `inode/directory` (packaged
  `fim.desktop` from the PKGBUILD *and* our own `cyberos-fim.desktop`) —
  must resolve to exactly one visible entry, tested by a bats assertion.
- `cyberos-cloud-drives`'s `cmd_open`/`window_for` matches windows by
  `title == basename($dir)` — the `cyberos-fim` wrapper must set that same
  `foot --title` or cloud-drives' "reuse existing window" focus logic
  silently breaks (window never found, always opens a new one).
- Old `Files.qml`/`cyberos-files` references left dangling anywhere
  (Launcher.qml, docs, tests) after removal — a stale reference is a broken
  desktop, not just a doc error; searched for explicitly in Task 5.

---

### Task 1: Vendor the `fim` package

**Files:**
- Create: `aur/fim/PKGBUILD` (copy of `/home/le_4rchitect/Work/tui-file-manager/PKGBUILD`, unmodified)
- Modify: `aur/packages.txt` — add `fim` to the list
- Modify: `profile/packages.x86_64` — add `fim` under a new `# ---- file manager / transfer ----` section, replacing the existing `# removable-drive mounting for the QML file manager` comment on `udisks2` with `# removable-drive mounting for fim's DEVICES sidebar`
- Test: `tests/packages.bats` (create if it doesn't exist; check first)

**Interfaces:**
- Produces: `fim` binary at `/usr/bin/fim` once built; `/usr/share/applications/fim.desktop` (packaged, `Exec=fim Terminal=true`) — Task 3 adds CyberOS's own entry that takes precedence.

- [ ] **Step 1: Check for an existing packages test file**

Run: `ls tests/*.bats | grep -i packag`

If one exists, read it to match its style before writing Step 2's test.

- [ ] **Step 2: Write the failing test**

Add to `tests/packages.bats` (create with a `bats` header matching
`tests/quickshell.bats`'s style if the file doesn't exist):

```bash
@test "fim is listed as a package" {
  grep -qx "fim" profile/packages.x86_64
}

@test "fim has a local PKGBUILD" {
  [ -f aur/fim/PKGBUILD ]
}

@test "fim is registered for local build" {
  grep -qx "fim" aur/packages.txt
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bats tests/packages.bats`
Expected: FAIL (file/lines don't exist yet)

- [ ] **Step 4: Copy the PKGBUILD and register the package**

```bash
mkdir -p aur/fim
cp /home/le_4rchitect/Work/tui-file-manager/PKGBUILD aur/fim/PKGBUILD
```

Add `fim` as a new line at the end of `aur/packages.txt`.

Add to `profile/packages.x86_64`, right after the existing `# ---- apps ----`
section's `trash-cli` line:

```
# ---- file manager / transfer ----
fim
rsync
```

(`rsync` is filetransferd's dependency, added here since it lands with the
same feature; `python3` is already present in the base package set.)

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/packages.bats`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add aur/fim/PKGBUILD aur/packages.txt profile/packages.x86_64 tests/packages.bats
git commit -m "packages: add fim as the default file manager"
```

---

### Task 2: Vendor filetransferd + ftctl, enable the systemd --user unit

**Files:**
- Create: `profile/airootfs/usr/local/bin/filetransferd` (copy of `daemon/filetransferd.py`, made executable, shebang `#!/usr/bin/env python3` preserved as-is from source)
- Create: `profile/airootfs/usr/local/bin/ftctl` (copy of `daemon/ftctl.py`, executable)
- Create: `profile/airootfs/etc/systemd/user/filetransferd.service` (rendered from `systemd/filetransferd.service.in`, `__EXEC_PATH__` replaced with `/usr/local/bin/filetransferd`)
- Create: `profile/airootfs/etc/systemd/user/default.target.wants/filetransferd.service` (symlink to `../filetransferd.service`, the user-unit equivalent of how `power-profiles-daemon.service` is enabled under `multi-user.target.wants/`)
- Test: `tests/packages.bats`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `/usr/local/bin/ftctl` — the CLI `fim` (Task 3) shells out to for copy/move/paste; `filetransferd.service` — polled by the bar chip (Task 4).

- [ ] **Step 1: Write the failing test**

Add to `tests/packages.bats`:

```bash
@test "filetransferd is enabled as a default user unit" {
  [ -L profile/airootfs/etc/systemd/user/default.target.wants/filetransferd.service ]
}

@test "ftctl and filetransferd binaries are vendored" {
  [ -x profile/airootfs/usr/local/bin/filetransferd ]
  [ -x profile/airootfs/usr/local/bin/ftctl ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/packages.bats`
Expected: FAIL on the two new assertions

- [ ] **Step 3: Vendor the daemon, CLI, and unit**

```bash
cp /home/le_4rchitect/Work/file-transfer/daemon/filetransferd.py \
   profile/airootfs/usr/local/bin/filetransferd
cp /home/le_4rchitect/Work/file-transfer/daemon/ftctl.py \
   profile/airootfs/usr/local/bin/ftctl
chmod 755 profile/airootfs/usr/local/bin/filetransferd profile/airootfs/usr/local/bin/ftctl

mkdir -p profile/airootfs/etc/systemd/user/default.target.wants
sed 's#__EXEC_PATH__#/usr/local/bin/filetransferd#' \
  /home/le_4rchitect/Work/file-transfer/systemd/filetransferd.service.in \
  > profile/airootfs/etc/systemd/user/filetransferd.service
ln -s ../filetransferd.service \
  profile/airootfs/etc/systemd/user/default.target.wants/filetransferd.service
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/packages.bats`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add profile/airootfs/usr/local/bin/filetransferd \
        profile/airootfs/usr/local/bin/ftctl \
        profile/airootfs/etc/systemd/user/filetransferd.service \
        profile/airootfs/etc/systemd/user/default.target.wants/filetransferd.service \
        tests/packages.bats
git commit -m "transfer: vendor filetransferd/ftctl, enable by default"
```

---

### Task 3: Replace Files.qml/cyberos-files with cyberos-fim

**Files:**
- Delete: `profile/airootfs/etc/skel/.config/quickshell/apps/Files.qml`
- Delete: `profile/airootfs/usr/local/bin/cyberos-files`
- Delete: `profile/airootfs/usr/local/share/applications/cyberos-files.desktop`
- Create: `profile/airootfs/usr/local/bin/cyberos-fim`
- Create: `profile/airootfs/usr/local/share/applications/cyberos-fim.desktop`
- Modify: `profile/airootfs/etc/skel/.config/hypr/hyprland.lua` — window rule
- Modify: `profile/airootfs/etc/skel/.config/quickshell/launcher/Launcher.qml` — remove `Files.qml`/`qs ipc call files` reference if present
- Test: `tests/quickshell.bats`

**Interfaces:**
- Consumes: `ftctl`/`fim` from Tasks 1-2 (referenced only by name in docs/desktop file, not called directly by this task's code).
- Produces: `cyberos-fim` — the one registered `inode/directory` handler; window class `cyberos-fim` that `hyprland.lua`'s window rule floats, and whose `--title` matches `cyberos-cloud-drives`'s `window_for()` expectation (title == the opened directory's basename).

- [ ] **Step 1: Check for Files.qml/cyberos-files references before deleting**

Run: `grep -rn "Files\.qml\|cyberos-files" profile/ docs/ tests/ | grep -v "^Binary"`

Note every hit; each one gets updated or removed in this task's later steps.

- [ ] **Step 2: Write the failing test**

Add to `tests/quickshell.bats`:

```bash
@test "fim is the only registered file manager" {
  [ ! -f profile/airootfs/etc/skel/.config/quickshell/apps/Files.qml ]
  [ ! -f profile/airootfs/usr/local/bin/cyberos-files ]
  [ -x profile/airootfs/usr/local/bin/cyberos-fim ]
  [ -f profile/airootfs/usr/local/share/applications/cyberos-fim.desktop ]
  grep -q "inode/directory" profile/airootfs/usr/local/share/applications/cyberos-fim.desktop
}

@test "no other file manager package is shipped" {
  ! grep -Eq "^(nautilus|thunar|pcmanfm|nnn|ranger)$" profile/packages.x86_64
  ! grep -Eq "^(nautilus|thunar|pcmanfm|nnn|ranger)$" aur/packages.txt
}

@test "cyberos-fim sets a title cloud-drives' window matching expects" {
  grep -q -- '--title' profile/airootfs/usr/local/bin/cyberos-fim
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bats tests/quickshell.bats`
Expected: FAIL

- [ ] **Step 4: Delete the QML app and old wrapper/desktop file**

```bash
rm profile/airootfs/etc/skel/.config/quickshell/apps/Files.qml
rm profile/airootfs/usr/local/bin/cyberos-files
rm profile/airootfs/usr/local/share/applications/cyberos-files.desktop
```

- [ ] **Step 5: Write the cyberos-fim wrapper**

Create `profile/airootfs/usr/local/bin/cyberos-fim`:

```sh
#!/bin/sh
# Opens fim in a floating foot window. Title is set to the target
# directory's basename so cyberos-cloud-drives' window_for() (which matches
# on title == remote name) keeps finding and reusing this window -- see
# cyberos-cloud-drives' cmd_open().
dir="${1:-$HOME}"
title="$(basename "$dir")"
exec foot --app-id=cyberos-fim --title="$title" -- fim "$dir"
```

```bash
chmod 755 profile/airootfs/usr/local/bin/cyberos-fim
```

- [ ] **Step 6: Write the desktop entry**

Create `profile/airootfs/usr/local/share/applications/cyberos-fim.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Files
Comment=Browse your files
Exec=cyberos-fim %f
Icon=system-file-manager
Terminal=false
Categories=System;FileManager;
MimeType=inode/directory;
Keywords=files;folder;browser;manager;
```

- [ ] **Step 7: Add the Hyprland float rule**

In `profile/airootfs/etc/skel/.config/hypr/hyprland.lua`, add next to the
existing `float-cloud-drives` rule (around line 198):

```lua
hl.window_rule({ name = "float-fim", match = { class = "^(cyberos-fim)$" }, float = true, size = { 1000, 640 }, center = true })
```

- [ ] **Step 8: Fix any remaining Files.qml/cyberos-files references found in Step 1**

For each hit from Step 1 (expected: `Launcher.qml`'s categories list at line
~185 already handles any `FileManager`-categorized `.desktop` generically, so
it likely needs no change — verify by re-running the Step 1 grep and
confirming remaining hits are only in this task's own new files or in
historical `CHANGELOG.md`/docs entries, which are left as history).

- [ ] **Step 9: Run tests to verify they pass**

Run: `bats tests/quickshell.bats`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add -A profile/airootfs/etc/skel/.config/quickshell/apps/Files.qml \
           profile/airootfs/usr/local/bin/cyberos-files \
           profile/airootfs/usr/local/bin/cyberos-fim \
           profile/airootfs/usr/local/share/applications/cyberos-files.desktop \
           profile/airootfs/usr/local/share/applications/cyberos-fim.desktop \
           profile/airootfs/etc/skel/.config/hypr/hyprland.lua \
           tests/quickshell.bats
git commit -m "files: replace Files.qml with fim as the default file manager"
```

---

### Task 4: Vendor the transfer bar chip

**Files:**
- Create: `profile/airootfs/etc/skel/.config/quickshell/bar/TransferIcon.qml` (copy of `file-transfer/TransferIcon.qml`)
- Create: `profile/airootfs/etc/skel/.config/quickshell/popups/Transfer.qml` (renamed from `file-transfer/Panel.qml`, matching this repo's popup-naming convention seen in `CloudDrives.qml`)
- Create: `profile/airootfs/etc/skel/.config/quickshell/popups/TransferService.qml` (from `file-transfer/Service.qml`)
- Create: `profile/airootfs/etc/skel/.config/quickshell/popups/TransferModel.js` (from `file-transfer/Model.js`)
- Modify: whichever bar file registers chips (find it: `grep -rl "CloudDrives\|cloud-drives" profile/airootfs/etc/skel/.config/quickshell/bar/`) — register the transfer chip next to Cloud Drives, on by default
- Test: `tests/quickshell.bats`

**Interfaces:**
- Consumes: `ftctl` (Task 2) — `TransferService.qml`'s poll command, update from `["ftctl", ...]` if the source used a different invocation (source project called it via its own daemon's CLI name, confirm it's literally `ftctl` in `Service.qml`; if not, update the copied file's command list to `ftctl`, matching how `filetransferd.py`/`ftctl.py` are installed to `/usr/local/bin` in Task 2).
- Produces: bar chip visible by default; no other task depends on this one's output.

- [ ] **Step 1: Find the bar registration file**

Run: `grep -rl "CloudDrives" profile/airootfs/etc/skel/.config/quickshell/bar/`

Read the matched file's Cloud Drives chip registration block to copy its
shape exactly (icon component, popup component, always-visible flag).

- [ ] **Step 2: Write the failing test**

Add to `tests/quickshell.bats`:

```bash
@test "transfer bar chip is vendored and registered by default" {
  [ -f profile/airootfs/etc/skel/.config/quickshell/bar/TransferIcon.qml ]
  [ -f profile/airootfs/etc/skel/.config/quickshell/popups/Transfer.qml ]
  grep -rq "TransferIcon" profile/airootfs/etc/skel/.config/quickshell/bar/*.qml
}

@test "transfer chip renders filenames as plain text" {
  grep -q "Text.PlainText" profile/airootfs/etc/skel/.config/quickshell/popups/Transfer.qml
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bats tests/quickshell.bats`
Expected: FAIL

- [ ] **Step 4: Copy and rename the QML files**

```bash
cp /home/le_4rchitect/Work/file-transfer/TransferIcon.qml \
   profile/airootfs/etc/skel/.config/quickshell/bar/TransferIcon.qml
cp /home/le_4rchitect/Work/file-transfer/Panel.qml \
   profile/airootfs/etc/skel/.config/quickshell/popups/Transfer.qml
cp /home/le_4rchitect/Work/file-transfer/Service.qml \
   profile/airootfs/etc/skel/.config/quickshell/popups/TransferService.qml
cp /home/le_4rchitect/Work/file-transfer/Model.js \
   profile/airootfs/etc/skel/.config/quickshell/popups/TransferModel.js
```

Edit the copied `Transfer.qml`/`TransferService.qml`/`TransferModel.js` for
any relative import paths that referenced the old sibling filenames
(`Service.qml`, `Model.js`, `TransferIcon.qml`) and update them to the new
names above.

Edit `Transfer.qml`: any `Text { text: <filename-derived value> }` element
must set `textFormat: Text.PlainText` (per this repo's convention for
untrusted rendered strings, guarded by `tests/quickshell.bats`).

- [ ] **Step 5: Register the chip in the bar**

In the file found in Step 1, add the transfer chip's registration using the
exact same shape as the Cloud Drives registration found there (component
reference, always-on, right section) — no separate opt-in flag, matching
Cloud Drives and Monitor Arrange's own on-by-default pattern.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats tests/quickshell.bats`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add profile/airootfs/etc/skel/.config/quickshell/bar/TransferIcon.qml \
        profile/airootfs/etc/skel/.config/quickshell/popups/Transfer.qml \
        profile/airootfs/etc/skel/.config/quickshell/popups/TransferService.qml \
        profile/airootfs/etc/skel/.config/quickshell/popups/TransferModel.js \
        tests/quickshell.bats
git commit -m "bar: add transfer queue chip, on by default"
```

(Also `git add` the bar-registration file modified in Step 5.)

---

### Task 5: Docs, changelog, and STATUS.md/REPORT.md handoff

**Files:**
- Modify: `docs/SPEC.md` — update the app list section (search for "Files/Images/Mixer" or similar QML-surfaces line)
- Modify: `CHANGELOG.md` — add entry under `[Unreleased]` (check existing header style first)
- Modify: `README.md` — update anywhere it lists the desktop's default apps
- Modify: `.gitignore` — add `STATUS.md` and `REPORT.md`
- Create: `STATUS.md` (untracked; last step, after everything above is committed)

**Interfaces:**
- Consumes: nothing new; summarizes Tasks 1-4.
- Produces: `STATUS.md` for Antigravity to read and act on.

- [ ] **Step 1: Update docs/SPEC.md**

Find and update the section describing Files/Images/Mixer as QML surfaces
(seen during exploration: "Files/Images/Mixer are Quickshell QML surfaces
now, so the only GUI apps on the ISO are the two that no QML surface can
replace" in `profile/packages.x86_64`'s comments, and any equivalent
sentence in `docs/SPEC.md`). Replace "Files" references with: "Files is
`fim`, a TUI file manager opened in a floating terminal, backed by the
`filetransferd`/`ftctl` transfer daemon (shown live in a bar chip); Images
and Mixer remain QML surfaces."

- [ ] **Step 2: Update CHANGELOG.md**

Read the top of `CHANGELOG.md` to match its exact `[Unreleased]`/heading
style, then add:

```markdown
### Added
- `fim` (TUI file manager) and `filetransferd`/`ftctl` (transfer daemon)
  as the default and only file manager / transfer mechanism, replacing
  the QML Files app. Live transfer status shown in a new bar chip.
```

- [ ] **Step 3: Update README.md if it lists default apps**

Run: `grep -n "Files\|file manager" README.md`

If it names the QML Files app as a feature, update the wording to describe
`fim` instead, in the same sentence style as the surrounding list.

- [ ] **Step 4: Add STATUS.md and REPORT.md to .gitignore**

Append to `.gitignore`:

```
STATUS.md
REPORT.md
```

- [ ] **Step 5: Run the full test suite**

Run: `bats tests/`
Expected: all PASS

- [ ] **Step 6: Commit the docs and gitignore changes**

```bash
git add docs/SPEC.md CHANGELOG.md README.md .gitignore
git commit -m "docs: update for fim as the default file manager"
```

- [ ] **Step 7: Write STATUS.md (untracked, last step)**

Create `STATUS.md` at the repo root:

```markdown
# Status: fim + filetransferd as default file manager

Implemented on branch `<branch name>`, commits: `<git log --oneline -8>`.

## What changed
- `fim` (TUI file manager) added as a locally-built package
  (`aur/fim/PKGBUILD`), the only file manager shipped.
- `filetransferd`/`ftctl` vendored to `/usr/local/bin`, systemd `--user`
  unit enabled by default.
- `cyberos-fim` wrapper + desktop entry replace `Files.qml`/`cyberos-files`
  as the registered `inode/directory` handler.
- A new bar chip shows live transfer status, on by default next to Cloud
  Drives and Monitor Arrange.
- `bats tests/` passes (see `tests/packages.bats`, `tests/quickshell.bats`).

## What Antigravity needs to do
1. `./build.sh` — builds the ISO. Needs sudo and several GB of scratch
   space in `work/`. If it fails, write the failure into `REPORT.md`
   verbatim (stdout/stderr) and stop; do not silently retry with modified
   flags.
2. `./test-vm.sh` — boots the newest `out/*.iso` in QEMU.
3. In the booted VM, live-test:
   - Opening Files from the app launcher opens a floating `fim` window.
   - Navigate, copy, move, paste, delete a file with `fim` (keys documented
     in `tui-file-manager`'s README: `c`/`x`/`p`, `d`, `D`).
   - The transfer bar chip shows the copy/move in progress and updates to
     idle when done.
   - Cloud Drives' "open" action (if a cloud drive is configured) still
     reuses/focuses the existing `fim` window rather than opening a
     duplicate.
   - No other file manager or transfer tool is present anywhere on the
     installed system.
4. Write everything observed, pass or fail, into `REPORT.md` (also
   untracked; do not commit it). Structure: what was tested, what happened,
   pass/fail per item above, and any unexpected behavior.
5. Follow this repo's conventions for anything committed: read
   `CLAUDE.md` and `CONTRIBUTING.md` first. In particular: no
   `Co-Authored-By`/`Claude-Session` trailers, no em dash anywhere, commit
   subject style `area: imperative lower-case summary`.
```

This step is not a git commit — `STATUS.md` and `REPORT.md` are untracked
per Step 4.
