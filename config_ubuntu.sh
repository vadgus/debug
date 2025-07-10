#!/bin/bash
set -e

real_user=$(logname)
user_home="/home/$real_user"
bashrc_file="$user_home/.bashrc"

# install basic packages
apt update
apt install -y openssh-server curl git tmux

# allow passwordless sudo
echo "$real_user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/$real_user
chmod 0440 /etc/sudoers.d/$real_user

# set locale and timezone
update-locale LANG=en_US.UTF-8
update-locale LC_TIME=en_ZW.UTF-8
timedatectl set-timezone Europe/Warsaw
source /etc/default/locale

# install venv for system python
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
apt install -y "python$PYTHON_VERSION-venv"

# fix apt sources to use https and pl mirror
sed -i 's|http://|https://|g' /etc/apt/sources.list
sed -i -E 's|[a-z]{2,3}\.archive\.ubuntu\.com|pl.archive.ubuntu.com|g' /etc/apt/sources.list
sed -i -E 's|[a-z]{2,3}\.security\.ubuntu\.com|security.ubuntu.com|g' /etc/apt/sources.list

# update & upgrade after mirror switch
apt update
apt upgrade -y

# disable apt motd messages
find /etc/update-motd.d/ -type f -exec chmod -x {} \;
find /etc/update-motd.d/ -type f \( -name '*header*' -o -name '*reboot-required*' \) -exec chmod +x {} \;
pro config set apt_news=false 2>/dev/null || true

# enable autologin in lightdm
echo -e "[Seat:*]\nautologin-user=$real_user\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf
chmod 644 /etc/lightdm/lightdm.conf
systemctl restart lightdm || true

# disable unattended-upgrades
systemctl disable unattended-upgrades || true

# disable xfce screensaver if available
sudo -u $real_user dbus-launch xfconf-query -c xfce4-screensaver -p /saver --create -t string -s blank-only || true

# add useful aliases
if grep -q "^alias ll=" "$bashrc_file"; then
    sed -i "s|^alias ll=.*|alias ll='ls -lah'|" "$bashrc_file"
else
    echo "alias ll='ls -lah'" >> "$bashrc_file"
fi

echo "alias upgrade='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo reboot'" >> "$bashrc_file"

# install docker if missing
if ! command -v docker &>/dev/null; then
    snap install docker
    groupadd docker || true
    usermod -aG docker $real_user
    echo 'newgrp docker' >> "$bashrc_file"
fi

# apply dark theme if session is running
desktop_env=$(echo "${XDG_CURRENT_DESKTOP:-$(sudo -u $real_user printenv XDG_CURRENT_DESKTOP)}" | tr '[:upper:]' '[:lower:]')

if [[ "$desktop_env" == *"xfce"* ]] || pgrep -u $real_user xfce4-session >/dev/null 2>&1; then
    apt install -y greybird-gtk-theme
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/ThemeName -s "Greybird-dark" --create -t string
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary-xfce-dark" --create -t string
elif [[ "$desktop_env" == *"gnome"* ]] || pgrep -u $real_user gnome-session >/dev/null 2>&1; then
    apt install -y gnome-tweaks
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Yaru-dark'
fi

# install qmodbus from github
bash -c "$(curl -fsSL https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/install_qmodbus.sh)" || true

echo "[✓] System configuration complete. You may reboot now."
