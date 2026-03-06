#!/usr/bin/env bash

set -euo pipefail

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

install -d -m 0755 /etc/sudoers.d
cat >/etc/sudoers.d/00-live <<'EOF'
live ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/00-live

systemctl enable sddm.service
systemctl enable NetworkManager.service
systemctl set-default graphical.target
