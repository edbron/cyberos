#!/usr/bin/env bats
# cyberos-monitor-arrange: place an external monitor around the internal
# display and set refresh rates, via `hyprctl eval "hl.monitor({...})"`.
# hyprctl is stubbed here -- these tests run with no live Hyprland session,
# on a dev host that may or may not have one. Ported from
# github.com/edbron/omarchy-monitor-placement-refresh-rate's
# bin/omarchy-monitor-arrange with one hardening change: see the script's
# own header for why a monitor `description` (EDID data, not this project's)
# is rejected outright rather than merely escaped if it contains a control
# character.

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/profile/airootfs/usr/local/bin/cyberos-monitor-arrange"
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CYBEROS_MONITORS_LUA="$BATS_TEST_TMPDIR/monitors.lua"

  # Canned two-monitor state: internal eDP-1 (60/40Hz) + external DP-1
  # (144/120/60Hz), DP-1 placed to the right. DESCRIPTION is swapped in by
  # individual tests that need to exercise the injection guard.
  export DESCRIPTION="${DESCRIPTION:-Dell U2723QE}"
  cat > "$BATS_TEST_TMPDIR/bin/hyprctl" <<EOF
#!/bin/bash
if [ "\$1" = "monitors" ]; then
  jq -n --arg d "\$DESCRIPTION" '[
    {name:"eDP-1", description:"BOE NE160WUM-NXA", disabled:false, width:1920, height:1080,
     scale:1, transform:0, x:0, y:0, refreshRate:60.02,
     availableModes:["1920x1080@60.02Hz","1920x1080@40.00Hz"]},
    {name:"DP-1", description: \$d, disabled:false, width:2560, height:1440,
     scale:1, transform:0, x:1920, y:0, refreshRate:144.0,
     availableModes:["2560x1440@144.00Hz","2560x1440@120.00Hz","2560x1440@60.00Hz"]}
  ]'
elif [ "\$1" = "eval" ]; then
  echo "\$2" >> "$BATS_TEST_TMPDIR/hyprctl-eval-calls"
else
  echo "unexpected hyprctl call: \$*" >&2; exit 1
fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/hyprctl"
  : > "$BATS_TEST_TMPDIR/hyprctl-eval-calls"
}

@test "script exists, executable, valid bash" {
  [ -x "$SCRIPT" ]
  bash -n "$SCRIPT"
}

@test "state: reports internal/external monitors and available rates" {
  run bash "$SCRIPT" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.internal == "eDP-1"'
  echo "$output" | jq -e '.externals[0].name == "DP-1"'
  echo "$output" | jq -e '.externals[0].placement == "right"'
  echo "$output" | jq -e '.monitors | length == 2'
  echo "$output" | jq -e '.monitors[1].rates == [144,120,60]'
}

@test "arrange left --dry-run: prints the Lua calls, never touches hyprctl eval" {
  run bash "$SCRIPT" left DP-1 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'hl.monitor({ output = "desc:BOE NE160WUM-NXA"'* ]]
  [[ "$output" == *'hl.monitor({ output = "desc:Dell U2723QE"'* ]]
  [ ! -s "$BATS_TEST_TMPDIR/hyprctl-eval-calls" ]
}

@test "arrange left: applies via hyprctl eval and persists a monitors.lua block" {
  run bash "$SCRIPT" left DP-1
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/hyprctl-eval-calls" ]
  grep -q "cyberos-monitor-arrange: begin" "$CYBEROS_MONITORS_LUA"
  grep -q 'desc:Dell U2723QE' "$CYBEROS_MONITORS_LUA"
}

@test "rate: rejects a rate the monitor doesn't offer at its current resolution" {
  run bash "$SCRIPT" rate DP-1 165 --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not offer"* ]]
}

@test "rate: accepts an offered rate, dry-run never touches hyprctl eval" {
  run bash "$SCRIPT" rate DP-1 120 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'mode = "2560x1440@120"'* ]]
  [ ! -s "$BATS_TEST_TMPDIR/hyprctl-eval-calls" ]
}

@test "a monitor description containing a control character is rejected, never reaches hyprctl eval" {
  DESCRIPTION=$'evil\ndesc"}) hl.dsp.exec_cmd("touch /tmp/pwned") --'
  export DESCRIPTION
  # Re-render the stub with the malicious description baked into $DESCRIPTION
  # at call time (the heredoc above reads it from the environment).
  run bash "$SCRIPT" left DP-1
  [ "$status" -ne 0 ]
  [[ "$output" == *"control character"* ]]
  [ ! -s "$BATS_TEST_TMPDIR/hyprctl-eval-calls" ]
  [ ! -f "$CYBEROS_MONITORS_LUA" ]
}

@test "hyprland.lua dofiles monitors.lua after the base monitor rule, guarded like theme.lua" {
  f="$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"
  grep -q 'pcall(dofile, cfgdir .. "/monitors.lua")' "$f"
  # theme.lua's own guard comes first in the file -- confirms this follows
  # the same "missing file degrades gracefully" shape, not a fresh pattern.
  awk '/theme.lua/{t=NR} /monitors.lua/{m=NR} END{exit !(t && m && t < m)}' "$f"
}

@test "profiledef.sh ships the script executable (mkarchiso strips mode otherwise)" {
  grep -q '\["/usr/local/bin/cyberos-monitor-arrange"\]="0:0:755"' "$ROOT/profile/profiledef.sh"
  mode=$(git -C "$ROOT" ls-files -s profile/airootfs/usr/local/bin/cyberos-monitor-arrange | awk '{print $1}')
  [ "$mode" = "100755" ]
}

@test "popup: PanelWindow, always-active shape (bar chip needs live state while closed), uses Cyber.ClickOutside" {
  f="$QS/popups/MonitorArrange.qml"
  [ -f "$f" ]
  grep -q 'PanelWindow' "$f"
  grep -q 'property bool opened: false' "$f"
  grep -q 'visible: root.opened' "$f"
  grep -q 'Cyber.ClickOutside { onOutsideClicked: root.close() }' "$f"
  grep -qE 'anchors \{ top: true; right: true; left: root\.opened; bottom: root\.opened \}' "$f"
}

@test "popup: no subprocess besides cyberos-monitor-arrange, argv-only" {
  f="$QS/popups/MonitorArrange.qml"
  ! grep -qE 'execDetached|Quickshell\.Process' "$f"
  grep -q '\["cyberos-monitor-arrange", "state"\]' "$f"
  grep -q 'actionProc.exec(\["cyberos-monitor-arrange", direction, root.target.name\])' "$f"
  grep -q 'actionProc.exec(\["cyberos-monitor-arrange", "rate", name, String(hz)\])' "$f"
}

@test "popup: monitor names/labels render as plain text (EDID data this project does not author)" {
  f="$QS/popups/MonitorArrange.qml"
  grep -q 'textFormat: Text.PlainText' "$f"
}

@test "no raw PUA glyph bytes in the new monitor-arrange surfaces (escapes only)" {
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' \
    "$QS/popups/MonitorArrange.qml" "$QS/bar/MonitorChip.qml" "$SCRIPT"
}

@test "bar chip: reads the panel's own state via the bare LazyLoader id, toggles via IPC" {
  f="$QS/bar/MonitorChip.qml"
  [ -f "$f" ]
  grep -q 'monitorArrange.item ? monitorArrange.item.externals.length : 0' "$f"
  grep -qE 'execDetached\(\["qs", "ipc", "call", "monitorarrange", "toggle"\]\)' "$f"
}

@test "Bar.qml wires MonitorChip among the right-side hardware chips" {
  grep -q 'MonitorChip {}' "$QS/bar/Bar.qml"
}

@test "shell.qml: monitorArrange is always-active, IPC target has open/close/toggle" {
  f="$QS/shell.qml"
  awk '/id: monitorArrange/,/^    }/' "$f" | grep -qE 'active:\s*true'
  awk '/target: "monitorarrange"/,/^    }/' "$f" | grep -q 'function open'
  awk '/target: "monitorarrange"/,/^    }/' "$f" | grep -q 'function close'
  awk '/target: "monitorarrange"/,/^    }/' "$f" | grep -q 'function toggle'
}
