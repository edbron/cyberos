#!/usr/bin/env bats
# cyberos-toggle-touchscreen (Super+Shift+U): enable/disable the touchscreen
# via Hyprland 0.56's hl.device({name, enabled}) Lua API, issued through
# `hyprctl eval`. hyprctl itself is stubbed here -- these tests run with no
# live Hyprland session and no real touch hardware, on a dev host that has
# neither.

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/profile/airootfs/usr/local/bin/cyberos-toggle-touchscreen"

setup() {
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  HYPRCTL_CALL_FILE="$BATS_TEST_TMPDIR/hyprctl-calls"
  NOTIFY_CALL_FILE="$BATS_TEST_TMPDIR/notify-calls"
  export HYPRCTL_CALL_FILE NOTIFY_CALL_FILE
  : > "$HYPRCTL_CALL_FILE"
  : > "$NOTIFY_CALL_FILE"

  # devices -j returns whatever's in FAKE_DEVICES_JSON; eval calls are just
  # logged (argv, one line per arg, so a multi-word eval string stays intact
  # as a single logged line).
  cat > "$BATS_TEST_TMPDIR/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$HYPRCTL_CALL_FILE"
if [[ "$1" == "devices" ]]; then
  cat "$FAKE_DEVICES_JSON"
fi
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/hyprctl"

  cat > "$BATS_TEST_TMPDIR/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$NOTIFY_CALL_FILE"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/notify-send"

  ONE_TOUCH="$BATS_TEST_TMPDIR/one-touch.json"
  printf '{"touch":[{"name":"ELAN9008:00 04F3:2A1B Touchscreen"}]}' > "$ONE_TOUCH"
  NO_TOUCH="$BATS_TEST_TMPDIR/no-touch.json"
  printf '{"touch":[]}' > "$NO_TOUCH"
  export ONE_TOUCH NO_TOUCH
}

@test "script exists, executable, valid bash" {
  [ -x "$SCRIPT" ]
  bash -n "$SCRIPT"
}

@test "lib-only sourcing defines helpers without side effects" {
  export CYBEROS_TOUCHSCREEN_LIB_ONLY=1
  run bash -c "source '$SCRIPT'; type escape_lua_string has_control_chars find_touch_device apply_device enable_touchscreen disable_touchscreen >/dev/null"
  [ "$status" -eq 0 ]
  [ ! -s "$HYPRCTL_CALL_FILE" ]
}

@test "escape_lua_string: backslash escaped before quote (order matters)" {
  export CYBEROS_TOUCHSCREEN_LIB_ONLY=1
  run bash -c "source '$SCRIPT'; escape_lua_string 'weird\\\"name'"
  [ "$status" -eq 0 ]
  [ "$output" = 'weird\\\"name' ]
}

@test "escape_lua_string: a plain name is untouched" {
  export CYBEROS_TOUCHSCREEN_LIB_ONLY=1
  run bash -c "source '$SCRIPT'; escape_lua_string 'ELAN9008:00 04F3:2A1B Touchscreen'"
  [ "$output" = 'ELAN9008:00 04F3:2A1B Touchscreen' ]
}

@test "has_control_chars: detects a control byte, passes a normal name" {
  export CYBEROS_TOUCHSCREEN_LIB_ONLY=1
  run bash -c "source '$SCRIPT'; has_control_chars \$'bad\x01name'"
  [ "$status" -eq 0 ]
  run bash -c "source '$SCRIPT'; has_control_chars 'normal name'"
  [ "$status" -eq 1 ]
}

@test "find_touch_device: reads the name back out of hyprctl devices -j" {
  export CYBEROS_TOUCHSCREEN_LIB_ONLY=1 FAKE_DEVICES_JSON="$ONE_TOUCH"
  run bash -c "source '$SCRIPT'; find_touch_device"
  [ "$output" = "ELAN9008:00 04F3:2A1B Touchscreen" ]
}

@test "find_touch_device: empty (not an error) when no touch device is present" {
  export CYBEROS_TOUCHSCREEN_LIB_ONLY=1 FAKE_DEVICES_JSON="$NO_TOUCH"
  run bash -c "source '$SCRIPT'; find_touch_device"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "disabling: hyprctl eval carries enabled=false, state file records the device name, notified" {
  export FAKE_DEVICES_JSON="$ONE_TOUCH"
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  grep -qE '^hl\.device\(\{ name = "ELAN9008:00 04F3:2A1B Touchscreen", enabled = false \}\)$' "$HYPRCTL_CALL_FILE"
  [ "$(cat "$XDG_STATE_HOME/cyberos/touchscreen-disabled-name")" = "ELAN9008:00 04F3:2A1B Touchscreen" ]
  grep -q "Touchscreen disabled" "$NOTIFY_CALL_FILE"
}

@test "enabling: hyprctl eval carries enabled=true, state file removed" {
  export FAKE_DEVICES_JSON="$ONE_TOUCH"
  mkdir -p "$XDG_STATE_HOME/cyberos"
  printf 'ELAN9008:00 04F3:2A1B Touchscreen\n' > "$XDG_STATE_HOME/cyberos/touchscreen-disabled-name"
  run "$SCRIPT" on
  [ "$status" -eq 0 ]
  grep -qE '^hl\.device\(\{ name = "ELAN9008:00 04F3:2A1B Touchscreen", enabled = true \}\)$' "$HYPRCTL_CALL_FILE"
  [ ! -f "$XDG_STATE_HOME/cyberos/touchscreen-disabled-name" ]
  grep -q "Touchscreen enabled" "$NOTIFY_CALL_FILE"
}

@test "toggle: no state file disables; a state file present re-enables" {
  export FAKE_DEVICES_JSON="$ONE_TOUCH"
  run "$SCRIPT" toggle
  [ "$status" -eq 0 ]
  grep -q "enabled = false" "$HYPRCTL_CALL_FILE"
  : > "$HYPRCTL_CALL_FILE"
  run "$SCRIPT" toggle
  [ "$status" -eq 0 ]
  grep -q "enabled = true" "$HYPRCTL_CALL_FILE"
}

@test "no touchscreen present: notifies, exits non-zero, never calls hyprctl eval" {
  export FAKE_DEVICES_JSON="$NO_TOUCH"
  run "$SCRIPT" toggle
  [ "$status" -ne 0 ]
  grep -q "No touchscreen found" "$NOTIFY_CALL_FILE"
  ! grep -q '^eval$' "$HYPRCTL_CALL_FILE"
}

@test "a device name with a quote and a backslash cannot break out of the Lua string" {
  MALICIOUS='$BATS_TEST_TMPDIR/malicious.json'
  printf '{"touch":[{"name":"evil\\\\\\" .. os.execute(\\\"touch /tmp/pwned\\\") .. \\\""}]}' > "$BATS_TEST_TMPDIR/malicious.json"
  export FAKE_DEVICES_JSON="$BATS_TEST_TMPDIR/malicious.json"
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  # Every quote the raw name contributes must appear as \" in the eval
  # string, never as a bare " that could close the Lua literal early.
  # grep -c counts matching *lines*, not occurrences, and this is all one
  # line -- grep -o | wc -l counts the actual \" occurrences instead.
  count=$(grep -o '\\"' "$HYPRCTL_CALL_FILE" | wc -l)
  [ "$count" -ge 2 ]
  ! grep -qE '[^\\]" \.\. os\.execute' "$HYPRCTL_CALL_FILE"
}

@test "a control character in the device name is rejected, not passed to hyprctl eval" {
  printf '{"touch":[{"name":"bad\\u0001name"}]}' > "$BATS_TEST_TMPDIR/ctrl.json"
  export FAKE_DEVICES_JSON="$BATS_TEST_TMPDIR/ctrl.json"
  run "$SCRIPT" off
  [ "$status" -ne 0 ]
  grep -q "invalid" "$NOTIFY_CALL_FILE"
  ! grep -q '^eval$' "$HYPRCTL_CALL_FILE"
}

@test "XDG_STATE_HOME is respected; unset falls back to ~/.local/state" {
  export FAKE_DEVICES_JSON="$ONE_TOUCH"
  unset XDG_STATE_HOME
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/state/cyberos/touchscreen-disabled-name" ]
}

@test "an unrecognised argument prints usage and exits non-zero" {
  run "$SCRIPT" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}
