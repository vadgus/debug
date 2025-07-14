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

# disable crash reporting (Ubuntu / Debian / Raspberry Pi OS)
os_name=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
if [[ "$os_name" == "ubuntu" ]]; then
  # Ubuntu/Xubuntu: disable apport
  sed -i 's/^enabled=1$/enabled=0/' /etc/default/apport 2>/dev/null || echo 'enabled=0' > /etc/default/apport
  systemctl stop apport.service 2>/dev/null || true
  systemctl disable apport.service 2>/dev/null || true
else
  # Debian / Raspberry Pi OS: disable core dumps and reportbug
  sysctl -w kernel.core_pattern=core
  echo 'kernel.core_pattern=core' > /etc/sysctl.d/99-disable-coredump.conf

  systemctl stop whoopsie.service 2>/dev/null || true
  systemctl disable whoopsie.service 2>/dev/null || true

  apt purge -y reportbug 2>/dev/null || true
fi

# install python venv support
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
apt-get install -y "python$PYTHON_VERSION-venv" "python$PYTHON_VERSION-tk"

# suppress motd / legal / apt news
find /etc/update-motd.d/ -type f -exec chmod -x {} \;
find /etc/update-motd.d/ -type f ! -name '*header*' ! -name '98-reboot-required' -exec chmod -x {} \;
pro config set apt_news=false 2>/dev/null || true
sed -i '/pam_motd\.so.*\/etc\/legal/ s/^/#/' /etc/pam.d/login 2>/dev/null || true
rm -f /etc/legal 2>/dev/null || true
truncate -s 0 /etc/motd 2>/dev/null || true
touch "$user_home/.hushlogin"

# safer autologin setup
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

if ! grep -q "^alias upgrade=" "$bashrc_file"; then
  echo "alias upgrade='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y'" >> "$bashrc_file"
fi

# install Docker if not present
if ! command -v docker &>/dev/null; then
  if command -v snap &>/dev/null && ! grep -qi raspberry /etc/os-release; then
    snap install docker
  else
    apt-get install -y docker.io
  fi
  groupadd docker || true
  usermod -aG docker "$real_user"
fi

# determine DE
desktop_env=$(sudo -u "$real_user" dbus-launch env | grep XDG_CURRENT_DESKTOP | cut -d= -f2 | tr '[:upper:]' '[:lower:]')
desktop_env=${desktop_env:-$(pgrep -u $real_user -a | grep -Eo '(xfce4-session|gnome-session)' | cut -d- -f1)}

# XFCE setup
if [[ "$desktop_env" == *"xfce"* ]] && [[ -n "$DISPLAY" ]]; then
  apt-get install -y greybird-gtk-theme elementary-icon-theme

  # force theme
  sudo -u "$real_user" xfconf-query -c xsettings -p /Net/ThemeName -s "Greybird-dark" || \
    sudo -u "$real_user" xfconf-query -c xsettings -p /Net/ThemeName --create -t string -s "Greybird-dark"

  # force icon theme
  sudo -u "$real_user" xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary-xfce-dark" || \
    sudo -u "$real_user" xfconf-query -c xsettings -p /Net/IconThemeName --create -t string -s "elementary-xfce-dark"

  # screensaver
  if sudo -u "$real_user" xfconf-query -c xfce4-screensaver -l | grep -q /saver; then
    sudo -u "$real_user" xfconf-query -c xfce4-screensaver -p /saver -s blank-only
  fi

  # notifications
  sudo -u "$real_user" xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s true || true

  # set black wallpaper for all monitors and workspaces
  echo "Applying black background to all XFCE monitors..."
  paths=$(sudo -u "$real_user" xfconf-query -c xfce4-desktop -l | grep 'last-image' | sed -E 's#/last-image##' | sort -u)

  for base in $paths; do
    echo "  → Applying on: $base"

    # remove existing wallpaper config if exists
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p "$base/last-image" -r 2>/dev/null || true
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p "$base/image-path" -r 2>/dev/null || true

    # set black background
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p "$base/last-image" --create -t string -s "" || true
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p "$base/image-path" --create -t string -s "" || true
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p "$base/color-style" --create -t int -s 0 || true
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p "$base/rgba1" --create -t string -s "0;0;0;1" || true
    sudo -u "$real_user" xfconf-query -c xfce4-desktop -p "$base/image-style" --create -t int -s 0 || true
  done

  echo "Restarting xfdesktop..."
  sleep 1
  sudo -u "$real_user" xfdesktop --replace > /dev/null 2>&1 &

  # autostart GUI-time theme apply
  mkdir -p "$user_home/.config/autostart"
  cat <<EOF > "$user_home/.config/autostart/xfce-apply-theme.desktop"
[Desktop Entry]
Type=Application
Name=Apply XFCE Theme and Background
Exec=sh -c '
sleep 2
xfconf-query -c xsettings -p /Net/ThemeName -s Greybird-dark
xfconf-query -c xsettings -p /Net/IconThemeName -s elementary-xfce-dark
xfconf-query -c xfce4-desktop -l | grep last-image | sed -E "s#/last-image##" | sort -u | while read base; do
  xfconf-query -c xfce4-desktop -p "\$base/last-image" --create -t string -s ""
  xfconf-query -c xfce4-desktop -p "\$base/image-path" --create -t string -s ""
  xfconf-query -c xfce4-desktop -p "\$base/color-style" --create -t int -s 0
  xfconf-query -c xfce4-desktop -p "\$base/rgba1" --create -t string -s "0;0;0;1"
  xfconf-query -c xfce4-desktop -p "\$base/image-style" --create -t int -s 0
done
xfdesktop --replace
xfwm4 --replace
' &
X-GNOME-Autostart-enabled=true
EOF
  chown "$real_user:$real_user" "$user_home/.config/autostart/xfce-apply-theme.desktop"
  chmod +x "$user_home/.config/autostart/xfce-apply-theme.desktop"
fi

# GNOME setup
if [[ "$desktop_env" == *"gnome"* ]]; then
  apt-get install -y gnome-tweaks

  # Create script that disables bash history during execution
  mkdir -p "$user_home/.config"
  cat <<'EOF' > "$user_home/.config/gnome-apply-dark.sh"
#!/bin/bash

# Temporarily disable bash history
unset HISTFILE
export HISTFILE=/dev/null
export HISTSIZE=0
export HISTFILESIZE=0
set +o history

# Enable Ubuntu dark mode (since 22.04+)
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Black desktop background
gsettings set org.gnome.desktop.background picture-uri ''
gsettings set org.gnome.desktop.background picture-options 'none'
gsettings set org.gnome.desktop.background primary-color '#000000'
gsettings set org.gnome.desktop.background color-shading-type 'solid'

# Black screensaver
gsettings set org.gnome.desktop.screensaver picture-uri ''
gsettings set org.gnome.desktop.screensaver picture-options 'none'
gsettings set org.gnome.desktop.screensaver primary-color '#000000'
gsettings set org.gnome.desktop.screensaver color-shading-type 'solid'

# Re-enable history just in case
set -o history
EOF

  chmod +x "$user_home/.config/gnome-apply-dark.sh"
  chown "$real_user:$real_user" "$user_home/.config/gnome-apply-dark.sh"

  # Create autostart entry to apply it on login (not interactive — not logged in history)
  mkdir -p "$user_home/.config/autostart"
  cat <<EOF > "$user_home/.config/autostart/gnome-apply-dark.desktop"
[Desktop Entry]
Type=Application
Exec=$user_home/.config/gnome-apply-dark.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Apply GNOME Dark Mode
Comment=Enable dark mode and black background/screensaver
EOF

  chown "$real_user:$real_user" "$user_home/.config/autostart/gnome-apply-dark.desktop"
fi

# install qmodbus (external script)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/install_qmodbus.sh)" || true

echo "System configuration complete."
