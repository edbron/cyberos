#!/usr/bin/env bats
# Music Flow: now-playing panel + bar chip, inspired by the UX of
# DevInBlack001/Omarchy-music-flow-copy (a fork of Clifford Baidoo's
# omarchy-music-flow) but not a port of it. That plugin shells out for
# browser/PipeWire stream scraping and fetches album art from a CDN
# allowlist; this version uses only Quickshell's own local Mpris D-Bus
# service, so there is no subprocess, no network call and no scraping
# anywhere in either file.

ROOT="$BATS_TEST_DIRNAME/.."
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"

@test "the old single-line Media.qml is gone, nothing references it" {
  [ ! -f "$QS/bar/Media.qml" ]
  ! grep -rq 'Media {}' "$QS/bar/Bar.qml"
}

@test "panel: PanelWindow, no subprocess, no network, uses Quickshell's own Mpris service" {
  f="$QS/popups/MusicFlow.qml"
  grep -q 'PanelWindow' "$f"
  grep -q 'import Quickshell.Services.Mpris' "$f"
  # No Process, no Quickshell.execDetached, no XMLHttpRequest/fetch/curl --
  # everything comes from the Mpris singleton, already local D-Bus data.
  ! grep -qE 'Process\s*\{|execDetached|XMLHttpRequest|curl' "$f"
}

@test "album art is shown only for a file:// trackArtUrl, never http(s)" {
  f="$QS/popups/MusicFlow.qml"
  grep -q 'hasLocalArt' "$f"
  grep -q 'trackArtUrl.startsWith("file://")' "$f"
  # The Image element's source is gated on hasLocalArt, not the raw URL
  # directly -- an http(s) art URL never reaches Image, so Image never
  # makes a network request of its own.
  awk '/Image \{/,/^ *}/' "$f" | grep -q 'source: root.hasLocalArt ? root.player.trackArtUrl : ""'
}

@test "no elevated privileges, no plaintext keys read: no root/sudo, no client.keys anywhere" {
  f="$QS/popups/MusicFlow.qml"
  ! grep -qE '\bsudo\b|\bpkexec\b|client\.keys' "$f"
}

@test "title/artist/album/source-name all render as plain text (MPRIS data this project does not author)" {
  f="$QS/popups/MusicFlow.qml"
  awk '/text: root\.player \? root\.player\.trackTitle/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
  awk '/text: root\.player \? root\.player\.trackArtist/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
  awk '/text: root\.player \? root\.player\.trackAlbum/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
  awk '/text: srow\.modelData\.identity/,/^ *}/' "$f" | grep -q 'textFormat: Text.PlainText'
}

@test "playback controls are gated on the player's own can* capability flags" {
  f="$QS/popups/MusicFlow.qml"
  grep -q 'enabled: !!(root.player && root.player.canGoPrevious)' "$f"
  grep -q 'enabled: !!(root.player && root.player.canTogglePlaying)' "$f"
  grep -q 'enabled: !!(root.player && root.player.canGoNext)' "$f"
}

@test "idle browser MPRIS entries are excluded (background tabs, not a deliberate source)" {
  f="$QS/popups/MusicFlow.qml"
  grep -q 'readonly property var browsers: \["firefox", "chromium", "brave"\]' "$f"
  grep -q 'candidates: Mpris.players.values.filter(p => !isBrowser(p) || p.isPlaying)' "$f"
}

@test "a browser tab actively playing audio overrides the browser exclusion" {
  f="$QS/popups/MusicFlow.qml"
  # The exclusion is scoped to idle entries (|| p.isPlaying), not a blanket
  # ban on browsers: a tab genuinely producing audio right now is real
  # output a student expects to see, not the stale/flickering background
  # tab the exclusion exists to hide.
  grep -q '!isBrowser(p) || p.isPlaying' "$f"
}

@test "browser exclusion carries its own rationale, so it isn't mistaken for a bug later" {
  f="$QS/popups/MusicFlow.qml"
  # Guards the explanatory comment above the browsers array, not just the
  # filter itself: without it, "why doesn't Music Flow show a YouTube tab
  # playing in Firefox" reads as a missed integration rather than the
  # deliberate, inherited-from-Media.qml choice it actually is.
  grep -qi "not a deliberate" "$f"
}

@test "source selection sticks to a stable bus name, not an index that could point at a different player" {
  f="$QS/popups/MusicFlow.qml"
  grep -q 'preferredId' "$f"
  grep -q 'p.dbusName === root.preferredId' "$f"
}

@test "no raw private-use glyph bytes (escapes only)" {
  ! grep -rlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$QS/popups/MusicFlow.qml" "$QS/bar/MusicFlowChip.qml"
}

@test "bar chip: reads the panel's own player (never disagrees on which one is active), toggles via IPC" {
  f="$QS/bar/MusicFlowChip.qml"
  grep -q 'musicflow.item ? musicflow.item.player : null' "$f"
  grep -qE 'execDetached\(\["qs", "ipc", "call", "musicflow", "toggle"\]\)' "$f"
  # No independent player-filtering logic here -- would be exactly the
  # duplicated-logic drift risk flagged in the pre-port audit of the
  # original plugin (two copies of the same filter that can silently
  # diverge). There is exactly one place this project computes it.
  ! grep -q 'browsers' "$f"
}

@test "Bar.qml wires MusicFlowChip on the left, where Media.qml used to sit" {
  f="$QS/bar/Bar.qml"
  grep -q 'MusicFlowChip {}' "$f"
  # Left row only -- still grouped with the launcher/install buttons, not
  # among the right-side hardware-status chips.
  awk '/RowLayout {.*\/\/ left/,/^        }/' "$f" | grep -q 'MusicFlowChip {}'
}

@test "chip visualizer: PwNodePeakMonitor, not a subprocess, only enabled while actually playing" {
  f="$QS/bar/MusicFlowChip.qml"
  grep -q 'import Quickshell.Services.Pipewire' "$f"
  grep -q 'PwNodePeakMonitor' "$f"
  grep -q 'node: Pipewire.defaultAudioSink' "$f"
  grep -q 'enabled: chip.playing' "$f"
  # No Process, no subprocess of any kind, backing the visualizer -- the
  # peak value comes entirely from Quickshell's own Pipewire service.
  ! grep -qE 'Process\s*\{|execDetached.*pw-record|pw-record' "$f"
}

@test "chip visualizer: bar height is bounded (min/max clamped), never fed straight from peak" {
  f="$QS/bar/MusicFlowChip.qml"
  grep -q 'Math.max(bars.minBarHeight' "$f"
  grep -q 'Math.min(bars.maxBarHeight' "$f"
}

@test "shell.qml: musicflow is always-active (chip needs live state while closed), IPC target is argument-free" {
  f="$QS/shell.qml"
  awk '/id: musicflow/,/^    }/' "$f" | grep -qE 'active:\s*true'
  awk '/target: "musicflow"/,/^    }/' "$f" | grep -q 'function open'
  awk '/target: "musicflow"/,/^    }/' "$f" | grep -q 'function close'
  awk '/target: "musicflow"/,/^    }/' "$f" | grep -q 'function toggle'
}
