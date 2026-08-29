# CyberOS — Cyber Department Arch Linux spin

A reproducible [archiso](https://wiki.archlinux.org/title/Archiso) profile that builds a
**live + installer ISO** for the four-year programme. Everything is pre-installed and themed;
students boot the USB, try it, and run one command to install it to disk.

Created and maintained by **edbron** ([github.com/edbron](https://github.com/edbron))
for the Cyber Department, University of Mines and Technology, Tarkwa.

| Requirement          | What ships                                              |
|----------------------|---------------------------------------------------------|
| Base OS              | Arch Linux (rolling)                                    |
| Tiling WM            | Hyprland + waybar, rofi, mako, swaybg, hyprlock, hypridle       |
| Display manager      | SDDM with the **Pixie** theme (`pixie-sddm-git`)        |
| Editors              | Neovim (themed config), VS Code (Microsoft build)       |
| Terminal             | foot + tmux (Ctrl-a prefix)                             |
| Browser              | Firefox                                                 |
| Office               | OnlyOffice Desktop Editors (`onlyoffice-bin`)           |
| Virtualisation       | VirtualBox (+ dkms host modules), guest utils for VMs   |
| Networking           | Cisco Packet Tracer (`packettracer`), Wireshark, nmap   |
| Security lab         | metasploit, ghidra, radare2, burp-free alternatives (sqlmap, nikto, gobuster), john, hashcat, hydra, aircrack-ng, bettercap, impacket, masscan, binwalk, volatility3, sleuthkit, yara, clamav, lynis, docker |
| Theme                | "Cyber Department" on the **UMaT brand palette** (umat.edu.gh): green `#004C23`, gold `#FFCB06`, dark base `#0B1610`, accent green `#3DBB6E`; custom wallpaper, Papirus icons, JetBrainsMono Nerd Font |

Live session: auto-login as **student**, no password (passwordless `sudo`); root also has no password. Real passwords are set by the installer.

## Layout

```
cyberos/
├── build.sh              # one-shot builder: AUR → local repo → mkarchiso
├── test-vm.sh            # boot the ISO in QEMU/UEFI
├── aur/packages.txt      # AUR packages to build into repo/   (+ put the Packet Tracer .deb here)
├── repo/                 # generated local pacman repo of the AUR builds
├── out/                  # finished ISOs
└── profile/              # the archiso profile
    ├── profiledef.sh     # ISO name/label/version, permissions
    ├── packages.x86_64   # EVERYTHING installed on the image (edit this to add/remove software)
    ├── pacman.conf.in    # build-time pacman.conf (local [cyberos] repo)
    └── airootfs/         # files overlaid onto the root filesystem
        ├── etc/skel/.config/{hypr,waybar,foot,tmux,nvim,wofi,mako,...}   ← the theme
        ├── etc/sddm.conf.d/           # Pixie theme, live autologin
        ├── etc/{passwd,shadow,group}  # live users
        ├── root/customize_airootfs.sh # runs in the chroot during the build
        ├── usr/local/bin/cyberos-install   # the installer
        └── usr/share/backgrounds/cyberos/wallpaper.png
```

## Building

On an Arch Linux host (a VM is fine; needs ~15 GB free, internet, ~20–40 min):

```bash
sudo pacman -S archiso base-devel git
# Packet Tracer is licensed: log in at https://www.netacad.com, download
#   "CiscoPacketTracer_<ver>_Ubuntu_64bit.deb" and copy it to aur/
./build.sh                  # → out/cyberos-YYYY.MM.DD-x86_64.iso
./test-vm.sh                # boot it in QEMU  (pacman -S qemu-desktop edk2-ovmf)
```

Useful flags: `./build.sh --skip-aur` (reuse repo/), `--only-aur`, `--clean`.

Write to USB: `sudo dd if=out/cyberos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`
(or Ventoy / Rufus in DD mode).

## Installing on a student machine

Boot the USB (UEFI or legacy BIOS both work), log in, open a terminal (`Super+Enter`) and:

```bash
sudo cyberos-install                       # interactive
# or unattended, e.g. for imaging a lab:
sudo cyberos-install --disk /dev/nvme0n1 --hostname lab-07 --user student \
     --password 'ChangeMe!' --tz Africa/Accra --fs ext4 --yes
```

The installer offers two modes:

* **Erase whole disk** — automatic GPT layout (BIOS-boot 1 MiB + EFI 1 GiB + root), ext4 or btrfs,
  4 GiB swapfile. Boots on UEFI *and* legacy BIOS (protective-MBR boot flag is set for picky firmware).
* **Manual** — opens `cfdisk` on the chosen disk so you can shrink/keep other operating systems, then
  asks which partitions to use for `/` (formatted), the EFI System partition (keep or format — keeping
  an existing Windows ESP gives you dual boot via GRUB's os-prober), and an optional `/home`
  (keep or format).

Unattended examples:

```bash
sudo cyberos-install --disk /dev/nvme0n1 --erase --hostname lab-07 --user student --password 'x' --tz Africa/Accra --yes
sudo cyberos-install --disk /dev/sda --root /dev/sda5 --efi /dev/sda1 --home /dev/sda6 --password 'x' --yes
```

Either way it copies the live system, removes the live-only pieces (autologin, passwordless sudo,
archiso initramfs hooks, sleep masks), creates the user, installs GRUB for both UEFI and BIOS, and
the result is byte-for-byte the same software set as the ISO. GRUB is installed for **both** BIOS and UEFI
regardless of how the live ISO was booted. If a machine ever loses its bootloader, boot the ISO and run
`sudo cyberos-repair-boot`. `archinstall` is also on the ISO if
you prefer a stock Arch install.

## Customising

* **Add/remove software** → `profile/packages.x86_64` (official repos) or `aur/packages.txt` (AUR).
* **Theme/keybinds** → `profile/airootfs/etc/skel/.config/…`. Colours live in
  `hypr/theme.conf`, `waybar/style.css`, `foot/foot.ini`, `nvim/lua/cyber.lua`.
* **Wallpaper** → replace `airootfs/usr/share/backgrounds/cyberos/wallpaper.png` (also used by
  the SDDM greeter and the lock screen).
* **Name/version** → `profile/profiledef.sh`, `airootfs/etc/os-release`.
* **NVIDIA labs** → uncomment `nvidia-open-dkms` in `packages.x86_64`.
* **Security-lab tools** → the "security lab toolset" block in `packages.x86_64`; AUR-only
  extras (ffuf, burpsuite, responder, …) are listed there as a comment — add them to
  `aur/packages.txt` to include them.
* **Keeping installed machines updated** → host `repo/` on an internal web server and
  uncomment the `[cyberos]` block in `airootfs/etc/pacman.conf`; otherwise the AUR packages
  stay at the version baked into the ISO while everything else updates from Arch mirrors.

## Key bindings (Hyprland)

| Keys | Action |
|------|--------|
| `Super+Enter` | terminal (foot) |
| `Super+D` | app launcher (rofi) |
| `Super+I` | Install CyberOS (live ISO) |
| `Super+Tab` | window switcher |
| `Super+.` / `Super+=` | emoji picker / calculator |
| `Super+B` / `E` / `C` | Firefox / files / VS Code |
| `Super+Q` | close window |
| `Super+H/J/K/L` | focus, `+Shift` move |
| `Super+1..0` | workspaces, `+Shift` move window |
| `Super+F` / `V` | fullscreen / float |
| `Super+Escape` | lock |
| `Print` | screenshot region → clipboard |

## Notes / caveats

* Arch is rolling: rebuild the ISO each term so students start from fresh packages.
* `virtualbox-host-dkms` and (optionally) `nvidia-open-dkms` are compiled during the build,
  so builds are slower than a plain archiso.
* Packet Tracer's PKGBUILD pins a checksum; `build.sh` re-computes it for the `.deb` you supply.
* Hyprland ≥ 0.56 prefers a Lua config (`hyprland.lua`) but still loads the classic
  `hyprland.conf` shipped here. 0.56.2 emits no deprecation warning for it — only a
  DEBUG line, `[cfg] Lua config not found, using legacy config at …` — so the port is
  not needed yet. If a release drops legacy parsing, port
  `etc/skel/.config/hypr/hyprland.conf` — see https://wiki.hypr.land/Configuring/.
* **`ufw` is installed but not enabled.** A default-deny inbound policy would
  silently break the exercises this ISO is for — Metasploit handlers, bind
  shells and local servers all listen — so labs work out of the box. Turn it on
  when the exercise is about firewalls:

  ```bash
  sudo ufw enable                  # deny inbound, allow outbound
  sudo systemctl enable ufw        # persist across reboots
  sudo ufw allow 4444/tcp          # open a port for a listener
  sudo ufw status verbose
  ```

* SSH is installed but **not enabled**. The live image ships root and student
  with empty passwords, so `20-cyberos-hardening.conf` sets `PermitRootLogin no`
  and `PermitEmptyPasswords no`; installed systems inherit it.
* Secure Boot is not supported by archiso out of the box — disable it in firmware or enrol keys.

## Department package repo

CyberOS builds its own pacman repository, `[cyberos]`. `build.sh` builds
everything in `aur/packages.txt` — cloned from the AUR, or from a local
`aur/<name>/PKGBUILD` if one exists — into `repo/`, and the ISO installs from
there. Upstream AUR packages and department add-ons share one pipeline.

### Adding a department add-on

```bash
cp -r aur/cyberos-addon-template aur/cyberos-netlab
$EDITOR aur/cyberos-netlab/PKGBUILD      # payload, or just depends=() for a metapackage
echo cyberos-netlab >> aur/packages.txt
cd aur/cyberos-netlab && makepkg -sf     # build it alone, no full ISO build
```

A course toolset is usually a metapackage — no source, just
`depends=('nmap' 'wireshark-qt' 'python-scapy')` — so one install pulls a whole
module's tools.

### Publishing so installed machines can use it

Today `[cyberos]` is `Server = file://…`, which only exists on the build host.
Installed machines therefore cannot `pacman -S` department packages, and updates
reach them only via a new ISO. To fix that, serve the repo:

```bash
./tools/publish-repo.sh --key <KEYID>    # → dist/cyberos-repo/x86_64/
```

Upload that directory, then uncomment the `[cyberos]` block in
`/etc/pacman.conf` (it ships commented, with the URL to fill in).

**Sign it.** An unsigned repo over the network means whoever answers that
hostname installs packages as root on every lab machine. Make a department key
once, keep the private half off the lab machines, and ship the public half:

```bash
gpg --full-generate-key                        # "CyberOS Repository <…>"
gpg --list-secret-keys --keyid-format=long     # note the key id
```

The script prints the exact `pacman.conf` snippet and the `pacman-key` commands
for the key you used. Current repo size is ~864 MB, which rules out GitHub Pages
(1 GB soft limit).

## Contributing

Branch off `main`, open a pull request, delete the branch after it merges.
Name the branch for the area it touches:

| Prefix | Area | Paths |
|--------|------|-------|
| `installer/` | install, repair, first boot | `profile/airootfs/usr/local/bin/cyberos-*` |
| `theme/` | Hyprland, waybar, rofi, foot, SDDM, wallpapers | `etc/skel/.config/`, `usr/share/sddm/`, `usr/share/backgrounds/`, `assets/` |
| `packages/` | what ships in the ISO | `profile/packages.x86_64`, `aur/` |
| `build/` | build and test tooling | `build.sh`, `test-vm.sh`, `profiledef.sh`, `pacman.conf.in` |
| `docs/` | documentation | `README.md` |

```bash
git switch main && git pull
git switch -c theme/sddm-clock-overlap
# ... work, commit ...
git push -u origin theme/sddm-clock-overlap
```

A bug fix goes on the prefix of whatever it fixes — a broken keybind is
`theme/`, a failing install is `installer/`.

**Keep branches short-lived.** The ISO is built from one tree, so an area
branch cannot ship on its own, and the busiest files are shared: `hyprland.conf`,
`profiledef.sh` and `packages.x86_64` are all edited by theme, installer and
package work alike. Small PRs merged quickly beat long-running branches.

`.github/CODEOWNERS` maps these areas to reviewers, so the right person is
requested automatically.

### Before you start

* **Clone fresh.** The history was rewritten on 2026-08-29; an older clone holds
  different commit hashes and will try to push them back.
* **Never commit `profile/pacman.conf`.** It is generated by `build.sh` from the
  tracked `profile/pacman.conf.in`, and is gitignored along with `work/`, `out/`,
  `repo/` and `aur/*.deb` — no ISOs or built packages in git.
* **Test before you open the PR.** `./build.sh` produces the ISO (needs `sudo` for
  `mkarchiso`); `./test-vm.sh` boots the newest `out/*.iso` in QEMU. Anything that
  changes the installer or the boot path should be exercised by an actual install
  in the VM, not just a build.

## Author & credits

CyberOS — the archiso profile, installer, theming and build tooling in this repository —
is the original work of **edbron**, for the Cyber Department at the University of Mines
and Technology, Tarkwa.

It stands on other people's work, which keeps its own authorship:

* [Arch Linux](https://archlinux.org) and [archiso](https://wiki.archlinux.org/title/Archiso)
* [Hyprland](https://hypr.land) and the wider hypr ecosystem (hyprlock, hypridle)
* **Pixie** SDDM theme — xCaptaiN09 (`pixie-sddm-git`)
* waybar theme — [HANCORE-linux/waybar-themes](https://github.com/HANCORE-linux/waybar-themes)
  V2.3, adapted here for CyberOS
* The UMaT brand palette belongs to the University of Mines and Technology.

