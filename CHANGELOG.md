# Changelog

All notable changes to CyberOS are documented in this file, starting from this
file's introduction. Earlier history is in `git log`, not backfilled here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows CyberOS's own scheme (`docs/SPEC.md` §4.6): `vYYYY.MM` for a
stable snapshot, `build-NN` for an engineering build, `YYYY.MM.DD` as the ISO's
own build metadata — not SemVer.

## [Unreleased]

### Security

- Fixed a shell injection in `cyberos-install`'s chroot handoff: an unquoted
  heredoc let a crafted `--user`/`--password`/`--root-password` value (a
  quote, backtick, or `$(...)`) run as arbitrary shell code, as root, inside
  `arch-chroot`. Tainted values now cross into the chroot via `env` instead
  of host-side text interpolation.
- Added `--user` character-set validation and an 8-character minimum for
  `--encrypt` passphrases to the CLI installer path (the GUI already
  enforced both); `--password` (argv) now warns that `--password-stdin` is
  safer.
- Quickshell bar chips that render text this desktop does not control
  (MPRIS track metadata, a window's own title) now render as plain text
  instead of Qt's default auto-detected rich text, closing a markup
  injection into the system bar.
- Added `--hostname` character-set validation to `cyberos-install` (the
  interactive and unattended paths both now require a single letters/
  digits/`-` hostname label, same defense-in-depth reasoning as the
  existing `--user` check): an unrestricted hostname could otherwise carry
  a newline into `/etc/hosts` or raw escape sequences into the installer's
  own ANSI summary box.

### Fixed

- Removed the dead `firewall_rules()` helper from `cyberos-install`: it was
  never called (the actual `ufw` enablement runs from `cyberos-firstboot`,
  since `ufw` needs a running kernel that isn't available inside the
  installer's chroot), and `tests/security.bats`'s firewall tests were
  checking that unused function's string output instead of the real code
  path, which meant they didn't actually catch a regression in what an
  installed machine boots with. The tests now grep `cyberos-firstboot`.

### Added

- `cyberos-arch-audit.timer`/`.service`: a weekly `arch-audit` run on
  installed systems, reporting known CVEs in installed packages against
  the pinned channel to the journal (`docs/SPEC.md` S4). Enabled by the
  installer alongside NetworkManager/sddm/bluetooth/cyberos-firstboot.

### Changed

- `build.sh` now asks (once the ISO is built) whether to delete `work/` --
  the AUR build trees and mkarchiso's scratch dir, which can run several GB
  and were previously left on disk indefinitely. `--keep-work`/`--purge-work`
  skip the prompt for non-interactive use; `repo/` and `out/` are untouched
  either way.
- `.gitignore` now excludes locally-built ISOs and screenshots.
- `docs/SPEC.md` §7.2's requirement table now tracks implementation status
  per item (S1-S6), instead of leaving "is this actually done" unanswered.
- Caught up `docs/branches/` to actual merge history: several charters
  still said "planned"/"open" for branches merged weeks ago, two merged
  branches had no table row at all, and `main.md` flagged an already-fixed
  bug as outstanding.
