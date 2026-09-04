#!/usr/bin/env bash
# shellcheck disable=SC2034
# CyberOS — departmental Arch Linux spin (Hyprland + Pixie SDDM)

iso_name="cyberos"
iso_label="CYBEROS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Cyber Department"
iso_application="CyberOS Live / Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd: much faster to build and to boot than xz; slightly larger image.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-wheel"]="0:0:440"
  ["/etc/sudoers.d/20-live-student"]="0:0:440"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"
  ["/root/customize_airootfs.sh"]="0:0:755"
  # mkarchiso copies airootfs/ with --no-preserve=mode, so anything needing the
  # execute bit must be listed here — git's 755 on the source file is not enough.
  ["/usr/local/bin/cyberos-theme"]="0:0:755"
  ["/usr/local/bin/cyberos-session"]="0:0:755"
  ["/usr/local/bin/cyberos-install"]="0:0:755"
  ["/usr/local/bin/cyberos-install-gui"]="0:0:755"
  ["/usr/local/bin/cyberos-firstboot"]="0:0:755"
  ["/usr/local/bin/cyberos-repair-boot"]="0:0:755"
  ["/usr/local/bin/cyberos-files"]="0:0:755"
  ["/usr/local/bin/cyberos-images"]="0:0:755"
  ["/usr/local/bin/cyberos-systemhealth-state"]="0:0:755"
  ["/usr/local/bin/cyberos-toggle-touchscreen"]="0:0:755"
  ["/usr/local/bin/cyberos-monitor-arrange"]="0:0:755"
  ["/usr/local/bin/cyberos-cloud-drives"]="0:0:755"
)
