#!/usr/bin/env bash

set -euo pipefail

enable_service_if_present() {
  local unit="$1"

  if [[ -f "/usr/lib/systemd/system/${unit}" || -f "/etc/systemd/system/${unit}" ]]; then
    systemctl enable "${unit}"
  fi
}

if ! id -u live >/dev/null 2>&1; then
  useradd -m -G wheel,audio,video,storage,input -s /usr/bin/bash live
fi

# Lock direct root login on the live image and allow the live user to log in
# without a password if the display manager path fails.
passwd -l root
passwd -d live

install -d -m 0755 /etc/sddm.conf.d
cat >/etc/sddm.conf.d/veldmuis-live.conf <<'EOF'
[General]
DisplayServer=x11

[Autologin]
User=live
Session=plasma.desktop
Relogin=false
EOF

install -d -m 0750 -o live -g live /home/live
install -d -m 0755 -o live -g live /home/live/Desktop
install -m 0755 /etc/skel/Desktop/Veldmuis\ Installer.desktop \
  /home/live/Desktop/Veldmuis\ Installer.desktop
chown live:live /home/live/Desktop/Veldmuis\ Installer.desktop
chmod 0755 /home/live/Desktop/Veldmuis\ Installer.desktop
chmod 0755 /usr/local/bin/veldmuis-calamares-launcher
chmod 0755 /usr/local/bin/veldmuis-calamares-root-runner

install -d -m 0755 /etc/sudoers.d
cat >/etc/sudoers.d/00-live <<'EOF'
live ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/00-live

# The stock mirrorlist package ships fully commented mirrors. A live installer
# needs at least one active Arch mirror before Calamares can bootstrap the target.
cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://europe.mirror.pkgbuild.com/$repo/os/$arch
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
EOF

if [[ -x /usr/bin/flatpak && -f /usr/share/flatpak/remotes.d/flathub.flatpakrepo ]]; then
  flatpak remote-add --if-not-exists --system --from \
    flathub /usr/share/flatpak/remotes.d/flathub.flatpakrepo
fi

enable_service_if_present sddm.service
enable_service_if_present NetworkManager.service
enable_service_if_present bluetooth.service
enable_service_if_present udisks2.service
enable_service_if_present power-profiles-daemon.service
enable_service_if_present pacman-init.service
enable_service_if_present spice-vdagentd.service
systemctl set-default graphical.target
