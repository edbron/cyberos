#!/usr/bin/env bash
# ============================================================================
#  release.sh — build, sign and stage CyberOS's own packages for release.
#
#  Everything under packages/ is software the department maintains. This builds
#  each one, signs it with the department key, and assembles a signed [cyberos]
#  repository that installed machines can pacman -S from and update against.
#
#  Usage:
#     ./tools/release.sh --key <KEYID>     # normal: signed, verifiable
#     ./tools/release.sh --unsigned        # LAN testing only, refuses to be quiet
#
#  Output: dist/cyberos-repo/x86_64/  — upload that directory as-is.
#
#  Make the department key once, and keep the private half OFF lab machines:
#     gpg --full-generate-key                       # "CyberOS Repository <...>"
#     gpg --list-secret-keys --keyid-format=long    # note the key id
#     gpg --export --armor <KEYID> > cyberos.gpg    # public half, ship in the ISO
#  Put that cyberos.gpg at profile/airootfs/usr/share/pacman/keyrings/ and the
#  build will trust it, so pacman verifies every CyberOS package it installs.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/packages"
REPO="$ROOT/repo"
DIST="$ROOT/dist/cyberos-repo/x86_64"
KEY="" UNSIGNED=0 SKIP_BUILD=0
BASEURL="${CYBEROS_REPO_URL:-https://REPLACE-ME.example/cyberos}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY=$2; shift 2;;
    --unsigned) UNSIGNED=1; shift;;
    --no-build) SKIP_BUILD=1; shift;;
    --url) BASEURL=$2; shift 2;;
    -h|--help) sed -n '3,20p' "$0"; exit 0;;
    *) echo "unknown option $1" >&2; exit 1;;
  esac
done

msg() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

if [[ -z $KEY && $UNSIGNED -eq 0 ]]; then
  die "no signing key. Pass --key <KEYID>, or --unsigned for LAN testing only.

An unsigned repo served over the network means whoever answers that hostname
installs packages as root on every lab machine using it. See the header of
this script for making the department key."
fi

# ---------------------------------------------------------------- 1. build
mkdir -p "$REPO"
if [[ $SKIP_BUILD -eq 0 ]]; then
  shopt -s nullglob
  built=0
  for d in "$SRC"/*/; do
    name=$(basename "$d")
    [[ -f $d/PKGBUILD ]] || continue
    [[ $name == template ]] && continue        # the template is not a release
    msg "Building $name"
    (cd "$d" && makepkg -sf --noconfirm --needed)
    cp -f "$d"/*.pkg.tar.zst "$REPO/"
    built=$((built + 1))
  done
  [[ $built -gt 0 ]] || echo "note: packages/ has no packages yet beyond the template" >&2
fi

# ---------------------------------------------------------------- 2. stage
shopt -s nullglob
pkgs=("$REPO"/*.pkg.tar.zst)
(( ${#pkgs[@]} )) || die "nothing to release: repo/ is empty"

msg "Staging ${#pkgs[@]} package(s)"
rm -rf "$DIST"; mkdir -p "$DIST"
cp -f "${pkgs[@]}" "$DIST/"

# ---------------------------------------------------------------- 3. sign
if [[ -n $KEY ]]; then
  msg "Signing with $KEY"
  for p in "$DIST"/*.pkg.tar.zst; do
    gpg --detach-sign --no-armor --local-user "$KEY" --yes "$p"
  done
  repo-add -q --sign --key "$KEY" "$DIST/cyberos.db.tar.gz" "$DIST"/*.pkg.tar.zst
  SIGLEVEL="Required DatabaseRequired"
else
  msg "Building UNSIGNED database"
  repo-add -q "$DIST/cyberos.db.tar.gz" "$DIST"/*.pkg.tar.zst
  SIGLEVEL="Optional TrustAll"
  echo "WARNING: unsigned — do not expose this beyond a trusted LAN." >&2
fi

# ---------------------------------------------------------------- 4. report
msg "Done — upload this directory"
echo "  $DIST"
echo
echo "Client /etc/pacman.conf:"
echo
echo "  [cyberos]"
echo "  SigLevel = $SIGLEVEL"
echo "  Server = $BASEURL/\$arch"
echo
[[ -n $KEY ]] && cat <<TRUST
The ISO trusts the key automatically if profile/airootfs/usr/share/pacman/keyrings/cyberos.gpg
exists at build time. On a machine installed before that, trust it once:
  sudo pacman-key --add cyberos.gpg && sudo pacman-key --lsign-key $KEY

TRUST
du -sh "$DIST" | sed 's/^/  size: /'
