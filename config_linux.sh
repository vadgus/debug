#!/bin/bash
set -e

# get real username
real_user=$(logname 2>/dev/null || who | awk '{print $1}' | head -n 1)
user_home="/home/$real_user"
bashrc_file="$user_home/.bashrc"

# install base packages
apt-get update
apt-get upgrade -y || true
apt-get install -y openssh-server curl git tmux sudo
apt-get autoremove -y
apt-get autoclean -y

# allow passwordless sudo
echo "$real_user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/$real_user
chmod 0440 /etc/sudoers.d/$real_user

# set locale and timezone
update-locale LANG=en_US.UTF-8
update-locale LC_TIME=en_ZW.UTF-8
source /etc/default/locale

# install python venv support
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
apt-get install -y "python$PYTHON_VERSION-venv" "python$PYTHON_VERSION-tk"

# suppress motd / legal / apt news
find /etc/update-motd.d/ -type f -exec chmod -x {} \;
find /etc/update-motd.d/ -type f \( -name '*header*' -o -name '98-reboot-required' \) -exec chmod +x {} \;
pro config set apt_news=false 2>/dev/null || true
sed -i '/pam_motd\.so.*\/etc\/legal/ s/^/#/' /etc/pam.d/login 2>/dev/null || true
rm -f /etc/legal 2>/dev/null || true
truncate -s 0 /etc/motd 2>/dev/null || true
touch "$user_home/.hushlogin"

# enable autologin in lightdm (safe version)
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<EOF > /etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=$real_user
autologin-user-timeout=0
EOF

# disable unused services
systemctl disable unattended-upgrades || true
systemctl disable apport || true
systemctl disable bluetooth || true

# useful aliases
if grep -q "^alias ll=" "$bashrc_file"; then
  sed -i "s|^alias ll=.*|alias ll='ls -lah'|" "$bashrc_file"
else
  echo "alias ll='ls -lah'" >> "$bashrc_file"
fi

# sed -i '/alias upgrade=/d' "$bashrc_file"
# echo "alias upgrade='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y'" >> "$bashrc_file"
if ! grep -q "^alias upgrade=" "$bashrc_file"; then
  echo "alias upgrade='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y'" >> "$bashrc_file"
fi

# install Docker if not present (avoid snap on Pi)
if ! command -v docker &>/dev/null; then
  if command -v snap &>/dev/null && ! grep -qi raspberry /etc/os-release; then
    snap install docker
  else
    apt-get install -y docker.io
  fi
  groupadd docker || true
  usermod -aG docker "$real_user"
  echo 'newgrp docker' >> "$bashrc_file"
fi

# determine DE more reliably
desktop_env=$(sudo -u "$real_user" dbus-launch env | grep XDG_CURRENT_DESKTOP | cut -d= -f2 | tr '[:upper:]' '[:lower:]')
desktop_env=${desktop_env:-$(pgrep -u $real_user -a | grep -Eo '(xfce4-session|gnome-session)' | cut -d- -f1)}

# XFCE setup
if [[ "$desktop_env" == *"xfce"* ]] && [[ -n "$DISPLAY" ]]; then
  apt-get install -y greybird-gtk-theme elementary-icon-theme

  # sudo -u "$real_user" xfconf-query -c xsettings -p /Net/ThemeName -s "Greybird-dark" --create -t string
  sudo -u "$real_user" xfconf-query -c xsettings -p /Net/ThemeName -s "Greybird-dark" || \
    sudo -u "$real_user" xfconf-query -c xsettings -p /Net/ThemeName --create -t string -s "Greybird-dark"

  # sudo -u "$real_user" xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary-xfce-dark" --create -t string
  sudo -u "$real_user" xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary-xfce-dark" || \
    sudo -u "$real_user" xfconf-query -c xsettings -p /Net/IconThemeName --create -t string -s "elementary-xfce-dark"

  if sudo -u "$real_user" xfconf-query -c xfce4-screensaver -l | grep -q /saver; then
    sudo -u "$real_user" xfconf-query -c xfce4-screensaver -p /saver -s blank-only
  fi

  sudo -u "$real_user" xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s true || true

  # sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "/usr/share/backgrounds/xfce/xfce-blue.jpg" || true
  sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "" || \
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image --create -t string -s ""

  sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/color-style -s 0 || \
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/color-style --create -t int -s 0

  sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/rgba1 -s "0;0;0;1" || \
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/rgba1 --create -t string -s "0;0;0;1"

  # restart XFCE session components
  sudo -u "$real_user" nohup xfwm4 --replace > /dev/null 2>&1 &
  sudo -u "$real_user" nohup xfdesktop --replace > /dev/null 2>&1 &

  mkdir -p "$user_home/.config/autostart"
  # cat <<EOF > "$user_home/.config/autostart/xfdesktop-reload.desktop"
  # [Desktop Entry]
  # Type=Application
  # Name=XFDesktop Reload
  # Exec=sh -c 'sleep 3 && pkill -HUP xfdesktop'
  # X-GNOME-Autostart-enabled=true
  # EOF

  # safer version
  rm -f "$user_home/.config/autostart/xfdesktop-reload.desktop" "$user_home/.config/autostart/xfdesktop-replace.desktop" || true
  cat <<EOF > "$user_home/.config/autostart/xfdesktop-replace.desktop"
[Desktop Entry]
Type=Application
Name=Restore XFDesktop
Exec=sh -c 'sleep 2 && nohup xfdesktop --replace > /dev/null 2>&1 &'
X-GNOME-Autostart-enabled=true
EOF
  chown "$real_user:$real_user" "$user_home/.config/autostart/xfdesktop-replace.desktop"
fi

# GNOME setup
if [[ "$desktop_env" == *"gnome"* ]]; then
  apt-get install -y gnome-tweaks

  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Yaru-dark'
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.notifications show-banners false || true
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' || true
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power power-saver-profile-on-low-battery false || true
fi

# install qmodbus (external script)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/install_qmodbus.sh)" || true

echo "[✓] System configuration complete."
