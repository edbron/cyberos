#!/usr/bin/env bash
# ============================================================================
#  CyberOS ISO builder
#    1. builds the AUR packages listed in aur/packages.txt into repo/ (as your user)
#    2. runs mkarchiso (as root) with profile/  →  out/cyberos-YYYY.MM.DD-x86_64.iso
#
#  Requirements (on an Arch host):  sudo pacman -S archiso base-devel git
#  Packet Tracer: drop CiscoPacketTracer_*_Ubuntu_64bit.deb (from netacad.com) into aur/
# ============================================================================
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO="$ROOT/repo"; WORK="$ROOT/work"; OUT="$ROOT/out"; PROFILE="$ROOT/profile"
SKIP_AUR=0; ONLY_AUR=0
for a in "$@"; do case $a in --skip-aur) SKIP_AUR=1;; --only-aur) ONLY_AUR=1;; --clean) sudo rm -rf "$WORK";; esac; done

msg() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run build.sh as a normal user; it calls sudo where needed"
command -v mkarchiso >/dev/null || die "archiso not installed:  sudo pacman -S archiso"
command -v makepkg   >/dev/null || die "base-devel not installed: sudo pacman -S base-devel git"

# ------------------------------------------------------------------ 1. AUR
if [[ $SKIP_AUR -eq 0 ]]; then
  mkdir -p "$REPO" "$WORK/aur"
  while read -r pkg; do
    [[ -z $pkg || $pkg == \#* ]] && continue
    msg "AUR: $pkg"
    d="$WORK/aur/$pkg"
    if [[ -f $ROOT/aur/$pkg/PKGBUILD ]]; then
      mkdir -p "$d"; cp -f "$ROOT/aur/$pkg"/* "$d/"          # local PKGBUILD
    elif [[ -d $d/.git ]]; then git -C "$d" pull -q; else git clone -q "https://aur.archlinux.org/$pkg.git" "$d"; fi
    if [[ $pkg == packettracer ]]; then
      deb=$(ls "$ROOT"/aur/CiscoPacketTracer_*_Ubuntu_64bit.deb 2>/dev/null | head -1 || true)
      [[ -n $deb ]] || die "Packet Tracer: put CiscoPacketTracer_*_Ubuntu_64bit.deb from https://www.netacad.com into $ROOT/aur/"
      cp -f "$deb" "$d/"
      # Cisco re-releases the same version with different checksums; trust our local copy.
      (cd "$d" && updpkgsums >/dev/null 2>&1 || true)
    fi
    (cd "$d" && makepkg -sf --noconfirm --needed)
    cp -f "$d"/*.pkg.tar.zst "$REPO/"
  done < "$ROOT/aur/packages.txt"
  # CyberOS's own packages. Unlike aur/ (upstream inputs we merely build), these
  # are what the department maintains and releases; they go in the same repo so
  # the ISO can install them and tools/release.sh can publish them.
  for d in "$ROOT"/packages/*/; do
    name=$(basename "$d")
    [[ -f $d/PKGBUILD && $name != template ]] || continue
    msg "CyberOS package: $name"
    (cd "$d" && makepkg -sf --noconfirm --needed)
    cp -f "$d"/*.pkg.tar.zst "$REPO/"
  done

  msg "Creating local repo"
  rm -f "$REPO"/cyberos.db* "$REPO"/cyberos.files*
  repo-add -q "$REPO/cyberos.db.tar.gz" "$REPO"/*.pkg.tar.zst
fi
[[ $ONLY_AUR -eq 1 ]] && exit 0

[[ -f $REPO/cyberos.db ]] || die "repo/ is empty — run without --skip-aur first"

# ------------------------------------------------------------------ 2. ISO
msg "Generating profile/pacman.conf"
sed "s|@REPO_DIR@|$REPO|" "$PROFILE/pacman.conf.in" > "$PROFILE/pacman.conf"

msg "Building ISO with mkarchiso (needs root)"
mkdir -p "$OUT"
sudo mkarchiso -v -w "$WORK/iso" -o "$OUT" "$PROFILE"
sudo chown "$USER:$USER" "$OUT"/*.iso
msg "ISO ready:"; ls -lh "$OUT"/*.iso
echo "Test it:  ./test-vm.sh $(ls "$OUT"/*.iso | tail -1)"
