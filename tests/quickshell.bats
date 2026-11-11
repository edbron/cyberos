#!/usr/bin/env bats
ROOT="$BATS_TEST_DIRNAME/.."
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"
QMLLINT=/usr/lib/qt6/bin/qmllint

@test "every QML file parses (qmllint; skips if absent)" {
  [ -x "$QMLLINT" ] || skip "qmllint not installed"
  find "$QS" -name '*.qml' -print0 | xargs -0 -n1 "$QMLLINT" --bare
}

@test "no raw private-use glyphs in any QML file -- \\uXXXX escapes only" {
  # PUA bytes are invisible in tool output; the waybar config lost 23 once.
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$QS" --include='*.qml'
}

@test "no hex colours outside Theme.qml" {
  # Catches #RGB, #ARGB, #RRGGBB, #AARRGGBB in either quote style -- not just
  # the 6-digit double-quoted form (a single-quoted or shorthand hex literal
  # slipped past this test before it was tightened).
  run grep -rlE "['\"]#[0-9A-Fa-f]{3,8}" "$QS" --include='*.qml'
  [ "$output" = "$QS/Theme.qml" ] || [ -z "$output" ]
}

@test "the bar chips all go through Theme" {
  for f in Bar BarModule ClockChip WindowTitle; do
    grep -q 'Theme\.' "$QS/bar/$f.qml"
  done
}

@test "shell.qml hosts one bar per screen and the three popup loaders" {
  grep -q 'Variants' "$QS/shell.qml"
  grep -q 'Quickshell.screens' "$QS/shell.qml"
  for id in powerMenu launcher osd; do grep -q "$id" "$QS/shell.qml"; done
}

@test "workspaces: 5 persistent, activate on click, Hyprland-driven" {
  grep -q 'Hyprland.workspaces' "$QS/bar/Workspaces.qml"
  grep -q 'activate()' "$QS/bar/Workspaces.qml"
  grep -qE 'persistent|for.*1.*5|range' "$QS/bar/Workspaces.qml"
}

@test "audio: pipewire sink with tracker, click/right-click/scroll behaviours" {
  grep -q 'Pipewire.defaultAudioSink' "$QS/bar/Audio.qml"
  grep -q 'PwObjectTracker' "$QS/bar/Audio.qml"
  grep -q '"mixer", "toggle"' "$QS/bar/Audio.qml"
}

@test "battery: hidden on desktops, warn/critical colours from Theme" {
  grep -q 'isLaptopBattery' "$QS/bar/Battery.qml"
  grep -q 'Theme.alert' "$QS/bar/Battery.qml"
}

@test "install button only exists on the live ISO" {
  grep -q '/run/archiso' "$QS/bar/InstallButton.qml"
  grep -q 'cyberos-install' "$QS/bar/InstallButton.qml"
}

@test "parity: every waybar right-side module has a quickshell counterpart" {
  # Brightness has no chip: the XF86 keys drive the OSD directly, and the
  # half-circle brightness glyph read as a stray moon in the bar.
  for f in Tray.qml BluetoothChip.qml Audio.qml Network.qml SysStats.qml Battery.qml ClockChip.qml; do
    [ -f "$QS/bar/$f" ]
  done
}

@test "brightness has no bar chip; the XF86 keys drive the OSD instead" {
  [ ! -f "$QS/bar/Brightness.qml" ]
  grep -q 'brightnessctl' "$QS/shell.qml"
  grep -q 'function brightnessUp' "$QS/shell.qml"
  grep -q 'function brightnessDown' "$QS/shell.qml"
}

@test "bar: Tray is followed directly by BluetoothChip (brightness chip removed)" {
  awk '/RowLayout {/{f++} f==2 && /Tray|Brightness|BluetoothChip/{print; if (/BluetoothChip/) exit}' "$QS/bar/Bar.qml" \
    | tr -d ' \t\n' | grep -q 'Tray{}BluetoothChip{}'
}

@test "power menu replaces the rofi script, plus sleep/hibernate" {
  [ ! -e "$ROOT/profile/airootfs/etc/skel/.config/rofi/powermenu.sh" ]
  # run-wrapped: a mid-body "!" is exempt from errexit and would be silently
  # swallowed by the loop/grep that follows.
  run grep -q 'powermenu.sh' "$ROOT/profile/profiledef.sh"
  [ "$status" -ne 0 ]
  for a in hyprlock 'systemctl.*suspend' 'hl.dsp.exit' 'systemctl.*reboot' 'systemctl.*poweroff'; do
    grep -qE "$a" "$QS/power/PowerMenu.qml"
  done
  grep -q '"power"' "$QS/shell.qml"   # ipc target
}

@test "hibernate is offered only when swap can actually hold RAM, checked live not assumed" {
  f="$QS/power/PowerMenu.qml"
  grep -q '/proc/meminfo' "$f"
  grep -q 'MemTotal' "$f"
  grep -q 'SwapTotal' "$f"
  # Gate is swap >= mem, not just "swap exists" -- a small swapfile/zram
  # would silently fail or corrupt state mid-hibernate otherwise.
  grep -q 'hibernateOk: root.swapKb > 0 && root.swapKb >= root.memKb' "$f"
  grep -qE 'systemctl.*hibernate' "$f"
  grep -q 'root.hibernateOk' "$f"
  implicit=$(grep -c 'height: 20 + root.actions.length \* 50' "$f")
  [ "$implicit" -eq 1 ]   # row count drives panel height, not a fixed constant
}

@test "click-outside-to-close: every popup uses Cyber.ClickOutside behind a self-contained content box" {
  # One shared mechanism (ClickOutside.qml, quickshell root, registered in
  # qmldir) instead of N copies of the same background MouseArea and the
  # same "does the content box eat its own clicks" reasoning duplicated
  # across every popup.
  grep -q 'ClickOutside ClickOutside.qml' "$QS/qmldir"
  grep -q 'signal outsideClicked()' "$QS/ClickOutside.qml"

  for f in "$QS/popups/BluetoothPanel.qml" "$QS/popups/WifiPanel.qml" \
           "$QS/popups/Mixer.qml" "$QS/popups/PowerPanel.qml" \
           "$QS/popups/MusicFlow.qml" "$QS/popups/SystemHealth.qml" \
           "$QS/popups/Calc.qml" "$QS/popups/ClipHist.qml" \
           "$QS/popups/EmojiPicker.qml" "$QS/popups/WinSwitch.qml" \
           "$QS/power/PowerMenu.qml" "$QS/launcher/Launcher.qml"; do
    grep -q 'Cyber.ClickOutside {' "$f"
    grep -q 'onOutsideClicked: root.close' "$f"   # closeRequested() or close()
    # Content box swallows its own clicks -- without this a click on blank
    # space inside the popup would fall through to ClickOutside behind it
    # and close the popup it landed inside.
    grep -q 'MouseArea { anchors.fill: parent }' "$f"
    # The content box is explicitly sized/positioned now, not `anchors.fill:
    # parent` against a window that (for most of these) is fullscreen --
    # that would silently expand the visible popup to cover the whole screen.
    grep -qE '^\s+(width: [0-9]+|height: [0-9]+|height: 20 \+ root\.actions\.length)' "$f"
  done
}

@test "click-outside-to-close: MusicFlow and SystemHealth stay small (not fullscreen) while closed" {
  # Both are always-loaded (LazyLoader active: true, never destroyed) --
  # unlike every other popup here, they cannot simply be fullscreen
  # unconditionally, or a "closed" panel would sit over the whole desktop
  # as an invisible click-blocker forever. right/bottom (or left/bottom)
  # only join top/left (or top/right) once root.opened is true.
  grep -q 'anchors { top: true; left: true; right: root.opened; bottom: root.opened }' "$QS/popups/MusicFlow.qml"
  grep -q 'anchors { top: true; right: true; left: root.opened; bottom: root.opened }' "$QS/popups/SystemHealth.qml"
}

@test "osd handles the five ipc functions and swayosd is gone" {
  for fn in volumeUp volumeDown volumeMute brightnessUp brightnessDown; do
    grep -q "function $fn" "$QS/shell.qml"
  done
  # hyprland.lua legitimately carries an explanatory "-- swayosd is gone --"
  # migration comment (line ~152); exclude comment-only lines so this checks
  # for LIVE references only, same comment-aware philosophy as the
  # complete-removal gate in surfaces2.bats. Fixing the previously-swallowed
  # "!" here (it used to be followed by a passing statement) surfaced this:
  # the raw "! grep -rq 'swayosd' ..." check, run for real, was matching
  # that comment and would have false-failed once un-swallowed.
  run bash -c "grep -n 'swayosd' '$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua' | grep -vE '^[0-9]+:[[:space:]]*--'"
  [ -z "$output" ]
  run grep -qE '^swayosd$' "$ROOT/profile/packages.x86_64"
  [ "$status" -ne 0 ]
  grep -q 'qs ipc call osd' "$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"
}

@test "osd: bottom panel with progress fill and hide timer, theme-coloured" {
  grep -q 'PanelWindow' "$QS/osd/Osd.qml"
  grep -q 'bottom: true' "$QS/osd/Osd.qml"
  grep -q 'Timer' "$QS/osd/Osd.qml"
  grep -q 'Theme\.' "$QS/osd/Osd.qml"
}

@test "osd: volume adjusts pipewire, brightness shells out to brightnessctl" {
  grep -q 'Pipewire.defaultAudioSink' "$QS/shell.qml"
  grep -q 'brightnessctl' "$QS/shell.qml"
}

@test "launcher is DesktopEntries-driven and bound to Super+D" {
  grep -q 'DesktopEntries' "$QS/launcher/Launcher.qml"
  grep -q '"launcher"' "$QS/shell.qml"
  grep -q 'qs ipc call launcher toggle' "$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"
  # merged into one alternation, sole/last statement -- see the mako-check
  # comment in surfaces2.bats for why a mid-body "!" can't be trusted.
  ! grep -qE 'rofi -show drun|rofi -show calc' "$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"  # calc became a quickshell surface in Task 4; see tests/surfaces2.bats
}

@test "launcher: centred focusable panel, ListView + filter, noDisplay excluded" {
  grep -q 'PanelWindow' "$QS/launcher/Launcher.qml"
  grep -q 'focusable: true' "$QS/launcher/Launcher.qml"
  grep -q 'ListView' "$QS/launcher/Launcher.qml"
  grep -q 'noDisplay' "$QS/launcher/Launcher.qml"
  grep -q 'execute()' "$QS/launcher/Launcher.qml"
  grep -q 'closeRequested' "$QS/launcher/Launcher.qml"
}

@test "launcher: minimal TUI list -- sharp corners, accent border, app name is plain text" {
  f="$QS/launcher/Launcher.qml"
  grep -qE 'radius:\s*0' "$f"
  grep -qE 'border\.color:\s*Cyber\.Theme\.accent' "$f"
  grep -q 'ObjectComparison.Identity' "$f"
  grep -qE 'text: cell\.modelData\.name' "$f"
  awk '/text: cell\.modelData\.name/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
}

@test "launcher: categories switch by keyboard (Left/Right only), not mouse scroll" {
  f="$QS/launcher/Launcher.qml"
  grep -q 'function cycleGroup' "$f"
  grep -qE 'case Qt\.Key_Right:' "$f"
  grep -qE 'case Qt\.Key_Left:' "$f"
  grep -q 'root.cycleGroup(1)' "$f"
  grep -q 'root.cycleGroup(-1)' "$f"
  # Gated on apps mode -- Left/Right do nothing in files mode, where
  # there's no category strip to move through.
  grep -q 'if (root.mode === "apps") { root.cycleGroup(1)' "$f"
  grep -q 'if (root.mode === "apps") { root.cycleGroup(-1)' "$f"
  # No wheel/drag path -- catList only moves in response to activeGroup,
  # driven by the key handler above. "!"-negated commands are exempt from
  # errexit regardless of position, so this can't just sit ahead of the
  # next two assertions -- run + an explicit status check instead.
  run grep -q 'WheelHandler' "$f"
  [ "$status" -ne 0 ]
  grep -qE 'interactive:\s*false' "$f"
  grep -q 'positionViewAtIndex' "$f"
}

@test "launcher: Tab/Backtab switch apps/files mode, not categories" {
  f="$QS/launcher/Launcher.qml"
  grep -q 'property string mode: "apps"' "$f"
  grep -q 'function setMode' "$f"
  grep -q 'function toggleMode' "$f"
  awk '/case Qt\.Key_Tab:/,/break;/' "$f" | grep -q 'root.toggleMode()'
  awk '/case Qt\.Key_Backtab:/,/break;/' "$f" | grep -q 'root.toggleMode()'
  # The segmented indicator: both segments present, bracket-highlighted
  # like the category chips, and clickable via root.setMode.
  grep -q '"\[Apps\]"' "$f"
  grep -q '"\[Files\]"' "$f"
  grep -q 'root.setMode("apps")' "$f"
  grep -q 'root.setMode("files")' "$f"
}

@test "launcher: files mode -- fd search is argv-only, fixed-string, bounded, no symlink following" {
  f="$QS/launcher/Launcher.qml"
  grep -qE '\["fd", "-i", "-F", "-H", "-a", "-t", "f",' "$f"
  grep -q '"--max-results", "40"' "$f"
  # -- before the query: a query starting with '-' is never parsed as a flag.
  grep -qE '"--", q,' "$f"
  grep -qE 'root\.usrRoot, root\.etcRoot, root\.varRoot, root\.homeRoot' "$f"
  grep -q 'usrRoot: "/usr"' "$f"
  grep -q 'Quickshell.env("HOME")' "$f"
  # No -L/--follow outside of comments -- fd must not traverse a symlink out
  # of any search root. Comments stripped first: the explanatory comment
  # right above this test's own source (and in Launcher.qml itself) says
  # "No -L/--follow" in prose, which a bare match would misfire on.
  # "!"-negated commands are exempt from errexit regardless of position, so
  # this can't just sit ahead of the next assertion -- run + an explicit
  # status check instead.
  run bash -c "grep -v '^\s*//' '$f' | grep -qE -- '-L\b|--follow'"
  [ "$status" -ne 0 ]
  # Client-side bound too, independent of --max-results.
  grep -q '.slice(0, 40)' "$f"
}

@test "launcher: files mode -- scope covers /etc, /var, and hidden dirs under \$HOME (~/.config)" {
  f="$QS/launcher/Launcher.qml"
  grep -q 'etcRoot: "/etc"' "$f"
  grep -q 'varRoot: "/var"' "$f"
  # -H is what actually reaches ~/.config: fd skips dotdirs without it.
  grep -qE '\["fd", "-i", "-F", "-H",' "$f"
  grep -q '/usr, /etc, /var, ~' "$f"
}

@test "launcher: files mode -- two-char floor, debounced, stale searches can't clobber fresh results" {
  f="$QS/launcher/Launcher.qml"
  grep -q 'interval: 150' "$f"
  grep -q 'fileSearchDebounce.restart()' "$f"
  grep -q 'q.length < 2' "$f"
  # Generation guard: each run is tagged, the result handler drops anything
  # that isn't the current generation.
  grep -q 'property int searchGen: 0' "$f"
  grep -q 'property int forGen: -1' "$f"
  grep -q 'if (fileSearchProc.forGen !== root.searchGen) return;' "$f"
}

@test "launcher: files mode -- results open via xdg-open, names/paths render as plain text" {
  f="$QS/launcher/Launcher.qml"
  grep -q 'Quickshell.execDetached(\["xdg-open", root.fileResults\[index\]\])' "$f"
  awk '/text: fcell\.baseName/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
  awk '/text: fcell\.dirName/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
  # A pathological filename elides instead of pushing dirName off the row.
  grep -q 'Layout.maximumWidth: 180' "$f"
}

@test "bar: apps chip is the first left module, toggles the launcher" {
  grep -q 'launcher.activeAsync = true' "$QS/bar/Bar.qml"
  grep -q 'tooltip: "Applications"' "$QS/bar/Bar.qml"
  # must precede InstallButton -- first module in the left RowLayout
  awk '/RowLayout {/{f=1} f && /Applications|InstallButton/{print; if (/InstallButton/) exit}' "$QS/bar/Bar.qml" \
    | head -1 | grep -q 'Applications'
}

@test "widget host isolates failures and loads alphabetically" {
  grep -q 'FolderListModel\|folder' "$QS/bar/WidgetHost.qml"
  grep -qE 'Loader' "$QS/bar/WidgetHost.qml"
  [ -f "$QS/widgets/00-example-uptime.qml" ]
  [ -f "$QS/widgets/README.md" ]
}

@test "waybar and swayosd are fully gone; quickshell ships" {
  [ ! -d "$ROOT/profile/airootfs/etc/skel/.config/waybar" ]
  run grep -qE '^waybar$' "$ROOT/profile/packages.x86_64"
  [ "$status" -ne 0 ]
  run grep -qE '^swayosd$' "$ROOT/profile/packages.x86_64"
  [ "$status" -ne 0 ]
  grep -qE '^quickshell$' "$ROOT/profile/packages.x86_64"
  grep -q 'exec_cmd("qs")' "$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"
  run grep -q 'waybar' "$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"
  [ "$status" -ne 0 ]
  ! grep -q 'waybar' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
}

@test "qmldir registers both Theme and OsdState as singletons" {
  grep -q 'singleton Theme' "$QS/qmldir"
  grep -q 'singleton OsdState' "$QS/qmldir"
}

# C1: Quickshell.env() returns "" (empty string), never null/undefined, so a
# `!== ""` guard is *always* true and the HOME fallback branch is dead code.
# With XDG_CONFIG_HOME unset (the CyberOS default), Theme.qml and
# WidgetHost.qml both silently resolved to "" + "/quickshell/..." -- a
# relative path under the qs process's CWD -- instead of $HOME/.config.
# bats cannot run qs itself, so this is a static (belt-and-braces) check on
# top of the live smoke-test verification in the report.
@test "C1: no XDG_CONFIG_HOME truthiness bug in Theme.qml / WidgetHost.qml" {
  # single grep across both files (sole/last statement) instead of two
  # separate "!" checks -- absence-in-either is equivalent to absence-in-both
  # for a negated presence check, and avoids the mid-body "!" swallow bug.
  ! grep -q 'env("XDG_CONFIG_HOME") !== ' "$QS/Theme.qml" "$QS/bar/WidgetHost.qml"
}

@test "C1: cyberos-theme writes theme.json under \$HOME/.config with no XDG_CONFIG_HOME" {
  run env -u XDG_CONFIG_HOME HOME="$BATS_TEST_TMPDIR/home" \
    bash "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme" dark
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/home/.config/quickshell/theme.json" ]
}

@test "Theme.qml reloads on fileChanged -- watchChanges alone never re-reads" {
  # Found in the Task 8 VM pass: without onFileChanged: reload() the shell
  # keeps its login-time palette and the live re-theme contract is dead.
  grep -q 'onFileChanged: reload()' "$QS/Theme.qml"
}

# Security: Text's default textFormat (AutoText) auto-detects and renders
# HTML-like content. BarModule's label carries MPRIS track metadata and
# WindowTitle carries a window's own title -- both set by something this
# desktop does not control -- so either could otherwise inject markup into
# the system bar.
@test "bar chip label/icon and the window title are rendered as plain text" {
  grep -q 'textFormat: Text.PlainText' "$QS/bar/WindowTitle.qml"
  awk '/text: chip\.label/,/^ *}/' "$QS/bar/BarModule.qml" | grep -q 'textFormat: Text.PlainText'
}

@test "wifi panel replaces nm-applet: surface, ipc target, chip click" {
  [ -f "$QS/popups/WifiPanel.qml" ]
  grep -q 'Quickshell.Networking' "$QS/popups/WifiPanel.qml"
  grep -q 'connectWithPsk' "$QS/popups/WifiPanel.qml"
  grep -q 'scannerEnabled' "$QS/popups/WifiPanel.qml"
  grep -q 'target: "wifi"' "$QS/shell.qml"
  grep -q 'qs ipc call wifi toggle\|"wifi", "toggle"' "$QS/bar/Network.qml"
  run grep 'nm-connection-editor' "$QS/bar/Network.qml"
  [ "$status" -ne 0 ]
}

@test "bluetooth panel replaces blueman: surface, ipc target, chip click" {
  [ -f "$QS/popups/BluetoothPanel.qml" ]
  grep -q 'Quickshell.Bluetooth' "$QS/popups/BluetoothPanel.qml"
  grep -q 'pair()' "$QS/popups/BluetoothPanel.qml"
  grep -q 'target: "bt"' "$QS/shell.qml"
  grep -q '"bt", "toggle"' "$QS/bar/BluetoothChip.qml"
  run grep 'blueman' "$QS/bar/BluetoothChip.qml"
  [ "$status" -ne 0 ]
}

@test "no GTK app launch paths remain anywhere in the shell" {
  run grep -RE 'execDetached\(\["(gtk-launch|blueman|nm-applet|nm-connection-editor|pavucontrol")' "$QS"
  [ "$status" -ne 0 ]
}

@test "launcher groups apps into categories with a Security group" {
  grep -q '"Security", "Development", "Internet"' "$QS/launcher/Launcher.qml"
  grep -q 'function groupOf' "$QS/launcher/Launcher.qml"
  grep -q 'activeGroup' "$QS/launcher/Launcher.qml"
  grep -q '"Wireshark": "Security"' "$QS/launcher/Launcher.qml"
  d="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/share/applications/metasploit.desktop"
  grep -q 'Categories=Security;' "$d"
  grep -q 'Exec=foot' "$d"
}
