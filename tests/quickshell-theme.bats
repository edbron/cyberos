#!/usr/bin/env bats
# The theming contract: cyberos-theme generates theme.json; Theme.qml consumes it.

ROOT="$BATS_TEST_DIRNAME/.."
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"

setup() {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
}

@test "cyberos-theme writes valid theme.json for both modes" {
  for mode in light dark; do
    env -u HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
      bash "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme" "$mode" >/dev/null
    python3 - "$XDG_CONFIG_HOME/quickshell/theme.json" "$mode" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
assert t["mode"] == sys.argv[2], t
for k in ("bg","surface","fg","muted","accent","accent2","alert","border","sel"):
    v = t[k]
    assert v.startswith("#") and len(v) == 7, (k, v)
assert 0 < t["barAlpha"] <= 1
PY
  done
}

@test "light and dark produce different backgrounds, same accent" {
  for mode in light dark; do
    env -u HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
      bash "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme" "$mode" >/dev/null
    cp "$XDG_CONFIG_HOME/quickshell/theme.json" "$BATS_TEST_TMPDIR/$mode.json"
  done
  python3 - "$BATS_TEST_TMPDIR" <<'PY'
import json, sys
l = json.load(open(sys.argv[1] + "/light.json")); d = json.load(open(sys.argv[1] + "/dark.json"))
assert l["bg"] != d["bg"]
assert l["accent"] == d["accent"] == "#00CA4E"
PY
}

@test "the skel theme.json is the dark palette, matching the skel default" {
  python3 - "$QS/theme.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
assert t["mode"] == "dark" and t["bg"] == "#1D1D1F" and t["accent"] == "#00CA4E"
PY
}

@test "cyberos-theme also writes an Omarchy-format colors.toml for fim" {
  # fim's live-theme auto-detection (tui-file-manager's theme/mod.rs) looks
  # for $XDG_STATE_HOME/omarchy/current/theme/colors.toml before falling
  # back to its own built-in palette; cyberos-theme must keep writing it so
  # fim follows the active CyberOS theme instead of always falling back.
  env -u HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    bash "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme" dark >/dev/null
  f="$XDG_STATE_HOME/omarchy/current/theme/colors.toml"
  [ -f "$f" ]
  python3 - "$f" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    t = tomllib.load(fh)
for k in ("foreground", "dark_foreground", "bright_foreground", "background",
          "dark_background", "darker_background", "lighter_background",
          "selection", "accent", "muted", "red", "green", "yellow", "cyan",
          "blue", "magenta"):
    v = t[k]
    assert v.startswith("#") and len(v) == 7, (k, v)
PY
}

@test "Theme.qml is a valid singleton and reads only theme.json" {
  grep -q '^pragma Singleton' "$QS/Theme.qml"
  grep -q 'singleton Theme' "$QS/qmldir"
  grep -q 'watchChanges' "$QS/Theme.qml"
}

@test "qmllint accepts Theme.qml (skips if qmllint absent)" {
  QMLLINT=/usr/lib/qt6/bin/qmllint
  [ -x "$QMLLINT" ] || skip "qmllint not installed"
  "$QMLLINT" --bare "$QS/Theme.qml"
}

@test "theme toggle flips gtk3 prefer-dark + qt6ct palette; gsettings gone" {
  t="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-theme"
  run grep 'gsettings' "$t"
  [ "$status" -ne 0 ]
  grep -q 'gtk-application-prefer-dark-theme' "$t"
  grep -q 'qt6ct.conf' "$t"
  grep -q 'color_scheme_path' "$t"
  grep -q 'gtk-theme-name=.*Adwaita-dark' "$t"
  grep -q 'gtk-icon-theme-name=.*Papirus' "$t"
  grep -q 'kdeglobals' "$t"
  grep -q 'icon_theme=' "$t"
}
