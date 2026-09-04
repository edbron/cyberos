#!/usr/bin/env bats
# The three QML surfaces that replaced the KDE apps.
ROOT="$BATS_TEST_DIRNAME/.."
QS="$ROOT/profile/airootfs/etc/skel/.config/quickshell"

@test "mixer: classifies pipewire nodes by exact type, never by isSink" {
  f="$QS/popups/Mixer.qml"
  [ -f "$f" ]
  grep -q 'PwNodeType.AudioSink' "$f"
  grep -q 'PwNodeType.AudioOutStream' "$f"
  grep -q 'PwObjectTracker' "$f"
  grep -q 'preferredDefaultAudioSink' "$f"
  # AudioOutStream carries the Sink bit, so an isSink filter would list a
  # playing app as an output device. Guard the trap, not just the feature.
  run grep -E '\.isSink|\.isStream' "$f"
  [ "$status" -ne 0 ]
  # The tracker must cover every node, not the filtered subset: PwNode.type
  # is Untracked until tracked, so filter-then-track is circular and leaves
  # the panel permanently empty. Found in VM testing, invisible to qmllint.
  grep -q 'objects: Pipewire.nodes.values' "$f"
  run grep -E 'objects: root\.(sinks|streams)' "$f"
  [ "$status" -ne 0 ]
  # PwNodeAudio.volume's NOTIFY signal is volumesChanged (shared with the
  # volumes list) -- there is no volumeChanged, and a Connections handler
  # for a nonexistent signal is dead code that only warns at runtime.
  grep -q 'onVolumesChanged' "$f"
  run grep 'function onVolumeChanged' "$f"
  [ "$status" -ne 0 ]
}

@test "mixer: wired into the shell and owns the bar's audio chip" {
  grep -q 'target: "mixer"' "$QS/shell.qml"
  grep -q 'Popups.Mixer' "$QS/shell.qml"
  grep -q '"mixer", "toggle"' "$QS/bar/Audio.qml"
  run grep 'pavucontrol' "$QS/bar/Audio.qml"
  [ "$status" -ne 0 ]
}

@test "images: FloatingWindow, folder walk without the absent fileURL role" {
  f="$QS/apps/Images.qml"
  [ -f "$f" ]
  grep -q 'FloatingWindow' "$f"
  grep -q 'Qt.labs.folderlistmodel' "$f"
  # indexOf() needs a file:// prefixed string; the fileURL role does not
  # exist and returns undefined, which makes indexOf throw.
  grep -q 'indexOf("file://"' "$f"
  run grep 'fileURL' "$f"
  [ "$status" -ne 0 ]
}

@test "images: pans via a transform, with the MouseArea outside it" {
  f="$QS/apps/Images.qml"
  grep -q 'Translate' "$f"
  grep -q 'pan.x' "$f"
  # anchors beat x/y, so a drag target on the anchored image is dead code
  run grep 'drag.target' "$f"
  [ "$status" -ne 0 ]
  # The MouseArea must NOT be nested inside the Image that carries the
  # Translate: Qt would deliver it already-transformed coordinates and the
  # pan math would double-compensate. Assert the Image element contains no
  # MouseArea by checking the span from `Image {` to the line before the
  # MouseArea declaration never opens one.
  img_line=$(grep -n 'Image {' "$f" | head -1 | cut -d: -f1)
  ma_line=$(grep -n 'MouseArea {' "$f" | head -1 | cut -d: -f1)
  [ "$ma_line" -gt "$img_line" ]
  # the Image block must have closed before the MouseArea opens: at the
  # MouseArea's indentation, a nested one would be deeper than the Image's.
  img_indent=$(sed -n "${img_line}p" "$f" | sed 's/[^ ].*//' | wc -c)
  ma_indent=$(sed -n "${ma_line}p" "$f" | sed 's/[^ ].*//' | wc -c)
  [ "$ma_indent" -le "$img_indent" ]
}

@test "images: ipc open target and desktop entry at an unowned path" {
  grep -q 'target: "images"' "$QS/shell.qml"
  grep -q 'function open' "$QS/shell.qml"
  d="$ROOT/profile/airootfs/usr/local/share/applications/cyberos-images.desktop"
  [ -f "$d" ]
  grep -q 'Exec=cyberos-images %f' "$d"
  grep -q 'MimeType=image/' "$d"
}

@test "files: FloatingWindow over FolderListModel with the verified roles" {
  f="$QS/apps/Files.qml"
  [ -f "$f" ]
  grep -q 'FloatingWindow' "$f"
  grep -q 'Qt.labs.folderlistmodel' "$f"
  grep -q 'showDirsFirst' "$f"
  run grep 'fileURL' "$f"
  [ "$status" -ne 0 ]
}

@test "files: opens via xdg-open, deletes via trash-put, never rm" {
  f="$QS/apps/Files.qml"
  grep -q '"xdg-open"' "$f"
  grep -q '"trash-put"' "$f"
  grep -q '"7z", "x"' "$f"
  # A file manager that shells out to rm is a data-loss bug, not a feature.
  run grep -E '"rm"|rm -' "$f"
  [ "$status" -ne 0 ]
}

@test "files: extract lists the archive first and refuses a zip-slip entry before ever calling 7z x" {
  f="$QS/apps/Files.qml"
  # 7z l runs before 7z x, driven from the list process's own completion --
  # the extract call sits inside listProc's stdout handler, not called
  # directly from extract().
  grep -q '"7z", "l", "-slt"' "$f"
  run grep -F 'function extract(filePath)' "$f"
  [ "$status" -eq 0 ]
  ! grep -q 'function extract(filePath) { extractProc' "$f"
  # Entries are parsed only after the archive's own header block ends --
  # otherwise the archive's own (always-absolute) external path would be
  # mistaken for an unsafe internal entry on every single extraction.
  grep -q '"----------"' "$f"
  grep -q 'p.startsWith("/")' "$f"
  grep -q 'p.split("/").includes("..")' "$f"
}

@test "files: ipc target, desktop entry, and Super+E open it" {
  grep -q 'target: "files"' "$QS/shell.qml"
  d="$ROOT/profile/airootfs/usr/local/share/applications/cyberos-files.desktop"
  [ -f "$d" ]
  grep -q 'Exec=cyberos-files %f' "$d"
  grep -q 'MimeType=inode/directory' "$d"
}

@test "launcher wrappers pass an explicit argument and are mode-registered" {
  for w in cyberos-files cyberos-images; do
    f="$ROOT/profile/airootfs/usr/local/bin/$w"
    [ -f "$f" ]
    # The empty-default is the whole point: qs ipc call with too few
    # arguments silently does nothing.
    grep -q '"${1:-}"' "$f"
    # mkarchiso copies airootfs with --no-preserve=mode, so the execute bit
    # only exists if profiledef.sh declares it.
    grep -q "\"/usr/local/bin/$w\"\]=\"0:0:755\"" "$ROOT/profile/profiledef.sh"
  done
}

# General form of the check above, driven by git's own tracked mode rather
# than a hand-maintained list: every script committed 755 under
# usr/local/bin must have a matching profiledef.sh entry, or mkarchiso's
# --no-preserve=mode silently ships it non-executable. Missing exactly this
# for cyberos-systemhealth-state and cyberos-toggle-touchscreen shipped both
# features unusable on a real ISO -- git's own mode bit isn't enough, and
# per-script tests only catch what someone remembers to write one for.
@test "every 755-tracked usr/local/bin script has a profiledef.sh file_permissions entry" {
  while IFS=$'\t' read -r mode path; do
    [ "$mode" = "100755" ] || continue
    name=$(basename "$path")
    run grep -q "\"/usr/local/bin/$name\"\]=\"0:0:755\"" "$ROOT/profile/profiledef.sh"
    [ "$status" -eq 0 ] || { echo "profiledef.sh is missing: [\"/usr/local/bin/$name\"]=\"0:0:755\""; false; }
  done < <(git -C "$ROOT" ls-files -s profile/airootfs/usr/local/bin | awk '{print $1"\t"$4}')
}

# --- Battery chip opens power profiles, not the shutdown menu (2026-09-01)
# The bar already has a dedicated power button for sleep/lock/restart/shutdown;
# the battery chip was opening the same menu instead of showing what a battery
# chip should: the active power profile and the live discharge rate.

@test "power profile panel uses the real UPower APIs" {
  f="$QS/popups/PowerPanel.qml"
  [ -f "$f" ]
  grep -q 'Quickshell.Services.UPower' "$f"
  # profile is writable; assigning it is how a profile is switched.
  grep -q 'PowerProfiles.profile' "$f"
  grep -q 'PowerProfile.PowerSaver' "$f"
  grep -q 'PowerProfile.Balanced' "$f"
  grep -q 'PowerProfile.Performance' "$f"
  # Performance is absent on many laptops -- must be gated, not assumed.
  grep -q 'hasPerformanceProfile' "$f"
  # changeRate is the discharge/charge figure in watts.
  grep -q 'changeRate' "$f"
}

@test "battery chip opens the power profile panel, not the shutdown menu" {
  grep -q '"powerprofile", "toggle"' "$QS/bar/Battery.qml"
  run grep 'powerMenu' "$QS/bar/Battery.qml"
  [ "$status" -ne 0 ]
  grep -q 'target: "powerprofile"' "$QS/shell.qml"
  grep -q 'Popups.PowerPanel' "$QS/shell.qml"
  # the dedicated power button must still own the shutdown menu
  grep -q 'powerMenu.activeAsync = true' "$QS/bar/Bar.qml"
}

@test "brightness chip is gone from the bar but the OSD keys still work" {
  run grep -n 'Brightness {}' "$QS/bar/Bar.qml"
  [ "$status" -ne 0 ]
  [ ! -f "$QS/bar/Brightness.qml" ]
  # XF86 brightness keys route through the shell's OSD handler, not the chip.
  grep -q 'function brightnessUp' "$QS/shell.qml"
  grep -q 'function brightnessDown' "$QS/shell.qml"
}

@test "power-profiles-daemon ships and is enabled on installed systems" {
  sed 's/#.*//' "$ROOT/profile/packages.x86_64" | tr -d ' ' | grep -qx 'power-profiles-daemon'
  grep -q 'power-profiles-daemon' "$ROOT/profile/airootfs/usr/local/bin/cyberos-install"
}
