#!/usr/bin/env bats

setup() {
  export CYBEROS_INSTALL_LIB_ONLY=1
  # shellcheck disable=SC1090
  source "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  TMP="$BATS_TEST_TMPDIR"
}

@test "restore_kernel copies the image when the source exists" {
  mkdir -p "$TMP/bootmnt/arch/boot/x86_64" "$TMP/dest/boot"
  echo kernel >"$TMP/bootmnt/arch/boot/x86_64/vmlinuz-linux"
  run restore_kernel linux "$TMP/bootmnt" "$TMP/dest"
  [ "$status" -eq 0 ]
  [ -f "$TMP/dest/boot/vmlinuz-linux" ]
}

@test "restore_kernel names the flavour it could not find" {
  mkdir -p "$TMP/bootmnt/arch/boot/x86_64" "$TMP/dest/boot"
  run restore_kernel linux-lts "$TMP/bootmnt" "$TMP/dest"
  [ "$status" -ne 0 ]
  [[ "$output" == *"linux-lts"* ]]
}

@test "restore_kernel falls back to the airootfs copy for lts" {
  mkdir -p "$TMP/bootmnt/arch/boot/x86_64" "$TMP/dest/boot"
  mkdir -p "$TMP/dest/usr/lib/modules/6.18.46-1-lts"
  echo kernel >"$TMP/dest/usr/lib/modules/6.18.46-1-lts/vmlinuz"
  run restore_kernel linux-lts "$TMP/bootmnt" "$TMP/dest"
  [ "$status" -eq 0 ]
  [ -f "$TMP/dest/boot/vmlinuz-linux-lts" ]
}

@test "restore_kernel does not mistake the lts image for the default kernel" {
  mkdir -p "$TMP/bootmnt/arch/boot/x86_64" "$TMP/dest/boot"
  mkdir -p "$TMP/dest/usr/lib/modules/6.18.46-1-lts"
  echo lts >"$TMP/dest/usr/lib/modules/6.18.46-1-lts/vmlinuz"
  run restore_kernel linux "$TMP/bootmnt" "$TMP/dest"
  [ "$status" -ne 0 ]
}

@test "grub_safe_entries emits one entry per kernel with the safe token" {
  run grub_safe_entries "1111-2222"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cyberos.safegraphics=1"* ]]
  [[ "$output" == *"nomodeset"* ]]
  [[ "$output" == *"vmlinuz-linux"* ]]
  [[ "$output" == *"vmlinuz-linux-lts"* ]]
  [[ "$output" == *"1111-2222"* ]]
}

@test "grub_safe_entries refuses to emit an entry with no root UUID" {
  run grub_safe_entries ""
  [ "$status" -ne 0 ]
}

@test "sourcing in library mode runs no installer logic" {
  # The guard is the risky part of this change: placed wrong, the installer
  # becomes a no-op and it only shows up mid-install on a student's disk.
  run bash -c "CYBEROS_INSTALL_LIB_ONLY=1 source '$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install'; echo SOURCED-OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED-OK"* ]]
  ! [[ "$output" == *"Firmware mode"* ]]
}

@test "the installer pins the default GRUB entry to the main kernel, not the LTS fallback" {
  # GRUB sorts kernel names in reverse, and vmlinuz-linux-lts sorts after
  # vmlinuz-linux, so shipping a fallback kernel silently made it the default.
  # Seen on build 14: a fresh install booted 6.18-lts instead of 7.1.
  run grep -c 'GRUB_TOP_LEVEL=/boot/vmlinuz-linux' "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  [ "$output" -ge 1 ]
}

@test "valid_username accepts what useradd accepts" {
  run valid_username "student"
  [ "$status" -eq 0 ]
  run valid_username "lab-07"
  [ "$status" -eq 0 ]
}

@test "valid_username rejects a value crafted to break out of the chroot heredoc" {
  run valid_username 'x"; touch /tmp/PWNED; echo "'
  [ "$status" -ne 0 ]
}

@test "valid_username rejects uppercase and leading digits" {
  run valid_username "Bob"
  [ "$status" -ne 0 ]
  run valid_username "1student"
  [ "$status" -ne 0 ]
}

@test "valid_luks_passphrase enforces the 8-character floor the GUI also enforces" {
  run valid_luks_passphrase "short"
  [ "$status" -ne 0 ]
  run valid_luks_passphrase "longenough1"
  [ "$status" -eq 0 ]
}

@test "the chroot handoff heredoc is quoted so USER_/PASS/ROOTPASS cannot inject shell syntax" {
  # Regression guard for the injection fixed in this change: an unquoted <<CH
  # heredoc lets the outer (host, root) shell expand --user/--password into
  # the script text handed to arch-chroot's bash, so a value containing a
  # quote or $(...) becomes shell syntax that runs inside the chroot.
  run grep -n "bin/bash -e <<'CH'" "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  [ "$status" -eq 0 ]
  run grep -n "bin/bash -e <<CH$" "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  [ "$status" -ne 0 ]
}

@test "USER_/PASS/ROOTPASS/TZ_/DISK/UEFI reach the chroot via env, not host-side interpolation" {
  run grep -A2 'arch-chroot /mnt /usr/bin/env' "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  [ "$status" -eq 0 ]
  for var in TZ_ USER_ PASS= ROOTPASS DISK UEFI; do
    [[ "$output" == *"$var"* ]]
  done
}

# --- Regression: ThinkPad T480 would not boot after a UEFI install (2026-09-01)
# Two independent defects, both found on real hardware:
#   1. the GPT protective-MBR "legacy bootable" flag was set on every install;
#      Lenovo firmware treats such a disk as hybrid and skips it in UEFI mode.
#   2. grub-install's NVRAM step could fail while `|| true` hid it, so the
#      machine had EFI binaries but no boot entry -- and the installer still
#      printed "INSTALLATION COMPLETE!".

@test "pmbr_boot is wanted for BIOS installs and refused on UEFI" {
  UEFI=0; run pmbr_boot_wanted; [ "$status" -eq 0 ]
  UEFI=1; run pmbr_boot_wanted; [ "$status" -ne 0 ]
}

@test "installer enables pmbr_boot from exactly one guarded place" {
  f="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  # Exactly one `pmbr_boot on` in the whole script, and it lives inside
  # apply_pmbr_boot, which refuses unless pmbr_boot_wanted says BIOS. A second
  # call site added later would trip this.
  [ "$(grep -c 'pmbr_boot on' "$f")" -eq 1 ]
  grep -A3 '^apply_pmbr_boot()' "$f" | grep -q 'pmbr_boot_wanted || return 0'
  grep -A4 '^apply_pmbr_boot()' "$f" | grep -q 'pmbr_boot on'
}

@test "installer does not swallow the UEFI boot-entry failure" {
  run grep -n 'bootloader-id=CyberOS --recheck || true' \
    "$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  [ "$status" -ne 0 ]
}

@test "installer verifies a UEFI boot entry exists before claiming success" {
  f="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  grep -q 'efibootmgr' "$f"
  grep -q 'cyberos-no-efi-entry' "$f"
}

@test "repair-boot clears pmbr_boot on UEFI and can fix an unbootable disk" {
  f="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-repair-boot"
  grep -q 'pmbr_boot off' "$f"
  run grep -n 'bootloader-id=CyberOS --recheck || true' "$f"
  [ "$status" -ne 0 ]
}

# unmount_disk: a disk carrying a previous CyberOS install (recognizable
# CYBEROS/CYBEROS_EFI labels) is exactly what this project's own udisks2
# auto-mount picks up on login. wipefs/sgdisk -Z then fail with a raw kernel
# I/O error, not a clear message, if the target disk's own partitions are
# still mounted when erase mode tries to wipe them -- reported from real
# hardware testing.

@test "unmount_disk calls umount on every partition, never on the disk itself" {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *MOUNTPOINT*) exit 0 ;;  # nothing still mounted once umount below has run
  *) printf '%s\n' /dev/sda /dev/sda1 /dev/sda2 /dev/sda3 ;;
esac
EOF
  chmod +x "$TMP/bin/lsblk"
  cat >"$TMP/bin/umount" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/umount-calls"
EOF
  chmod +x "$TMP/bin/umount"
  PATH="$TMP/bin:$PATH" run unmount_disk /dev/sda
  [ "$status" -eq 0 ]
  [ -f "$TMP/umount-calls" ]
  # "!"-negated commands are exempt from errexit regardless of position, so
  # this can't just sit ahead of the next three assertions -- run + an
  # explicit status check instead.
  run grep -qx -- '-R /dev/sda' "$TMP/umount-calls"
  [ "$status" -ne 0 ]
  grep -qx -- '-R /dev/sda1' "$TMP/umount-calls"
  grep -qx -- '-R /dev/sda2' "$TMP/umount-calls"
  grep -qx -- '-R /dev/sda3' "$TMP/umount-calls"
}

@test "unmount_disk tolerates lsblk failure and an unmounted (already-idle) partition" {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$TMP/bin/lsblk"
  cat >"$TMP/bin/umount" <<'EOF'
#!/usr/bin/env bash
exit 32
EOF
  chmod +x "$TMP/bin/umount"
  PATH="$TMP/bin:$PATH" run unmount_disk /dev/sda
  [ "$status" -eq 0 ]
}

# Regression: the original unmount_disk swallowed every umount failure with
# `|| true` and had no way to report one, so a genuinely busy partition (a
# stale LUKS mapping from a prior encrypted install, say) fell straight
# through into wipefs/sgdisk -Z anyway -- silently "fixed", still broken.

@test "unmount_disk fails loudly when a partition is still mounted after every unmount attempt" {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *MOUNTPOINT*) printf '%s\n' /mnt ;;
  *) printf '%s\n' /dev/sda /dev/sda1 ;;
esac
EOF
  chmod +x "$TMP/bin/lsblk"
  cat >"$TMP/bin/umount" <<'EOF'
#!/usr/bin/env bash
exit 32
EOF
  chmod +x "$TMP/bin/umount"
  PATH="$TMP/bin:$PATH" run unmount_disk /dev/sda
  [ "$status" -ne 0 ]
  [[ "$output" == *"still has a mounted partition"* ]]
}

@test "disk_has_mount follows a dm-crypt/LUKS mapper child, not just a raw partition path" {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
printf '%s\n%s\n%s\n' "" "" "/mnt"
EOF
  chmod +x "$TMP/bin/lsblk"
  PATH="$TMP/bin:$PATH" run disk_has_mount /dev/sda
  [ "$status" -eq 0 ]
}

@test "disk_has_mount returns false when nothing under the disk is mounted" {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TMP/bin/lsblk"
  PATH="$TMP/bin:$PATH" run disk_has_mount /dev/sda
  [ "$status" -ne 0 ]
}

@test "the pre-partition guard is mapper-aware: disk_has_mount, not a raw /proc/mounts regex" {
  f="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  grep -q 'disk_has_mount "\$DISK" && die "\$DISK is mounted' "$f"
  # The old regex only ever matched a raw partition device path, never a
  # /dev/mapper/<name> mount source stacked on one -- gone from this guard,
  # though the manual-mode ROOTP/EFIP/HOMEP check a few lines above it is a
  # separate, still-intentional /proc/mounts read.
  run grep -Fn '(p?[0-9]| )" /proc/mounts' "$f"
  [ "$status" -ne 0 ]
}

@test "erase mode dies if unmount_disk cannot clear every mount, does not press on into wipefs" {
  f="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  grep -q 'unmount_disk "\$DISK" || die' "$f"
}

# is_whole_disk: the unattended --disk path had no validation at all before
# this -- --disk /dev/sda1 by mistake would run wipefs/sgdisk -Z against a
# partition, not the disk it looks like.

@test "is_whole_disk accepts TYPE=disk, rejects a partition or unresolvable path" {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
echo "${LSBLK_TYPE:-}"
EOF
  chmod +x "$TMP/bin/lsblk"
  LSBLK_TYPE=disk PATH="$TMP/bin:$PATH" run is_whole_disk /dev/sda
  [ "$status" -eq 0 ]
  LSBLK_TYPE=part PATH="$TMP/bin:$PATH" run is_whole_disk /dev/sda1
  [ "$status" -ne 0 ]
  PATH="$TMP/bin:$PATH" run is_whole_disk /dev/does-not-exist
  [ "$status" -ne 0 ]
}

@test "unattended validation refuses a --disk that is not a whole disk" {
  f="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  grep -q 'is_whole_disk "\$DISK" || die' "$f"
}

@test "erase mode unmounts the target disk before wipefs/sgdisk -Z run" {
  f="$BATS_TEST_DIRNAME/../profile/airootfs/usr/local/bin/cyberos-install"
  before=$(grep -n 'unmount_disk "\$DISK"' "$f" | head -1 | cut -d: -f1)
  after=$(grep -n 'wipefs -af "\$DISK"' "$f" | head -1 | cut -d: -f1)
  [ -n "$before" ]
  [ -n "$after" ]
  [ "$before" -lt "$after" ]
}
