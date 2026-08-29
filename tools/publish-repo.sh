#!/usr/bin/env bash
# ============================================================================
#  publish-repo.sh — package repo/ into a directory you can serve over HTTP,
#  so installed CyberOS machines can `pacman -S` department packages and get
#  updates without a new ISO.
#
#  Usage:
#     ./tools/publish-repo.sh                 # unsigned (LAN / testing only)
#     ./tools/publish-repo.sh --key <KEYID>   # signed (required for internet)
#
#  Output: dist/cyberos-repo/x86_64/  — upload that directory as-is.
#
#  Signing matters. An unsigned repo served over the network means whoever
#  answers that hostname installs packages as root on every lab machine. Make a
#  department key once:
#     gpg --full-generate-key            # "CyberOS Repository <...>"
#     gpg --list-secret-keys --keyid-format=long
#  and pass its id with --key.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/repo"
DIST="$ROOT/dist/cyberos-repo/x86_64"
KEY=""
BASEURL="${CYBEROS_REPO_URL:-https://REPLACE-ME.example/cyberos}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY=$2; shift 2;;
    --url) BASEURL=$2; shift 2;;
    -h|--help) sed -n '3,20p' "$0"; exit 0;;
    *) echo "unknown option $1" >&2; exit 1;;
  esac
done

msg() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d $REPO ]] || die "no repo/ — run ./build.sh first (it builds the packages)"
shopt -s nullglob
pkgs=("$REPO"/*.pkg.tar.zst)
(( ${#pkgs[@]} )) || die "repo/ has no packages — run ./build.sh without --skip-aur"

msg "Staging ${#pkgs[@]} package(s)"
rm -rf "$DIST"; mkdir -p "$DIST"
cp -f "${pkgs[@]}" "$DIST/"

if [[ -n $KEY ]]; then
  msg "Signing packages with $KEY"
  for p in "$DIST"/*.pkg.tar.zst; do
    gpg --detach-sign --no-armor --local-user "$KEY" --yes "$p"
  done
  msg "Building signed database"
  repo-add -q --sign --key "$KEY" "$DIST/cyberos.db.tar.gz" "$DIST"/*.pkg.tar.zst
  SIGLEVEL="Required DatabaseRequired"
else
  msg "Building UNSIGNED database"
  repo-add -q "$DIST/cyberos.db.tar.gz" "$DIST"/*.pkg.tar.zst
  SIGLEVEL="Optional TrustAll"
  echo "WARNING: unsigned. Anyone who can answer that URL installs packages as root" >&2
  echo "         on every machine using this repo. Use --key before exposing it." >&2
fi

msg "Done — upload this directory"
echo "  $DIST"
echo
echo "Then on client machines, in /etc/pacman.conf:"
echo
echo "  [cyberos]"
echo "  SigLevel = $SIGLEVEL"
echo "  Server = $BASEURL/\$arch"
echo
if [[ -n $KEY ]]; then
  echo "and trust the key once (ship the public key in the ISO, or fetch it):"
  echo "  sudo pacman-key --add cyberos.gpg && sudo pacman-key --lsign-key $KEY"
  echo
fi
du -sh "$DIST" | sed 's/^/  size: /'
