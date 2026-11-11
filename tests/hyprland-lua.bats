#!/usr/bin/env bats
# Executes hyprland.lua against a stub `hl` that records calls. A config that
# parses but registers no binds trips Hyprland's emergency mode, so parsing is
# not enough.

HYPR="$BATS_TEST_DIRNAME/../profile/airootfs/etc/skel/.config/hypr"
STUB="$BATS_TEST_DIRNAME/hl-stub.lua"

setup() {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$XDG_CONFIG_HOME/hypr"
  cp "$HYPR/theme.lua" "$XDG_CONFIG_HOME/hypr/theme.lua"
  # Isolates the touchscreen-restore block's state read from whatever the
  # real running user happens to have under ~/.local/state/cyberos.
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
}

run_config() { lua -e "dofile('$STUB'); dofile('$HYPR/hyprland.lua'); report()"; }

@test "hyprland.lua and theme.lua are valid Lua" {
  luac -p "$HYPR/hyprland.lua" "$HYPR/theme.lua"
}

@test "the config registers the core binds" {
  run run_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"bind SUPER + Return"* ]]
  [[ "$output" == *"bind SUPER + SHIFT + T"* ]]
  [[ "$output" == *"bind SUPER + I"* ]]
  [[ "$output" == *"bind SUPER + 1"* ]]
  [[ "$output" == *"bind SUPER + SHIFT + 0"* ]]
  [[ "$output" == *"bind Print"* ]]
}

@test "enough binds to never trip emergency mode" {
  run run_config
  n=$(grep -c '^bind ' <<<"$output")
  [ "$n" -ge 60 ]
}

@test "autostart launches the bar (notifications now live inside it) and idle daemon" {
  run run_config
  [[ "$output" == *"exec qs"* ]]
  [[ "$output" == *"exec hypridle"* ]]
  ! grep -q 'exec mako' <<<"$output"
}

@test "border colours come from theme.lua, not from the config" {
  run run_config
  [[ "$output" == *"active_border=rgb(00CA4E)"* ]]
  ! grep -qE 'rgb\([0-9A-F]{6}\)' <<<"$(grep -v 'fallback\|theme = {' "$HYPR/hyprland.lua" | grep -v '^--')" \
    || { echo "hex colours found in hyprland.lua; they belong in cyberos-theme"; false; }
}

@test "a missing theme.lua degrades to the fallback palette instead of failing" {
  rm "$XDG_CONFIG_HOME/hypr/theme.lua"
  run run_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_border=rgb(00CA4E)"* ]]
}

@test "cyberos-theme generates a theme.lua that hyprland.lua consumes, both modes" {
  for mode in light dark; do
    env -u HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
      bash "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-theme" "$mode" >/dev/null
    luac -p "$XDG_CONFIG_HOME/hypr/theme.lua"
    run run_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"active_border=rgb(00CA4E)"* ]]
    grep -q "mode    = \"$mode\"" "$XDG_CONFIG_HOME/hypr/theme.lua"
  done
}

@test "the legacy hyprland.conf is gone, so the two cannot drift" {
  [ ! -e "$HYPR/hyprland.conf" ]
}

@test "volume/brightness binds dispatch through the quickshell OSD ipc, swayosd gone" {
  run run_config
  [[ "$output" == *"bindcmd XF86AudioRaiseVolume :: qs ipc call osd volumeUp"* ]]
  [[ "$output" == *"bindcmd XF86AudioLowerVolume :: qs ipc call osd volumeDown"* ]]
  [[ "$output" == *"bindcmd XF86AudioMute :: qs ipc call osd volumeMute"* ]]
  [[ "$output" == *"bindcmd XF86MonBrightnessUp :: qs ipc call osd brightnessUp"* ]]
  [[ "$output" == *"bindcmd XF86MonBrightnessDown :: qs ipc call osd brightnessDown"* ]]
  [[ "$output" != *"swayosd"* ]]
}

@test "the quickshell layer gets a layer_rule keyed on its own namespace" {
  run run_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"layer_rule ns=quickshell"* ]]
}

@test "autostart execs qs exactly once; swaybg/cliphist survive; GTK applets gone" {
  run run_config
  [ "$status" -eq 0 ]
  n=$(grep -c '^exec qs$' <<<"$output")
  [ "$n" -eq 1 ]
  [[ "$output" == *"exec swaybg"* ]]
  [[ "$output" != *"nm-applet"* ]]
  [[ "$output" != *"blueman-applet"* ]]
  [[ "$output" == *"exec wl-paste --type text --watch cliphist store"* ]]
  [[ "$output" == *"exec wl-paste --type image --watch cliphist store"* ]]
}

@test "app binds target the Qt apps; installer launches without gtk-launch" {
  run run_config
  [[ "$output" == *"bindcmd SUPER + E :: cyberos-files"* ]]
  [[ "$output" == *'bindcmd SUPER + I :: foot --app-id=cyberos-installer --title="Install CyberOS" sudo /usr/local/bin/cyberos-install'* ]]
  [[ "$output" != *"gtk-launch"* ]]
}

@test "Super+D opens the quickshell launcher" {
  run run_config
  [[ "$output" == *"bindcmd SUPER + D :: qs ipc call launcher toggle"* ]]
  [[ "$output" != *"bindcmd SUPER + D :: rofi"* ]]
}

@test "Super+equal opens the quickshell calc, Super+X opens the quickshell clip history (Task 4)" {
  run run_config
  [[ "$output" == *"bindcmd SUPER + equal :: qs ipc call calc toggle"* ]]
  [[ "$output" == *"bindcmd SUPER + X :: qs ipc call clip toggle"* ]]
  # merged into one alternation so the negated check is the sole/last
  # statement -- a mid-body "!" is exempt from errexit and would be
  # silently swallowed by a later passing statement otherwise.
  ! grep -qE 'rofi -show calc|rofi -dmenu' <<<"$output"
}

@test "Super+period opens the quickshell emoji picker; rofi -show emoji is gone" {
  run run_config
  [[ "$output" == *"bindcmd SUPER + period :: qs ipc call emoji toggle"* ]]
  ! grep -q 'bindcmd SUPER + period :: rofi' <<<"$output"
}

@test "Super+Shift+U toggles the touchscreen" {
  run run_config
  [[ "$output" == *"bindcmd SUPER + SHIFT + U :: cyberos-toggle-touchscreen"* ]]
}

@test "no persisted touchscreen-disabled state: hl.device is never called" {
  run run_config
  [ "$status" -eq 0 ]
  ! grep -q '^device ' <<<"$output"
}

@test "a persisted touchscreen-disabled name is restored as enabled=false on config load" {
  mkdir -p "$XDG_STATE_HOME/cyberos"
  printf 'ELAN9008:00 04F3:2A1B Touchscreen\n' > "$XDG_STATE_HOME/cyberos/touchscreen-disabled-name"
  run run_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"device name=ELAN9008:00 04F3:2A1B Touchscreen enabled=false"* ]]
}

@test "an empty persisted-name file restores nothing (no crash, no bogus hl.device call)" {
  mkdir -p "$XDG_STATE_HOME/cyberos"
  : > "$XDG_STATE_HOME/cyberos/touchscreen-disabled-name"
  run run_config
  [ "$status" -eq 0 ]
  ! grep -q '^device ' <<<"$output"
}
