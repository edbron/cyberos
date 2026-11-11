# CyberOS — Cyber Department Arch Linux spin

A reproducible [archiso](https://wiki.archlinux.org/title/Archiso) profile that builds a
**live + installer ISO** for the four-year programme. Everything is pre-installed and themed;
students boot the USB, try it, and run one command to install it to disk.

Created and maintained by **edbron** ([github.com/edbron](https://github.com/edbron))
for the Cyber Department, University of Mines and Technology, Tarkwa.

| Requirement          | What ships                                              |
|----------------------|---------------------------------------------------------|
| Base OS              | Arch Linux (rolling)                                    |
| Tiling WM            | Hyprland + Quickshell (QML shell: bar, launcher, OSD, power menu), rofi, mako, swaybg, hyprlock, hypridle |
| Display manager      | SDDM with the **Pixie** theme (`pixie-sddm-git`)        |
| Editors              | Neovim (themed config), VS Code (Microsoft build)       |
| Terminal             | foot + tmux (Ctrl-a prefix)                             |
| Browser              | Firefox                                                 |
| Office               | OnlyOffice Desktop Editors (`onlyoffice-bin`)           |
| Virtualisation       | VirtualBox (+ dkms host modules), guest utils for VMs   |
| Networking           | Cisco Packet Tracer (`packettracer`), Wireshark, nmap   |
| Security lab         | metasploit, ghidra, radare2, burp-free alternatives (sqlmap, nikto, gobuster), john, hashcat, hydra, aircrack-ng, bettercap, impacket, masscan, binwalk, volatility3, sleuthkit, yara, clamav, lynis, docker |
| Theme                | macOS window UI palette — Red Shimmer `#FF605C`, Coronation Gold `#FFBD44`, Malachite `#00CA4E`, Light Silver `#E1DFE1`, Argent `#C0BFC0`, Tech White `#F5F5F5`. **Dark by default, `Super+Shift+T` toggles light.** Custom wallpaper per mode, Papirus icons, JetBrainsMono Nerd Font |

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
        ├── etc/skel/.config/{hypr,quickshell,foot,tmux,nvim,wofi,mako,...}   ← the theme
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

On success, `build.sh` asks whether to delete `work/` (AUR build trees +
mkarchiso's scratch dir, easily several GB, none of it needed once `repo/`
has the packages and `out/` has the ISO). Answering no keeps the next build
fast; `--keep-work`/`--purge-work` skip the prompt (e.g. in CI).

Write to USB: `sudo dd if=out/cyberos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`
(or Ventoy / Rufus in DD mode).

## Installing on a student machine

Clicking **Install CyberOS** opens a graphical wizard: pick a disk, create the
account, confirm, watch it run. It is a front-end only — every disk operation is
still performed by `cyberos-install`, so the GUI and the CLI cannot drift apart.
`cyberos-install-gui --dry-run` clicks through the whole wizard without live media
and without touching a disk.

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
  `hypr/theme.lua`, `quickshell/theme.json` (consumed by `Theme.qml`), `foot/foot.ini`,
  `nvim/lua/cyber.lua`.
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

## Light and dark

CyberOS ships dark and switches with one command or `Super+Shift+T`:

```bash
cyberos-theme            # print the current mode (dark by default)
cyberos-theme light
cyberos-theme toggle
```

The palette lives in `cyberos-theme` alone, which generates the colours for
Hyprland, the Quickshell bar/launcher/OSD/power menu, rofi, foot, mako, tmux
and Neovim, sets the GTK/libadwaita colour scheme, and swaps the wallpaper.
There is one source of truth, so the applications cannot drift apart.
Already-open terminals keep their colours; new ones pick the new palette up.
The shell (Quickshell) re-themes live — no restart needed — because
`Theme.qml` watches `quickshell/theme.json` for changes.

Two notes on the palette. It is six colours — three accents and three near
whites — with no dark tone, so light mode adds a readable text colour
(`#1D1D1F`, `#6E6E73` muted) and dark mode adds backgrounds (`#1D1D1F`,
`#2B2B2D`, `#3A3A3C`); dark mode then uses Tech White and Argent for text.
ANSI terminals need eight hues where the palette gives three, so
blue/magenta/cyan follow the macOS system colours.

## Key bindings (Hyprland)

| Keys | Action |
|------|--------|
| `Super+Enter` | terminal (foot) |
| `Super+D` | app launcher (native QML, `Tab` switches apps/files search) |
| `Super+I` | Install CyberOS (live ISO) |
| `Super+Tab` | window switcher |
| `Super+.` / `Super+=` | emoji picker / calculator |
| `Super+B` / `E` / `C` | Firefox / files / VS Code |
| `Super+Q` | close window |
| `Super+H/J/K/L` | focus, `+Shift` move |
| `Super+1..0` | workspaces, `+Shift` move window |
| `Super+F` / `V` | fullscreen / float |
| `Super+Escape` | lock |
| `Super+Shift+U` | toggle touchscreen on/off |
| `Print` | screenshot region → clipboard |

## Notes / caveats

* Arch is rolling: rebuild the ISO each term so students start from fresh packages.
* `virtualbox-host-dkms` and (optionally) `nvidia-open-dkms` are compiled during the build,
  so builds are slower than a plain archiso.
* Packet Tracer's PKGBUILD pins a checksum; `build.sh` re-computes it for the `.deb` you supply.
* The Hyprland config ships in the **Lua format** (`etc/skel/.config/hypr/hyprland.lua`);
  the legacy `.conf` is removed in Hyprland 0.57, and 0.56.2 already warns about it on
  every login. Colours come from `theme.lua`, generated by `cyberos-theme` — do not put
  hex values in `hyprland.lua`. `hyprlock` still reads the hyprlang `theme.conf`, which
  is generated alongside it.
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

## Contributing

Branch off `main`, name the branch for the area it touches (`installer/`,
`theme/`, `packages/`, `build/`, `docs/`), open a pull request, and delete the
branch after it merges. Run `git config core.hooksPath .githooks` once per
clone and `bats tests/` before you open it.

The full guide — branch prefixes and their paths, the fresh-clone warning, the
test and build commands, and the commit conventions — is in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Author & credits

CyberOS — the archiso profile, installer, theming and build tooling in this repository —
is the original work of **edbron**, for the Cyber Department at the University of Mines
and Technology, Tarkwa.

It stands on other people's work, which keeps its own authorship:

* [Arch Linux](https://archlinux.org) and [archiso](https://wiki.archlinux.org/title/Archiso)
* [Hyprland](https://hypr.land) and the wider hypr ecosystem (hyprlock, hypridle)
* **Pixie** SDDM theme — xCaptaiN09 (`pixie-sddm-git`)
* Historical: the earlier waybar theme was adapted from
  [HANCORE-linux/waybar-themes](https://github.com/HANCORE-linux/waybar-themes) V2.3;
  the shell is now Quickshell (QML), but the palette it carried lives on in
  `cyberos-theme` and `theme.json`
* The UMaT brand palette belongs to the University of Mines and Technology.

