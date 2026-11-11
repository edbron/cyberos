#!/usr/bin/env bats
# cyberos-cloud-drives: connect Google Drive/OneDrive/iCloud Drive as
# folders under ~/Cloud via rclone, with the config-encryption secret held
# only in the login keyring. rclone/secret-tool/gum/systemctl are stubbed
# here -- these tests run with none of those actually configured, on a dev
# host that may or may not have them. Ported from
# github.com/edbron/omarchy-cloud-drives's bin/omarchy-cloud-drives,
# reviewed in full and found already sound; see the script's own header for
# the three places it had to diverge from the Omarchy-specific original.

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/profile/airootfs/usr/local/bin/cyberos-cloud-drives"
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CYBEROS_CLOUD_ROOT="$HOME/Cloud"

  # rclone: reports one configured remote (GoogleDrive) by default. Tests
  # that need "nothing configured" override REMOTES before calling.
  export REMOTES="${REMOTES:-GoogleDrive}"
  cat > "$BATS_TEST_TMPDIR/bin/rclone" <<'EOF'
#!/bin/bash
case "$1" in
  listremotes) [ -n "$REMOTES" ] && printf '%s\n' $REMOTES | sed 's/$/:/' ;;
  config)
    case "$2" in
      encryption) [ "${ENCRYPTED:-0}" = "1" ] && exit 0 || exit 1 ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/rclone"

  # secret-tool: a tiny in-memory store keyed on the full attribute list.
  cat > "$BATS_TEST_TMPDIR/bin/secret-tool" <<EOF
#!/bin/bash
STORE="$BATS_TEST_TMPDIR/secret-store"
case "\$1" in
  store) mkdir -p "\$STORE"; cat > "\$STORE/\${*: -4}" ;;
  lookup) [ "\${SECRET_TOOL_FAIL:-0}" = "1" ] && exit 1; f="\$STORE/\${*: -4}"; [ -f "\$f" ] && cat "\$f" || exit 1 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/secret-tool"

  cat > "$BATS_TEST_TMPDIR/bin/mountpoint" <<'EOF'
#!/bin/bash
exit "${MOUNTPOINT_STATUS:-1}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/mountpoint"

  cat > "$BATS_TEST_TMPDIR/bin/systemctl" <<'EOF'
#!/bin/bash
[ "$1" = "--user" ] || exit 0
case "$2" in
  is-active) exit "${SYSTEMCTL_ACTIVE:-1}" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/systemctl"

  cat > "$BATS_TEST_TMPDIR/bin/gum" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/gum"
}

@test "script exists, executable, valid bash" {
  [ -x "$SCRIPT" ]
  bash -n "$SCRIPT"
}

@test "state: reports one configured provider, two unconfigured, no crash without a keyring" {
  export SECRET_TOOL_FAIL=1
  run bash "$SCRIPT" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rclone == true'
  echo "$output" | jq -e '.keyring == false'
  echo "$output" | jq -e '.providers | length == 3'
  echo "$output" | jq -e '.providers[0].id == "google" and .providers[0].configured == true'
  echo "$output" | jq -e '.providers[1].configured == false and .providers[2].configured == false'
}

@test "state: mounted/active reflect the live mountpoint/systemctl checks, not just 'configured'" {
  export MOUNTPOINT_STATUS=0 SYSTEMCTL_ACTIVE=0
  run bash "$SCRIPT" state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers[0].mounted == true and .providers[0].active == true'
}

@test "ensure_rclone fails clearly when rclone/fuse3 are missing, no lazy-install attempted" {
  rm -f "$BATS_TEST_TMPDIR/bin/rclone"
  source <(sed -n '/^ensure_rclone()/,/^}/p' "$SCRIPT")
  source <(sed -n '/^fail()/,/^}/p' "$SCRIPT")
  source <(sed -n '/^have_rclone()/,/^}/p' "$SCRIPT")
  run ensure_rclone
  [ "$status" -ne 0 ]
  [[ "$output" == *"rclone/fuse3 not found"* ]]
  ! grep -v '^#' "$SCRIPT" | grep -q "omarchy-pkg-add"
}

@test "create_private_file refuses to write through an existing symlink" {
  source <(sed -n '/^create_private_file()/,/^}/p' "$SCRIPT")
  fail() { echo "FAIL: $*" >&2; return 1; }
  target="$BATS_TEST_TMPDIR/real-secret-target"
  link="$BATS_TEST_TMPDIR/planted-link"
  printf 'pre-existing content' > "$target"
  ln -s "$target" "$link"
  run create_private_file "$link"
  [ "$status" -ne 0 ]
  # The symlink itself, and what it points to, are both untouched.
  [ -L "$link" ]
  [ "$(cat "$target")" = "pre-existing content" ]
}

@test "write_file replaces (not writes through) an existing symlink at the destination" {
  source <(sed -n '/^write_file()/,/^}/p' "$SCRIPT")
  fail() { echo "FAIL: $*" >&2; return 1; }
  target="$BATS_TEST_TMPDIR/real-unit-target"
  link="$BATS_TEST_TMPDIR/planted-unit-link"
  printf 'attacker content' > "$target"
  ln -s "$target" "$link"
  echo "legit content" | write_file "$link" 0644
  [ ! -L "$link" ]
  [ "$(cat "$link")" = "legit content" ]
  [ "$(cat "$target")" = "attacker content" ]
}

@test "no elevated privileges, no plaintext credentials in any subprocess argv" {
  ! grep -qE '\bsudo\b|\bpkexec\b' "$SCRIPT"
  # The Apple ID password only ever appears as a local shell variable name
  # ($pw / $2 in rc_configure_icloud), never inlined into a command array.
  ! grep -qE '\[".*\$pw.*"\]|\[".*apple_id.*password.*"\]' "$SCRIPT"
}

@test "iCloud password goes over the private rc socket, never argv: rc_call is the only network call, curl gets it via stdin" {
  grep -q 'rc_call() {' "$SCRIPT"
  grep -qE '\-\-data-binary @-' "$SCRIPT"
  grep -q '\-\-unix-socket "\$RC_DIR/rc.sock"' "$SCRIPT"
  # rc_start's own socket directory is created with a private umask.
  grep -qE 'umask 077; mktemp -d' "$SCRIPT"
}

@test "cmd_launch: floating terminal via this project's own foot pattern, args %q-quoted before bash -c" {
  grep -q 'foot --app-id=cyberos-cloud-drives' "$SCRIPT"
  grep -qE "printf '%q ' \"\\\$@\"" "$SCRIPT"
  # Only mentioned in the header's explanatory prose (what this diverges
  # from), never as an actual command -- strip comment lines first.
  ! grep -v '^#' "$SCRIPT" | grep -q "omarchy-launch-floating-terminal-with-presentation"
}

@test "cmd_open uses plain xdg-open, not Omarchy's uwsm-app" {
  grep -q 'setsid xdg-open "\$dir"' "$SCRIPT"
  ! grep -v '^#' "$SCRIPT" | grep -q "uwsm-app"
}

@test "the systemd unit is generated inline, not copied from a bundled plugin directory" {
  grep -q 'write_file "\$UNIT_DIR/\${UNIT_NAME}.service" 0644 <<UNIT' "$SCRIPT"
  ! grep -q "PLUGIN_DIR" "$SCRIPT"
  # Sandboxing tradeoffs (fusermount3 needs setuid + no mount-namespace) are
  # carried over from the upstream unit's own commentary, not dropped.
  grep -qi "fusermount3 is setuid root" "$SCRIPT"
}

@test "no raw PUA glyph bytes anywhere in the new Cloud Drives surfaces (escapes only)" {
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' \
    "$QS/popups/CloudDrives.qml" "$QS/bar/CloudDrivesChip.qml" "$SCRIPT"
}

@test "packages.x86_64: rclone, fuse3, gum, libsecret, gnome-keyring are all base packages" {
  for p in rclone fuse3 gum libsecret gnome-keyring; do
    grep -qx "$p" "$ROOT/profile/packages.x86_64"
  done
  # uwsm was dropped along with the uwsm-app usage above -- not a base
  # package this feature needs.
  ! grep -qx "uwsm" "$ROOT/profile/packages.x86_64"
}

@test "hyprland.lua: gnome-keyring autostarted (secrets component only), float-cloud-drives window rule present" {
  f="$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"
  grep -q 'gnome-keyring-daemon --start --components=secrets' "$f"
  grep -qE 'hl\.window_rule\(\{ name = "float-cloud-drives"' "$f"
}

@test "profiledef.sh ships the script executable (mkarchiso strips mode otherwise)" {
  grep -q '\["/usr/local/bin/cyberos-cloud-drives"\]="0:0:755"' "$ROOT/profile/profiledef.sh"
  mode=$(git -C "$ROOT" ls-files -s profile/airootfs/usr/local/bin/cyberos-cloud-drives | awk '{print $1}')
  [ "$mode" = "100755" ]
}

@test "popup: PanelWindow, always-active shape (bar chip needs live state while closed), uses Cyber.ClickOutside" {
  f="$QS/popups/CloudDrives.qml"
  [ -f "$f" ]
  grep -q 'PanelWindow' "$f"
  grep -q 'property bool opened: false' "$f"
  grep -q 'visible: root.opened' "$f"
  grep -q 'Cyber.ClickOutside { onOutsideClicked: root.close() }' "$f"
  grep -qE 'anchors \{ top: true; right: true; left: root\.opened; bottom: root\.opened \}' "$f"
}

@test "popup: connect/disconnect launch a floating terminal and close, mount/unmount/open stay in-panel" {
  f="$QS/popups/CloudDrives.qml"
  grep -q 'execDetached(\["cyberos-cloud-drives", "launch", action, id\])' "$f"
  grep -q 'root.close();' "$f"
  grep -q 'actionProc.exec(\["cyberos-cloud-drives", action, id\])' "$f"
}

@test "popup: provider names/paths render as plain text (data this project does not author)" {
  grep -q 'textFormat: Text.PlainText' "$QS/popups/CloudDrives.qml"
}

@test "popup and MonitorArrange share Cyber.Pill instead of two copies of the same component" {
  grep -q 'Cyber.Pill {' "$QS/popups/CloudDrives.qml"
  grep -q 'Cyber.Pill {' "$QS/popups/MonitorArrange.qml"
  ! grep -q 'component Pill:' "$QS/popups/MonitorArrange.qml" "$QS/popups/CloudDrives.qml"
  grep -q 'Pill Pill.qml' "$QS/qmldir"
}

@test "bar chip: reads the panel's own state via the bare LazyLoader id, toggles via IPC" {
  f="$QS/bar/CloudDrivesChip.qml"
  [ -f "$f" ]
  grep -q 'cloudDrives.item ? cloudDrives.item.mountedCount : 0' "$f"
  grep -qE 'execDetached\(\["qs", "ipc", "call", "clouddrives", "toggle"\]\)' "$f"
}

@test "Bar.qml wires CloudDrivesChip among the right-side hardware chips" {
  grep -q 'CloudDrivesChip {}' "$QS/bar/Bar.qml"
}

@test "shell.qml: cloudDrives is always-active, IPC target has open/close/toggle" {
  f="$QS/shell.qml"
  awk '/id: cloudDrives/,/^    }/' "$f" | grep -qE 'active:\s*true'
  awk '/target: "clouddrives"/,/^    }/' "$f" | grep -q 'function open'
  awk '/target: "clouddrives"/,/^    }/' "$f" | grep -q 'function close'
  awk '/target: "clouddrives"/,/^    }/' "$f" | grep -q 'function toggle'
}
