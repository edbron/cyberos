# CyberOS Technical Specification

**Status:** Draft 1 · **Date:** 2026-08-30 · **Owner:** edbron
**Applies to:** CyberOS ≥ 2026.09 · **Supersedes:** nothing (first formal spec)

CyberOS is an Arch-based Linux distribution for the Cyber Department, University of
Mines and Technology, Tarkwa. It is delivered as a live+installer ISO and maintained
as a set of pacman repositories under department control.

This document is normative. **MUST / MUST NOT / SHOULD / MAY** are used as in RFC 2119.
Anything not marked MUST is guidance.

---

## 0. Why this document exists

Up to now CyberOS has been built by hand: one person, one machine, one QEMU test cell
(UEFI × virtual disk). That is fine for a prototype and unacceptable for something a
department of students installs on hardware we do not own. Every mainstream distribution
solves this with the same three things, and this spec adopts all three:

| Practice | Who does it | What it buys |
|---|---|---|
| Published **release criteria** + a test matrix that gates the release | Fedora, openSUSE | You cannot ship a build nobody proved boots |
| **Staged channels** between upstream and users | Manjaro (unstable→testing→stable), openSUSE Slowroll | Upstream breakage is absorbed by maintainers, not students |
| **Signed repositories** with a reviewed submission pipeline | Debian, Fedora, Flathub, Arch | A package a student installs is one a human approved |

CyberOS additionally has a constraint most distributions do not: **the update schedule
must be controllable by the department**, so a lab of 40 machines does not silently
change under an exam.

---

## 1. Scope

CyberOS ships as **one image**, built from one profile, with everything installed and
working offline.

| | |
|---|---|
| Contents | Live session, installer, desktop, dev tools, the full security-lab toolset |
| Size | ~4.7 GiB, 212 packages |
| Distribution | Campus mirror, department NAS, USB |

### 1.1 Why not a smaller "base" edition

An earlier draft of this spec required a `cyberos-base` edition of **2.0 GiB or less**, so
that the ISO could be attached to a GitHub release (assets cap at 2 GiB). That was
implemented, measured, and **withdrawn**, because the number was not reachable.

Splitting the security-lab toolset out moved the image from 4.9 GiB to 4.7 GiB. The lab
tools were never the bulk:

| Package | Installed |
|---|---|
| `onlyoffice-bin` | 1252 MiB |
| `visual-studio-code-bin` | 1018 MiB |
| the two together | **2270 MiB** |

Reaching 2 GiB would have meant dropping VS Code, OnlyOffice, both kernels' headers, the
CJK and Nerd fonts, `gcc`, `cmake`, `nodejs`, `docker`, `clamav` and Firefox — roughly
5.5 GiB of installed content. What remains after that is not a student desktop, and a
student with no network gets almost nothing.

The decision is therefore that **GitHub releases are not a distribution channel for the
ISO**. Tags and source stay on GitHub; the image goes out by campus mirror, NAS and USB,
which is how it has actually been distributed all along. Release notes link to the mirror.

This section is kept rather than deleted because the 2 GiB figure was written into a
specification, built against, and disproved by measurement. Someone will suggest it again.

### 1.1 Out of scope

- Architectures other than `x86_64`. No aarch64, no 32-bit.
- Server, container, or cloud images.
- Any device where the department does not control the firmware settings.
- Distributing the ISO as a GitHub release asset — see §1.1.

---

## 2. Hardware support tiers

"Runs well on all machines" is not a testable statement. This section replaces it with
three tiers. **Only Tier 1 gates a release.**

### 2.1 Tier 1 — Supported (blocking)

A release MUST NOT ship unless every Tier 1 configuration passes the §6 test matrix.

| Property | Requirement |
|---|---|
| CPU | `x86_64`, 2 cores. Upstream Arch builds for baseline `x86_64`, so that is the floor; `x86-64-v2` is *recommended* for acceptable desktop performance |
| Firmware | UEFI x64, Secure Boot **disabled or user-key-enrolled** |
| RAM | 4 GiB minimum for the live session, 8 GiB recommended for the lab toolset |
| Disk | 25 GiB free (installer already enforces this for alongside installs) |
| GPU | Intel Gen 6+ (`i915`), AMD GCN 1.0+ (`amdgpu`), or a VM with virtio-gpu/virgl |
| Firmware blobs | Whatever is in `linux-firmware` |
| Network | Any NIC with an in-tree driver |

### 2.2 Tier 2 — Best effort (non-blocking)

Bugs here are tracked and fixed but MUST NOT block a release.

- Legacy BIOS / CSM boot (the syslinux path already in `profiledef.sh`, currently untested)
- NVIDIA Turing and newer, via `nvidia-open-dkms` (610.57.04 in `extra`)
- Hybrid Intel+NVIDIA and AMD+NVIDIA laptops
- Broadcom wireless via `broadcom-wl-dkms` — common on the older Dell and Apple hardware
  students actually own, and not covered by `linux-firmware`
- Machines with 2–4 GiB RAM

### 2.3 Tier 3 — Documented, unsupported

Shipped with a documented workaround; no fix commitment.

- NVIDIA pre-Turing (`nvidia-open-dkms` does not support it; nouveau or Tier 3 only)
- GPUs with no working GL — MUST fall back to a usable session, see §2.5
- Secure Boot **enforced** with no ability to enrol keys. CyberOS has no
  Microsoft-signed shim and MUST NOT claim Secure Boot support.
- Any RAM below 2 GiB

### 2.4 Kernel policy

The image MUST offer two kernels:

| Package | Role |
|---|---|
| `linux` (7.1.9.arch1) | Default. Newest hardware support. |
| `linux-lts` (6.18.46) | Fallback boot entry. Recovers machines where a new kernel regresses a driver — the single most common cause of "it worked last month". |

Both MUST appear in the boot menu of the **installed** system, not only the live image.

### 2.5 Graphics fallback (blocking requirement)

Hyprland requires a working OpenGL/Wayland stack. On hardware where it does not
initialise, the current image gives the student a black screen and nothing else.

The boot menu MUST offer a **"CyberOS (safe graphics)"** entry that:
1. appends `nomodeset` to the kernel command line, and
2. starts the session with `WLR_RENDERER_ALLOW_SOFTWARE=1`.

The installed system MUST carry the same entry. A student who cannot reach a desktop
cannot file a bug, so this is treated as a boot requirement, not a nicety.

### 2.6 Firmware updates

`fwupd` (2.1.7) SHOULD be installed. Several Tier 2 failures — especially on Lenovo and
Dell laptops — are firmware bugs fixed by an LVFS update, and the fix costs one package.

---

## 3. Standards conformance

CyberOS follows the UAPI Group and freedesktop specifications rather than inventing
layout. Conformance is cheap here because systemd and Arch already implement most of it;
the value is that third-party tooling and other distributions' documentation apply.

| Spec | Requirement |
|---|---|
| **UAPI.1** Boot Loader Specification | **Aspirational, not yet met.** The installer uses GRUB, because GRUB is what gives us one bootloader for both UEFI and legacy BIOS plus `os-prober` for dual-boot — and BIOS and alongside-install are both requirements. GRUB does not emit Type #1 entries. Conformance would mean systemd-boot, and losing BIOS support with it, so this is recorded as a known deviation rather than a task. Revisit if Tier 2 BIOS support is ever dropped. |
| **UAPI.2** Discoverable Partitions | The installer MUST set GPT type `4f68bce3-e8cd-4db1-96e7-fbcaf984b709` (Linux x86-64 root) on the root partition and `c12a7328-f81f-11d2-ba4b-00a0c93ec93b` on the ESP. Already done — this pins it as a requirement. |
| **UAPI.5** Unified Kernel Images | Installations that enrol Secure Boot keys MUST use UKIs, since only a UKI can be signed as one object. Non-Secure-Boot installs keep the split kernel+initrd that GRUB expects. Tier 2 only; no plan implements it yet. |
| **UAPI.6** Configuration Files | All CyberOS state MUST live under `$XDG_CONFIG_HOME/cyberos/` (already true of `~/.config/cyberos/mode`) and `/etc/cyberos/` for system state. No dotfiles in `$HOME`. |
| **freedesktop AppStream** | Every package in `[cyberos-apps]` MUST ship a valid `.metainfo.xml`. This is the app store's catalogue format — §5. |
| **XDG Base Directory** | Already enforced via `xdg-user-dirs`. |

---

## 4. Release engineering — controlled, delayed rolling

### 4.1 The problem

Arch is rolling: `pacman -Syu` on two machines a week apart produces two different
systems. For a teaching lab this is the wrong default — a driver regression or a Python
minor bump lands mid-semester with nobody having tested it.

### 4.2 The model

Three channels, in the shape Manjaro uses (unstable → testing → stable), but implemented
without mirroring Arch. The mechanism is the **Arch Linux Archive**, which publishes a
dated snapshot of the official repositories every day at
`https://archive.archlinux.org/repos/YYYY/MM/DD/$repo/os/$arch`.

**A channel is a date.** Promoting a channel is moving that date forward.

| Channel | Pin | Advances | Audience |
|---|---|---|---|
| `unstable` | today | daily, automatically | maintainers only |
| `testing` | a chosen date | weekly, after the §6 smoke matrix passes | volunteer students, lab spares |
| `stable` | a chosen date | **monthly**, after the full §6 matrix passes | every student machine |

`stable` therefore lags upstream Arch by up to ~5 weeks. That lag is the product, not a
defect: it is the window in which maintainers absorb upstream breakage.

`/etc/pacman.d/cyberos-channel` on a student machine holds exactly one line:

```
Server = https://archive.archlinux.org/repos/2026/08/01/$repo/os/$arch
```

and `pacman.conf` includes that file for `[core]` and `[extra]` instead of the rolling
mirrorlist.

**Why this and not a full mirror:** mirroring `core`+`extra` is ~80 GiB and must be kept
in sync forever. The ALA is already that mirror, already dated, already public. The
department hosts only its own packages.

### 4.3 Security fixes must not wait for the schedule

A date pin freezes security fixes too, which would be worse than rolling. The escape
hatch is repository precedence: pacman resolves a package from the **first** repository
that contains it.

```
[cyberos-security]     # highest precedence — CVE fixes only
[cyberos-apps]
[cyberos]
[core]                 # pinned to the channel date
[extra]                # pinned to the channel date
```

When `arch-audit` (§7.4) reports a CVE in a package that the pin holds at a vulnerable
version, the maintainer copies **that single package** from current Arch into
`[cyberos-security]`. It overrides the pin for that package and nothing else.

- Time to publish a fix for a CVSS ≥ 7.0 vulnerability: **MUST be ≤ 72 hours** from the
  Arch Security Advisory.
- A `[cyberos-security]` entry MUST be removed once the channel pin advances past it, so
  the repo stays small and does not silently become a fork.
- `[cyberos-security]` MUST NOT be used to sneak feature updates past the schedule. Every
  entry needs a CVE or AVG identifier in the commit message.

### 4.4 Client tooling

`cyberos-channel` (new) — reads and switches the pin:

```
cyberos-channel                    # print current channel and pinned date
cyberos-channel set testing        # switch, warning that a downgrade needs -Syuu
cyberos-channel freeze 2026-08-01  # pin to an explicit date (exam weeks)
```

Moving *backwards* (stable→an older pin) downgrades packages and MUST require
`pacman -Syuu` and an explicit confirmation. Moving across more than **three** stable
snapshots at once SHOULD warn — the further the jump, the less it was tested.

### 4.5 Campus mirror

The ALA is one host and is not built to serve a whole campus. A department caching proxy
SHOULD sit in front of it. Any transparent pacman cache works; the client change is one
line in `cyberos-channel`.

### 4.6 Versioning

`YYYY.MM` for stable snapshots (`2026.09`). Build metadata `YYYY.MM.DD` stays as the ISO
version. Tags: `v2026.09` for a snapshot, `build-NN` for a build, as today.

---

## 5. The CyberOS app store and plugin market

### 5.1 Principle

**Nothing reaches a student that a maintainer did not approve.** This is the reason the
department runs its own repository instead of enabling the AUR, where PKGBUILDs are
arbitrary unreviewed shell scripts run as your user.

### 5.2 One mechanism, two catalogues

Apps and plugins are **both** pacman packages. There is no second packaging system.

| | Apps | Plugins |
|---|---|---|
| Naming | upstream name | `cyberos-plugin-<name>` |
| Examples | a CTF toolkit, a course IDE | a bar widget, an nvim colourscheme, a rofi menu, a lab exercise pack |
| Repo | `[cyberos-apps]` | `[cyberos-apps]` |
| Catalogue | AppStream `component/desktop-application` | AppStream `component/addon` |

They differ only by AppStream component type and a naming convention. Building a separate
plugin runtime would be a second thing to secure for no benefit.

### 5.3 Submission

A submission is a pull request to the `cyberos-apps` repository containing:

```
apps/<pkgname>/
├── PKGBUILD
├── <pkgname>.metainfo.xml     # AppStream, must validate
└── SUBMISSION.md              # what it is, who wrote it, why the department wants it
```

### 5.4 Verification gates

**All automated gates MUST pass before a human reviews.** A PR that fails any gate is not
reviewed.

| # | Gate | Tool | Rejects |
|---|---|---|---|
| G1 | PKGBUILD lint | `namcap PKGBUILD` | missing licence, bad deps, wrong arch |
| G2 | Sources are pinned and authenticated | script | any `source=` that is not `https://`, `git+https://#commit=`, or a local file; any `sha256sums=('SKIP')` on a non-VCS source |
| G3 | Clean-chroot build | `extra-x86_64-build` (`devtools`) | anything that needs the maintainer's machine to build |
| G4 | No network during build | build sandbox with networking off after source fetch | build-time curl-to-shell, the classic supply-chain vector |
| G5 | Built-package lint | `namcap *.pkg.tar.zst` | missing deps, world-writable files, insecure RPATH |
| G6 | Filesystem policy | script over `pacman -Qlp` | any setuid/setgid bit; any path outside `/usr`, `/opt`, `/etc`; any file in `/etc/sudoers.d`, `/etc/polkit-1/rules.d`, `/usr/lib/systemd/system` unless the PR is explicitly flagged for privilege review |
| G7 | Malware scan | `clamscan` over the package payload | known-bad binaries |
| G8 | Metadata valid | `appstreamcli validate --explain` | catalogue entries that would render broken |
| G9 | Licence present | script | package with no `licenses/` entry and no SPDX identifier |

**Human review (G10):** two maintainer approvals via CODEOWNERS. Reviewers MUST confirm
that the upstream source URL is the project's real home, that the version matches an
upstream release, and that anything caught by G6's privilege flag is justified.

### 5.5 Signing and publication

- The department holds a **GPG signing key**: an offline primary key, an on-disk signing
  subkey. The primary key MUST NOT live on the build machine.
- Packages are signed (`gpg --detach-sign`) and the database with `repo-add --sign`.
- The public key ships in a `cyberos-keyring` package, installed by the ISO, so trust is
  bootstrapped at install time and not by asking students to `pacman-key --recv`.
- Client config MUST be `SigLevel = Required DatabaseRequired TrustedOnly` for every
  `[cyberos*]` repo. **The current build-time `SigLevel = Optional TrustAll` in
  `profile/pacman.conf.in` is a known gap and MUST be closed.**

### 5.6 Promotion follows the OS channels

An approved package publishes to `[cyberos-apps]` on the **testing** channel first, and
promotes to **stable** on the same monthly cadence as the OS (§4.2). Security fixes to an
already-published app use the §4.3 route.

### 5.7 Client

`cyberos-store` — a CLI plus a Qt6/QML GUI (QtQuick, the same toolkit as the shell;
`qt6-declarative` is already on the ISO. Add `pyside6` alongside this client if it's
written in Python). It reads an
AppStream catalogue generated by `appstreamcli compose` and published beside the repo
database, and installs via `pkexec pacman`.

It MUST NOT implement its own download or install logic — pacman does that, with
signature verification. The store is a browser over a repository, nothing more.

---

## 6. Quality gates and the test matrix

Modelled on Fedora's release-criteria + openQA approach: a written list of what must work,
and automation that drives a VM like a human to prove it.

### 6.1 Release criteria (blocking)

A build MUST NOT be released unless all of these hold on **every Tier 1 configuration**:

1. The image boots to the live desktop.
2. Networking comes up (DHCP over the virtual/physical NIC).
3. The installer completes in each of its three modes — erase, alongside, custom.
4. The installed system boots unaided after the medium is removed.
5. The account created by the installer can log in, and `sudo` works.
6. The installer's files are absent from the installed system.
7. Both the `linux` and `linux-lts` boot entries boot.
8. The safe-graphics entry reaches a usable session (§2.5).
9. `pacman -Syu` on the pinned channel completes with no errors.
10. Theme toggle (`Super+Shift+T`) switches every themed surface, including a
    newly-opened terminal. *(Regression already seen: foot picked its palette from an
    absent appearance portal.)*
11. `lynis audit system` hardening index **MUST NOT** be below the previous release's.

### 6.2 Test matrix

The current matrix has **one** populated cell. The target:

| | UEFI + virtual disk | UEFI + USB on real hw | BIOS/CSM | Secure Boot (enrolled) |
|---|---|---|---|---|
| erase install | **done** | required | required | Tier 2 |
| alongside install | **done** | required | required | Tier 2 |
| custom partition | **done** | required | Tier 2 | Tier 2 |
| safe graphics | required | required | Tier 2 | — |

"required" = must pass before the first `v2026.MM` stable snapshot.

### 6.3 Automation

Release-criteria items 1–9 are scriptable against QEMU today: boot the ISO, drive the
installer through its CLI (`cyberos-install --yes --password-stdin`), reboot, assert.
Automating this is Plan 3, Task 5. The installer is CLI-only (the former GTK wizard
and its dry-run check are gone), so the whole flow is scriptable over `sendkey`.

### 6.4 Reproducible builds

The build MUST set `SOURCE_DATE_EPOCH` (`profiledef.sh` already reads it) and SHOULD
record a `BUILDINFO` for each `[cyberos*]` package. `archlinux-repro` (20260119) verifies
rebuilds. This is SLSA Build L1; signed provenance from CI would reach L2 and is the
target once packages are built by CI rather than a laptop.

**No plan implements this yet.** `SOURCE_DATE_EPOCH` is already set, which is most of L1;
`BUILDINFO` capture and a `rebuilderd` instance are deliberately deferred until the
repository is hosted (decision D1) and CI owns a signing subkey (D2). Recorded here so it is
a known gap rather than an assumed property.

---

## 7. Security requirements

### 7.1 Already satisfied

- SSH: `PermitRootLogin no`, `PermitEmptyPasswords no`, replacing archiso's permissive
  defaults. `sshd` is **not** enabled in the live image — verified.
- The live session's passwordless `root`/`student` exist only in the live image; the
  installer sets real passwords.
- Passwords reach the installer over stdin, never `argv` (`/proc/*/cmdline` is world-readable).
- The installer removes itself from the installed system.

### 7.2 Required changes

| # | Requirement | Why | Status |
|---|---|---|---|
| S1 | `ufw` MUST be **enabled** on installed systems with `default deny incoming`, `default allow outgoing` | It is currently installed but disabled, which protects nobody. A machine running Metasploit and Docker on a campus network needs a default-deny posture. | Done -- applied by `cyberos-firstboot` (ufw needs a running kernel, so it can't happen in the installer's chroot) |
| S2 | `[cyberos*]` repos MUST use `SigLevel = Required DatabaseRequired TrustedOnly` | Closes §5.5's `TrustAll` gap | Done -- `airootfs/etc/pacman.conf`'s `[cyberos]` block |
| S3 | The installer MUST offer **LUKS2 full-disk encryption** | Student laptops are lost and stolen; the machines hold lab material | Done -- `cyberos-install --encrypt` / the GUI wizard's Encrypt toggle |
| S4 | `arch-audit` MUST be installed with a weekly timer reporting CVEs against the pinned channel | §4.3 depends on knowing what is vulnerable | Done -- `cyberos-arch-audit.timer`/`.service`, enabled on install |
| S5 | `sbctl` SHOULD be installed and Secure Boot key enrolment documented | Tier 2 machines with SB on are otherwise unbootable | Done -- `sbctl` is installed; README "Notes / caveats" has a full enrol/sign/re-sign walkthrough. Initrd stays unsigned (split kernel+initrd, no UKI) until UAPI.5 lands -- tracked there, not here |
| S6 | The live session MUST NOT start `sshd` | Regression guard on 7.1 — the live user has no password | Done -- guarded by `tests/security.bats` |

### 7.3 Deliberately rejected

- **`linux-hardened` as the default kernel.** Its ptrace and BPF restrictions break
  debuggers, `gdb`, Metasploit and Ghidra — the entire point of the image. MAY be offered
  as an extra boot entry.
- **Disabling `docker`.** Docker's socket is a root-equivalent capability, but the course
  needs it. Mitigation is S1's firewall plus not adding students to the `docker` group by
  default.

### 7.4 Vulnerability handling

CyberOS follows Arch's advisory stream rather than duplicating it. `arch-audit` queries
`security.archlinux.org`, where the Arch Security Team tracks CVEs as AVGs and publishes
ASAs. A CyberOS advisory (a `CSA-YYYY-NNN` note in the repo) is only written when the fix
is CyberOS-specific — our packages, our configs, our installer.

### 7.5 Supply chain

Target **SLSA Build Level 2**: builds on a hosted platform (GitHub Actions) producing
signed provenance, so forging an artifact requires an attack rather than a mistake. L1
(provenance exists) is reachable immediately by recording `BUILDINFO`; L2 needs CI to own
the signing subkey. L3 is out of reach for a department and is not a goal.

---

## 8. Repository and branch policy

`main` is protected and always releasable. Work happens on topic branches named
`<area>/<topic>`, matching the CODEOWNERS areas. Each branch has a charter in
`docs/branches/`. See `docs/branches/README.md`.

---

## 9. Open decisions

These are not yet settled and block the work that depends on them.

| # | Decision | Blocks |
|---|---|---|
| D1 | Where are `[cyberos*]` repos hosted? 864 MiB rules out GitHub Pages. Campus web server, an object store, or a department NAS? | §4, §5 — nothing publishes until this is answered |
| D2 | Who holds the offline signing primary key, and where? | §5.5 |
| D3 | Is there a campus host for the ALA caching proxy? | §4.5 |
| D4 | Cisco Packet Tracer needs a licensed `.deb` from netacad that cannot be redistributed. Does it ship in the image, or install post-hoc? | §1 contents |

---

## References

- [UAPI Group Specifications](https://uapi-group.org/specifications/) — Boot Loader (UAPI.1), Discoverable Partitions (UAPI.2), Unified Kernel Images (UAPI.5), Configuration Files (UAPI.6)
- [Fedora QA: Release validation test plan](https://fedoraproject.org/wiki/QA:Release_validation_test_plan) and [Fedora openQA](https://fedoraproject.org/wiki/OpenQA)
- [Fedora 45 Final Release Criteria](https://fedoraproject.org/wiki/Fedora_45_Final_Release_Criteria)
- [Manjaro: Switching Branches](https://wiki.manjaro.org/) — the unstable→testing→stable staging model
- [openSUSE Slowroll](https://en.opensuse.org/Portal:Slowroll) — delayed rolling with continuous CVE fixes
- [Arch Security Team](https://wiki.archlinux.org/title/Arch_Security_Team) and the [Arch Security Tracker](https://github.com/archlinux/arch-security-tracker)
- [Arch Linux Archive](https://archive.archlinux.org/) — dated repository snapshots
- [Flathub MetaInfo guidelines](https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines) — app catalogue metadata quality bar
- [SLSA v1.0 security levels](https://slsa.dev/spec/v1.0/levels) — build provenance track
- [Arch Wiki: UEFI Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)
