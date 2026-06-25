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

# Allow the live user to log in without a password if the display manager path
# fails. Root starts locked from the airootfs shadow file.
passwd -d live

cat >/etc/plasmalogin.conf <<'EOF'
[Autologin]
User=live
Session=plasma.desktop
Relogin=true
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

enable_service_if_present plasmalogin.service
enable_service_if_present NetworkManager.service
enable_service_if_present bluetooth.service
enable_service_if_present power-profiles-daemon.service
enable_service_if_present pacman-init.service
systemctl set-default graphical.target
