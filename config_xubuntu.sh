#!/bin/bash
set -e

real_user=$(logname)
bashrc_file="/home/$real_user/.bashrc"

echo "[*] Installing base packages..."
apt update
apt install -y openssh-server git curl

echo "[*] Adding passwordless sudo for $real_user..."
echo "$real_user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/$real_user
chmod 0440 /etc/sudoers.d/$real_user

echo "[*] Setting system locale and timezone..."
update-locale LANG=en_US.UTF-8
update-locale LC_TIME=en_ZW.UTF-8
timedatectl set-timezone Europe/Warsaw
source /etc/default/locale

echo "[*] Installing available Python virtual environments..."
apt install -y python3.10-venv || true

if apt-cache show python3.12-venv >/dev/null 2>&1; then
    apt install -y python3.12-venv
else
    echo "[*] python3.12-venv not available on this system — skipping."
fi

echo "[*] Fixing APT sources..."
# Convert http to https
sed -i -E 's|http://|https://|g' /etc/apt/sources.list
# Change country-specific Ubuntu archive domains to .pl
sed -i -E 's|[a-z]{2}\.archive\.ubuntu\.com|pl.archive.ubuntu.com|g' /etc/apt/sources.list
sed -i -E 's|[a-z]{2}\.security\.ubuntu\.com|security.ubuntu.com|g' /etc/apt/sources.list

echo "[*] Updating APT again..."
apt update

echo "[*] Disabling apt motd news..."
find /etc/update-motd.d/ -type f -exec chmod -x {} \;
find /etc/update-motd.d/ -type f \( -name '*header*' -o -name '*reboot-required*' \) -exec chmod +x {} \;
pro config set apt_news=false 2>/dev/null || true

echo "[*] Setting LightDM autologin..."
echo -e "[Seat:*]\nautologin-user=$real_user\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf
chmod 644 /etc/lightdm/lightdm.conf
systemctl restart lightdm

echo "[*] Disabling unattended-upgrades..."
systemctl disable unattended-upgrades

echo "[*] Configuring XFCE screensaver..."
sudo -u $real_user dbus-launch xfconf-query -c xfce4-screensaver -p /saver --create -t string -s blank-only

echo "[*] Configuring aliases..."
# Replace or add 'll' alias
if grep -q "^alias ll=" "$bashrc_file"; then
    sed -i "s|^alias ll=.*|alias ll='ls -lah'|" "$bashrc_file"
else
    echo "alias ll='ls -lah'" >> "$bashrc_file"
fi

# Add alias for upgrade wrapped in tmux
echo "alias upgrade='command -v tmux >/dev/null || sudo apt install -y tmux && tmux new-session -d -s update \"sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo reboot\"'" >> "$bashrc_file"

echo "[✓] System configuration complete. You may reboot now."
