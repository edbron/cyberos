#!/usr/bin/env bats
# Qt desktop plumbing: portal routing, default apps, and the absence of the
# old thunar/xfce helper and GTK4 config files.

AIROOTFS="$BATS_TEST_DIRNAME/../profile/airootfs"

@test "portal config: hyprland first, kde FileChooser, no gtk" {
  f="$AIROOTFS/etc/xdg-desktop-portal/hyprland-portals.conf"
  [ -f "$f" ]
  grep -qx 'default=hyprland;kde' "$f"
  grep -qx 'org.freedesktop.impl.portal.FileChooser=kde' "$f"
  run grep 'gtk' "$f"
  [ "$status" -ne 0 ]
}

@test "mimeapps.list routes to the QML surfaces and the two kept apps" {
  f="$AIROOTFS/etc/skel/.config/mimeapps.list"
  grep -qx 'inode/directory=cyberos-fim.desktop' "$f"
  grep -qx 'image/png=cyberos-images.desktop' "$f"
  grep -qx 'application/pdf=firefox.desktop' "$f"
  grep -qx 'text/plain=code.desktop' "$f"
  grep -qx 'x-scheme-handler/https=firefox.desktop' "$f"
  # No KDE app ids may survive here -- those packages are gone, and a
  # dangling default silently breaks "Open with".
  run grep -E 'org\.kde\.|okularApplication' "$f"
  [ "$status" -ne 0 ]
}

@test "xfce helper and gtk-4.0 configs are gone; gtk-3.0 stays for firefox" {
  [ ! -e "$AIROOTFS/etc/skel/.config/xfce4" ]
  [ ! -e "$AIROOTFS/usr/share/xfce4" ]
  [ ! -e "$AIROOTFS/etc/skel/.local/share/applications/xfce4-about.desktop" ]
  [ ! -e "$AIROOTFS/etc/skel/.config/gtk-4.0" ]
  [ -f "$AIROOTFS/etc/skel/.config/gtk-3.0/settings.ini" ]
}
