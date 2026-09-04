#!/usr/bin/env bats
# System Health: CPU/memory/battery/disk-SMART bar widget, ported from
# DevInBlack001/omarchy-system-health onto this shell's own conventions
# (Cyber.Theme, PanelWindow, shell.qml-owned IpcHandler) rather than
# Omarchy's Panel/qs.Ui/qs.Commons base classes, which this project does not
# depend on.

ROOT="$BATS_TEST_DIRNAME/.."
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"
SCRIPT="$ROOT/profile/airootfs/usr/local/bin/cyberos-systemhealth-state"

@test "data script exists, executable, valid Python" {
  [ -x "$SCRIPT" ]
  python3 -c "import ast; ast.parse(open('$SCRIPT').read())"
}

@test "data script: read-only, no root/sudo, no polkit (comments aside)" {
  # Strip comment lines first: the header comment itself says "no sudo" in
  # prose, which a bare word match would misfire on.
  ! grep -v '^\s*#' "$SCRIPT" | grep -qE '\bsudo\b|\bpkexec\b|SmartSelftestStart|EraseFreeSpace'
}

@test "data script: every subprocess/file read is byte- and time-bounded" {
  grep -q 'MAX_READ_BYTES' "$SCRIPT"
  grep -q 'MAX_SUBPROCESS_BYTES' "$SCRIPT"
  grep -q 'MAX_DISKS' "$SCRIPT"
  grep -q 'MAX_WARNINGS' "$SCRIPT"
  grep -qE 'timeout=' "$SCRIPT"
  grep -q 'os.set_blocking' "$SCRIPT"
}

@test "data script: no shell=True, no shell string composition -- subprocess calls are argv lists" {
  # A "!"-negated command is exempt from errexit no matter its position, so
  # only the function's LAST statement actually decides a bats pass/fail --
  # an earlier failing "! grep" is silently swallowed, not reported. `run` +
  # an explicit status check is used for all three so each one actually gates.
  run grep -qE 'shell\s*=\s*True' "$SCRIPT"
  [ "$status" -ne 0 ]
  run grep -qE 'os\.system|os\.popen' "$SCRIPT"
  [ "$status" -ne 0 ]
  # Popen/run always take a Python list literal (argv), never an f-string
  # or %-formatted command line.
  run grep -qE 'Popen\(f["'"'"']|run\(f["'"'"']' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "data script: one bad section degrades that section, not the whole payload" {
  grep -q 'def safe(' "$SCRIPT"
  grep -q 'safe(battery)' "$SCRIPT"
  grep -q 'safe(cpu)' "$SCRIPT"
  grep -q 'safe(memory)' "$SCRIPT"
  grep -q 'safe(disks' "$SCRIPT"
}

@test "data script runs for real on this host and produces well-formed JSON" {
  run python3 "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert set(d.keys()) >= {'cpu','memory','battery','disks'}"
}

@test "Model.js is vendored, pure JS (no QML/Quickshell imports), and exports the panel's formatters" {
  f="$QS/popups/SystemHealthModel.js"
  [ -f "$f" ]
  # "!"-negated commands are exempt from errexit regardless of position, so
  # this must not sit ahead of other assertions in the body -- run + an
  # explicit status check instead of relying on it being last.
  run grep -qE '^import ' "$f"
  [ "$status" -ne 0 ]
  grep -q 'function summarize' "$f"
  grep -q 'function cpuStatus' "$f"
  grep -q 'function memoryStatus' "$f"
  grep -q 'function batteryStatus' "$f"
  grep -q 'function diskStatus' "$f"
}

@test "panel: PanelWindow, own IpcHandler removed in favour of shell.qml's, payload capped, argv-only Process" {
  f="$QS/popups/SystemHealth.qml"
  grep -q 'PanelWindow' "$f"
  grep -qE 'command:\s*\["cyberos-systemhealth-state"\]' "$f"
  grep -q 'maxPayloadBytes' "$f"
  grep -q 'utf8ByteLength' "$f"
  # No embedded IpcHandler -- shell.qml owns the "systemhealth" target,
  # matching every other popup in this shell (Calc/WifiPanel/Mixer/...).
  ! grep -q 'IpcHandler' "$f"
}

@test "panel: CPU model, disk model/device, and process names render as plain text (data this project does not author)" {
  f="$QS/popups/SystemHealth.qml"
  awk '/text: root\.cpu \? root\.cpu\.model/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
  awk '/text: \(diskCard\.modelData\.model/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
  awk '/k: modelData\.name/,/^ *}/' "$f" | grep -qE 'k:|v:' # KeyValueRow itself is PlainText, checked below
  awk '/component KeyValueRow:/,/^    }/' "$f" | grep -q 'textFormat: Text.PlainText'
  awk '/component StatRow:/,/^    }/' "$f" | grep -q 'textFormat: Text.PlainText'
}

@test "bar chip: microchip glyph is a \\u escape (no raw PUA byte), colours by overallStatus, toggles via IPC" {
  f="$QS/bar/SystemHealthChip.qml"
  grep -qE 'icon:\s*"\\uf2db"' "$f"
  grep -q 'overallStatus' "$f"
  grep -qE 'execDetached\(\["qs", "ipc", "call", "systemhealth", "toggle"\]\)' "$f"
}

@test "Bar.qml wires SystemHealthChip in with the other hardware-status chips" {
  grep -q 'SystemHealthChip {}' "$QS/bar/Bar.qml"
}

@test "shell.qml: systemhealth is always-active (unlike the toggle-on-open popups), not activeAsync" {
  f="$QS/shell.qml"
  awk '/id: systemhealth/,/^    }/' "$f" | grep -qE 'active:\s*true'
  awk '/target: "systemhealth"/,/^    }/' "$f" | grep -q 'function open'
  awk '/target: "systemhealth"/,/^    }/' "$f" | grep -q 'function close'
  awk '/target: "systemhealth"/,/^    }/' "$f" | grep -q 'function toggle'
}

@test "packages: lm_sensors (CPU temp), python, udisks2 all present" {
  PKGS="$ROOT/profile/packages.x86_64"
  pkg_listed() { sed 's/#.*//' "$PKGS" | tr -d ' ' | grep -v '^$' | grep -qx "$1"; }
  pkg_listed "lm_sensors"
  pkg_listed "python"
  pkg_listed "udisks2"
}

@test "no raw PUA glyph bytes in the new System Health surfaces (escapes only)" {
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$QS/popups/SystemHealth.qml" "$QS/bar/SystemHealthChip.qml"
}
