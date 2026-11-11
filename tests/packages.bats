#!/usr/bin/env bats
# GTK purge: packages.x86_64 must not list GTK/GNOME desktop apps/applets,
# and must list their Qt6/KDE replacements. GTK3 itself may still arrive as
# a dependency of firefox/code -- that is fine and not tested here.

PKGS="$BATS_TEST_DIRNAME/../profile/packages.x86_64"

# Exact-name match against the package list with comments stripped.
pkg_listed() {
  sed 's/#.*//' "$PKGS" | tr -d ' ' | grep -v '^$' | grep -qx "$1"
}

@test "no GTK/GNOME packages remain in packages.x86_64" {
  for p in gtk4 libadwaita xdg-desktop-portal-gtk network-manager-applet \
           blueman pavucontrol thunar thunar-archive-plugin thunar-volman \
           gvfs gvfs-mtp file-roller tumbler imv zathura zathura-pdf-mupdf \
           gnome-calculator gnome-text-editor gnome-disk-utility nwg-look \
           adwaita-icon-theme gnome-themes-extra; do
    run pkg_listed "$p"
    [ "$status" -ne 0 ]
  done
}

@test "KDE applications are gone from packages.x86_64" {
  for p in dolphin ark okular gwenview kate kcalc partitionmanager \
           pavucontrol-qt kio-extras kio-fuse ffmpegthumbs \
           kdegraphics-thumbnailers breeze-icons; do
    run pkg_listed "$p"
    [ "$status" -ne 0 ]
  done
}

@test "headless Qt services and CLI tooling the QML surfaces need are present" {
  # portal-kde is the FileChooser backend for firefox/code (no window, no
  # KDE app); udisks2 mounts removable media; both are daemons, not apps.
  # fd backs the launcher's files-mode search (tests/quickshell.bats).
  # libnotify backs cyberos-toggle-touchscreen's notify-send feedback
  # (tests/touchscreen.bats).
  for p in xdg-desktop-portal-kde udisks2 adwaita-cursors xdg-utils trash-cli 7zip unzip fd libnotify; do
    pkg_listed "$p"
  done
}

@test "fim is listed as a package" {
  pkg_listed "fim"
}

@test "fim has a local PKGBUILD" {
  [ -f "$BATS_TEST_DIRNAME/../aur/fim/PKGBUILD" ]
}

@test "fim is registered for local build" {
  grep -qx "fim" "$BATS_TEST_DIRNAME/../aur/packages.txt"
}

@test "filetransferd is enabled as a default user unit" {
  [ -L "$BATS_TEST_DIRNAME/../profile/airootfs/etc/systemd/user/default.target.wants/filetransferd.service" ]
}

@test "ftctl and filetransferd binaries are vendored" {
  [ -x "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/filetransferd" ]
  [ -x "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/ftctl" ]
}

@test "ft_common is vendored -- ftctl/filetransferd both import it" {
  [ -f "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/ft_common.py" ]
  grep -q "import ft_common" "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/ftctl"
  grep -q "import ft_common" "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/filetransferd"
}
