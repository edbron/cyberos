#!/usr/bin/env bats
# Task 1: QML notifications (NotificationServer + popups + DND chip) replace mako.

ROOT="$BATS_TEST_DIRNAME/.."
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"

@test "notification server replaces mako" {
  grep -q 'NotificationServer' "$QS/shell.qml"
  grep -q '"notify"' "$QS/shell.qml"
  [ ! -d "$ROOT/profile/airootfs/etc/skel/.config/mako" ]
  [ -f "$QS/notify/NotifyCard.qml" ] && grep -q 'Theme.alert' "$QS/notify/NotifyCard.qml"
  grep -q 'invoke' "$QS/notify/NotifyCard.qml"
  # negated checks run-wrapped so a mid-body failure can't be swallowed by a
  # later passing statement (bash/bats exempt "!"-negated commands from
  # errexit, so only the LAST statement in a body safely propagates a "!"
  # failure -- with three of these here, `run` + explicit status assertion
  # is used instead of trying to make all three "last").
  run grep -qE '^mako$' "$ROOT/profile/packages.x86_64"
  [ "$status" -ne 0 ]
  run grep -rn 'mako' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  [ "$status" -ne 0 ]
  run grep -rn 'mako' "$ROOT/profile/airootfs/etc/skel/.config/hypr/hyprland.lua"
  [ "$status" -ne 0 ]
}

@test "mako is gone from the whole profile tree, not just the obvious spots" {
  ! grep -rn 'mako' "$ROOT/profile/" --include='*.lua' --include='*.sh' --include='cyberos-theme' 2>/dev/null
}

@test "onNotification tracks the notification so it lands in trackedNotifications" {
  # Notification.tracked is a settable bool (verified against the qmltypes:
  # read isTracked/write setTracked) -- the server itself does not
  # auto-track, so the handler must set it explicitly or nothing ever
  # appears in trackedNotifications.
  grep -q 'onNotification' "$QS/shell.qml"
  grep -qE '\.tracked = true' "$QS/shell.qml"
}

@test "NotificationServer is configured for body/image/actions" {
  grep -q 'keepOnReload: true' "$QS/shell.qml"
  grep -q 'actionsSupported: true' "$QS/shell.qml"
  grep -q 'imageSupported: true' "$QS/shell.qml"
  grep -q 'bodySupported: true' "$QS/shell.qml"
}

@test "notify ipc target exposes a dnd toggle" {
  grep -q 'target: "notify"' "$QS/shell.qml"
  grep -q 'function dnd(): void' "$QS/shell.qml"
}

@test "NotifyPopups: top-right anchored panel, exclusiveZone 0, hidden on empty/DND" {
  [ -f "$QS/notify/NotifyPopups.qml" ]
  grep -q 'PanelWindow' "$QS/notify/NotifyPopups.qml"
  grep -q 'top: true' "$QS/notify/NotifyPopups.qml"
  grep -q 'right: true' "$QS/notify/NotifyPopups.qml"
  grep -q 'exclusiveZone: 0' "$QS/notify/NotifyPopups.qml"
  grep -q 'aboveWindows: true' "$QS/notify/NotifyPopups.qml"
  grep -qE 'visible:.*dnd' "$QS/notify/NotifyPopups.qml"
}

@test "NotifyPopups eviction: soft limit spares critical, hard ceiling does not" {
  # Regression guard: an earlier revision exempted critical notifications from
  # eviction with no hard ceiling behind it, so any local process could flood
  # the session bus with urgency=critical notifications (a client-chosen hint,
  # not a privileged flag) and grow trackedNotifications without bound. The
  # fix adds a hard ceiling that evicts the oldest item regardless of urgency;
  # this pins both thresholds and both branches so a future "simplification"
  # can't silently drop the ceiling again.
  f="$QS/notify/NotifyPopups.qml"
  grep -qE 'softLimit:\s*20' "$f"
  grep -qE 'hardLimit:\s*100' "$f"
  grep -qE 'all\.length > root\.hardLimit' "$f"
  grep -qE 'all\.length > root\.softLimit' "$f"
  # Hard-ceiling branch: unconditional eviction, no urgency check on this line.
  hard_line=$(grep -nE 'all\[0\]\.expire\(\)' "$f")
  [ -n "$hard_line" ]
  [[ "$hard_line" != *urgency* ]]
  # Soft-limit branch: still exempts critical notifications.
  grep -qE "urgency !== NotificationUrgency\.Critical" "$f"
}

@test "NotifyCard: urgency styling, expiry timer, dismiss on click" {
  grep -q 'NotificationUrgency' "$QS/notify/NotifyCard.qml"
  grep -q 'Critical' "$QS/notify/NotifyCard.qml"
  grep -q 'Timer' "$QS/notify/NotifyCard.qml"
  grep -q 'expireTimeout' "$QS/notify/NotifyCard.qml"
  grep -q '\.expire()' "$QS/notify/NotifyCard.qml"
  grep -q '\.dismiss()' "$QS/notify/NotifyCard.qml"
}

@test "bar: NotifyChip shows a bell glyph + tracked count, wired into Bar.qml" {
  [ -f "$QS/bar/NotifyChip.qml" ]
  grep -q 'NotifyChip' "$QS/bar/Bar.qml"
  grep -q 'trackedNotifications' "$QS/bar/NotifyChip.qml"
  grep -qE 'dnd' "$QS/bar/NotifyChip.qml"
}

@test "no raw PUA glyph bytes in the new notify surfaces (escapes only)" {
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$QS/notify" "$QS/bar/NotifyChip.qml" --include='*.qml'
}

# Task 2: QML window switcher (Super+Tab) replaces `rofi -show window`.

HYPR="$BATS_TEST_DIRNAME/../profile/airootfs/etc/skel/.config/hypr"
STUB="$BATS_TEST_DIRNAME/hl-stub.lua"

run_hypr_config() {
  local cfgdir="$BATS_TEST_TMPDIR/hyprcfg/hypr"
  mkdir -p "$cfgdir"
  cp "$HYPR/theme.lua" "$cfgdir/theme.lua"
  XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/hyprcfg" lua -e "dofile('$STUB'); dofile('$HYPR/hyprland.lua'); report()"
}

@test "WinSwitch.qml lists Hyprland toplevels" {
  [ -f "$QS/popups/WinSwitch.qml" ]
  grep -q 'Hyprland.toplevels' "$QS/popups/WinSwitch.qml"
}

@test "WinSwitch: PanelWindow, ScriptModel identity, Tab/arrows cycle, Return activates, Escape closes" {
  grep -q 'PanelWindow' "$QS/popups/WinSwitch.qml"
  grep -q 'ScriptModel' "$QS/popups/WinSwitch.qml"
  grep -q 'ObjectComparison.Identity' "$QS/popups/WinSwitch.qml"
  grep -q 'Qt.Key_Tab' "$QS/popups/WinSwitch.qml"
  grep -q 'Qt.Key_Down' "$QS/popups/WinSwitch.qml"
  grep -q 'Qt.Key_Up' "$QS/popups/WinSwitch.qml"
  grep -q 'Qt.Key_Return' "$QS/popups/WinSwitch.qml"
  grep -q 'Qt.Key_Escape' "$QS/popups/WinSwitch.qml"
  grep -q 'closeRequested' "$QS/popups/WinSwitch.qml"
}

@test "WinSwitch: focuses via Hyprland.dispatch, not a nonexistent activate()" {
  grep -q 'Hyprland.dispatch' "$QS/popups/WinSwitch.qml"
  ! grep -qE '\.activate\(\)' "$QS/popups/WinSwitch.qml"
}

@test "shell.qml: winswitch LazyLoader + IpcHandler mirror the launcher's toggle shape" {
  grep -q 'popups' "$QS/shell.qml"
  grep -q 'id: winswitch' "$QS/shell.qml"
  grep -q 'target: "winswitch"' "$QS/shell.qml"
  grep -q 'function toggle(): void' "$QS/shell.qml"
  grep -q 'onCloseRequested: winswitch.active = false' "$QS/shell.qml"
}

@test "Super+Tab dispatches the quickshell winswitch, rofi -show window is gone" {
  run run_hypr_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"bindcmd SUPER + Tab :: qs ipc call winswitch toggle"* ]]
  run grep -q 'rofi -show window' <<<"$output"
  [ "$status" -ne 0 ]
  ! grep -rq 'rofi -show window' "$HYPR/hyprland.lua"
}

@test "the other rofi binds (equal/X) are untouched by the Tab swap" {
  # NOTE: equal/X were rofi binds when Task 2 (window switcher) landed this
  # test. Task 4 (calc/clipboard) swaps them too -- see the Task 4 section
  # below for the current assertions on SUPER+equal/SUPER+X.
  run run_hypr_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"bindcmd SUPER + Tab :: qs ipc call winswitch toggle"* ]]
}

@test "no raw PUA glyph bytes in popups/ (escapes only)" {
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$QS/popups" --include='*.qml'
}

# Task 3: QML emoji picker (Super+period) replaces `rofi -show emoji`; data
# vendored once from rofi-emoji's all_emojis.txt.

@test "emoji.txt is vendored, non-empty, and carries a CC-BY-4.0 attribution header" {
  [ -s "$QS/emoji.txt" ]
  grep -qE '^# ' "$QS/emoji.txt"
  grep -qi 'rofi-emoji' "$QS/emoji.txt"
  grep -qi 'CC-BY-4.0' "$QS/emoji.txt"
  grep -qi 'unicode' "$QS/emoji.txt"
  # real, literal UTF-8 emoji glyphs -- not \uXXXX-escaped (R-s1): every
  # non-comment line's first byte sequence must NOT be a literal backslash-u.
  # run-wrapped (not just "! grep") because a later statement follows in
  # this body -- see the mako-check comment above for why that matters.
  run grep -qE '^\\u' "$QS/emoji.txt"
  [ "$status" -ne 0 ]
  # more than a token handful of entries
  n=$(grep -vcE '^#' "$QS/emoji.txt")
  [ "$n" -gt 1000 ]
}

@test "EmojiPicker.qml exists and reads emoji.txt via FileView" {
  [ -f "$QS/popups/EmojiPicker.qml" ]
  grep -q 'FileView' "$QS/popups/EmojiPicker.qml"
  grep -q 'emoji.txt' "$QS/popups/EmojiPicker.qml"
}

@test "EmojiPicker: GridView, ScriptModel identity, filter, copy via wl-copy stdin" {
  grep -q 'PanelWindow' "$QS/popups/EmojiPicker.qml"
  grep -q 'GridView' "$QS/popups/EmojiPicker.qml"
  grep -q 'ScriptModel' "$QS/popups/EmojiPicker.qml"
  grep -q 'ObjectComparison.Identity' "$QS/popups/EmojiPicker.qml"
  grep -qE 'columns:\s*8' "$QS/popups/EmojiPicker.qml"
  grep -q '"wl-copy"' "$QS/popups/EmojiPicker.qml"
  grep -q '\.write(' "$QS/popups/EmojiPicker.qml"
  grep -q 'stdinEnabled = false' "$QS/popups/EmojiPicker.qml"
  grep -q 'Qt.Key_Return' "$QS/popups/EmojiPicker.qml"
  grep -q 'Qt.Key_Escape' "$QS/popups/EmojiPicker.qml"
  grep -q 'closeRequested' "$QS/popups/EmojiPicker.qml"
}

@test "EmojiPicker: comment-skip does not swallow the '#'-prefixed keycap emoji rows" {
  # emoji.txt has two rows whose glyph itself starts with the literal '#'
  # character (the keycap sequences): "#️⃣ keycap: # ..." and "#⃣ keycap: # ...".
  # A parser that treats every line[0] === '#' as a comment would silently
  # drop both from the picker. The fix checks the SECOND character is
  # whitespace too (comment headers are always "# text"; the keycap glyphs'
  # second codepoint is a variation selector / combining mark, never a
  # space) -- assert that check is actually present in the source.
  grep -qE 'line\[1\]' "$QS/popups/EmojiPicker.qml"
  grep -q '#️⃣' "$QS/emoji.txt"
  grep -q '#⃣ ' "$QS/emoji.txt"
}

@test "shell.qml: emoji LazyLoader + IpcHandler mirror the launcher's toggle shape" {
  grep -q 'id: emoji' "$QS/shell.qml"
  grep -q 'target: "emoji"' "$QS/shell.qml"
  grep -q 'onCloseRequested: emoji.active = false' "$QS/shell.qml"
}

@test "Super+period dispatches the quickshell emoji picker, rofi -show emoji is gone" {
  run run_hypr_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"bindcmd SUPER + period :: qs ipc call emoji toggle"* ]]
  run grep -q 'rofi -show emoji' <<<"$output"
  [ "$status" -ne 0 ]
  ! grep -rq 'rofi -show emoji' "$HYPR/hyprland.lua"
}

@test "rofi-emoji is gone from packages; rofi itself leaves in Task 5" {
  ! grep -qE '^rofi-emoji$' "$ROOT/profile/packages.x86_64"
}

# Task 4: QML calculator (Super+equal) replaces `rofi -show calc`; QML
# clipboard history (Super+X) replaces the cliphist|rofi|cliphist|wl-copy pipe.

@test "Calc.qml: PanelWindow, debounce Timer, qalc argv (expr as one element), copies result via wl-copy stdin" {
  [ -f "$QS/popups/Calc.qml" ]
  grep -q 'PanelWindow' "$QS/popups/Calc.qml"
  grep -q 'Timer' "$QS/popups/Calc.qml"
  grep -qE 'interval:\s*150' "$QS/popups/Calc.qml"
  grep -q '"qalc"' "$QS/popups/Calc.qml"
  grep -q '"-t"' "$QS/popups/Calc.qml"
  grep -q '"wl-copy"' "$QS/popups/Calc.qml"
  grep -q '\.write(' "$QS/popups/Calc.qml"
  grep -q 'stdinEnabled = false' "$QS/popups/Calc.qml"
  grep -q 'Qt.Key_Return' "$QS/popups/Calc.qml"
  grep -q 'Qt.Key_Escape' "$QS/popups/Calc.qml"
  grep -q 'closeRequested' "$QS/popups/Calc.qml"
}

@test "Calc.qml: guards empty input, does not spawn qalc on an empty expression" {
  grep -q '\.trim()' "$QS/popups/Calc.qml"
  grep -qE 'if\s*\(expr\s*===\s*""\)' "$QS/popups/Calc.qml"
}

@test "ClipHist.qml: lists cliphist, decode via stdin write (no pipe), chains to wl-copy" {
  [ -f "$QS/popups/ClipHist.qml" ]
  grep -q 'PanelWindow' "$QS/popups/ClipHist.qml"
  grep -q '"cliphist"' "$QS/popups/ClipHist.qml"
  grep -q '"list"' "$QS/popups/ClipHist.qml"
  grep -q '"decode"' "$QS/popups/ClipHist.qml"
  grep -q '"wl-copy"' "$QS/popups/ClipHist.qml"
  grep -q 'ScriptModel' "$QS/popups/ClipHist.qml"
  grep -q 'ObjectComparison.Identity' "$QS/popups/ClipHist.qml"
  grep -q 'StdioCollector' "$QS/popups/ClipHist.qml"
  grep -q '\.write(' "$QS/popups/ClipHist.qml"
  grep -q 'onExited' "$QS/popups/ClipHist.qml"
  grep -q 'Qt.Key_Return' "$QS/popups/ClipHist.qml"
  grep -q 'Qt.Key_Escape' "$QS/popups/ClipHist.qml"
  grep -q 'closeRequested' "$QS/popups/ClipHist.qml"
}

@test "no composed shell strings anywhere in quickshell (argv + stdin writes only), except two pre-existing static /proc readers" {
  # The Global Constraints test is "! grep -rn '\"sh\", \"-c\"' \$QS" over the
  # whole quickshell dir. Widened tree-wide (was scoped to Calc/ClipHist
  # only) with an explicit allowlist for the two pre-existing legitimate
  # static /proc readers: bar/SysStats.qml and widgets/00-example-
  # uptime.qml pre-date this plan (installer/quickshell) and legitimately
  # shell out to static, argument-free /proc reads with zero untrusted
  # input, which is not the injection trap this constraint targets. Any
  # "sh", "-c" OUTSIDE those two files -- including a regression in the
  # cliphist decode -> wl-copy chain carrying a user-selected clipboard
  # entry -- fails this test.
  ! (grep -rn '"sh", "-c"' "$QS" --include='*.qml' | grep -vE 'bar/SysStats.qml|widgets/00-example-uptime.qml')
}

@test "shell.qml: calc + clip LazyLoaders and IpcHandlers mirror the launcher's toggle shape" {
  grep -q 'id: calc' "$QS/shell.qml"
  grep -q 'target: "calc"' "$QS/shell.qml"
  grep -q 'onCloseRequested: calc.active = false' "$QS/shell.qml"
  grep -q 'id: clip' "$QS/shell.qml"
  grep -q 'target: "clip"' "$QS/shell.qml"
  grep -q 'onCloseRequested: clip.active = false' "$QS/shell.qml"
}

@test "Super+equal dispatches the quickshell calc, rofi -show calc is gone" {
  run run_hypr_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"bindcmd SUPER + equal :: qs ipc call calc toggle"* ]]
  run grep -q 'rofi -show calc' <<<"$output"
  [ "$status" -ne 0 ]
  ! grep -rq 'rofi -show calc' "$HYPR/hyprland.lua"
}

@test "Super+X dispatches the quickshell clip history, the cliphist|rofi|cliphist|wl-copy pipe is gone" {
  run run_hypr_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"bindcmd SUPER + X :: qs ipc call clip toggle"* ]]
  run grep -q 'rofi -dmenu' <<<"$output"
  [ "$status" -ne 0 ]
  ! grep -rq 'rofi -dmenu' "$HYPR/hyprland.lua"
}

@test "packages: libqalculate added explicitly, rofi-calc gone, cliphist still present (rofi itself leaves in Task 5)" {
  grep -qE '^libqalculate$' "$ROOT/profile/packages.x86_64"
  run grep -qE '^rofi-calc$' "$ROOT/profile/packages.x86_64"
  [ "$status" -ne 0 ]
  grep -qE '^cliphist$' "$ROOT/profile/packages.x86_64"
}

@test "no raw PUA glyph bytes in the new Calc/ClipHist popups (escapes only)" {
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$QS/popups/Calc.qml" "$QS/popups/ClipHist.qml"
}

# Task 5: rofi eradication -- rofi and rofi's config are used by NOTHING
# after Tasks 1-4 (winswitch/emoji/calc/clip all live in QML now), so the
# package, its config dir, the dead layer_rule and the theme generator's
# rofi block all leave.

@test "rofi config dir is gone" {
  [ ! -d "$ROOT/profile/airootfs/etc/skel/.config/rofi" ]
}

@test "rofi is gone from packages.x86_64" {
  ! grep -qE '^rofi$' "$ROOT/profile/packages.x86_64"
}

@test "the dead rofi layer_rule is gone from hyprland.lua; the quickshell layer_rule survives" {
  # NOTE: "! grep" is only guaranteed to fail the test when it is the LAST
  # statement in the body -- bash/bats exempt a "!"-negated command from
  # errexit/ERR-trap propagation, so an earlier "! grep" that "fails" (i.e.
  # a real match was found) would be silently swallowed if something ran
  # after it. Keep the negated check last.
  grep -q 'namespace = "quickshell"' "$HYPR/hyprland.lua"
  ! grep -q 'namespace = "rofi"' "$HYPR/hyprland.lua"
}

@test "cyberos-theme: rofi block and mkdir component are gone; the script still parses" {
  bash -n "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  # the other generated blocks are untouched: hypr, foot, tmux, nvim and
  # quickshell theme.json all still get written
  grep -q '"$CFG/hypr/theme.conf"' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  grep -q '"$CFG/hypr/theme.lua"' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  grep -q '"$CFG/foot/foot.ini"' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  grep -q '"$CFG/tmux/theme.conf"' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  grep -q '"$CFG/nvim/lua/cyber_colors.lua"' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  grep -q '"$CFG/quickshell/theme.json"' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
  # negated checks last, combined into one grep call (see NOTE above)
  ! grep -qE '/rofi/colors\.rasi|\$CFG"/rofi' "$ROOT/profile/airootfs/usr/local/bin/cyberos-theme"
}

@test "the complete-removal gate: rofi/mako survive nowhere in profile/ except explanatory migration comments" {
  # Any hit of "rofi" or "mako" that is NOT on a comment line (#, // or --
  # prefixed, ignoring leading whitespace) is a live reference -- a command,
  # a package line, a config path, an autostart -- and fails this test. This
  # is meaningful, not vacuous: proven RED by temporarily reintroducing a
  # bare "rofi" package line (self-review), which this same pipeline catches.
  # \b matters: without it this matched the "rofi" inside "profile", so any
  # power-PROFIle word (power-profiles-daemon, PowerProfiles) failed the gate.
  # Still catches a bare "rofi" package line or a rofi-calc/rofi.rasi path.
  run bash -c "grep -rniE '\\brofi\\b|\\bmako\\b' '$ROOT/profile/' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//|--)'"
  [ -z "$output" ]
}
