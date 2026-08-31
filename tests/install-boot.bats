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

@test "valid_hostname accepts a plain label" {
  run valid_hostname "cyberos"
  [ "$status" -eq 0 ]
  run valid_hostname "lab-07"
  [ "$status" -eq 0 ]
}

@test "valid_hostname rejects a value that would corrupt /etc/hosts or the ANSI summary box" {
  run valid_hostname $'evil\nline'
  [ "$status" -ne 0 ]
  run valid_hostname "<b>x</b>"
  [ "$status" -ne 0 ]
}

@test "valid_hostname rejects a leading or trailing hyphen" {
  run valid_hostname "-bad"
  [ "$status" -ne 0 ]
  run valid_hostname "bad-"
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
