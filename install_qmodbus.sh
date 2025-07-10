#!/bin/bash
set -e

FORCE_INSTALL=0

if [[ "$1" == "--force" ]]; then
    FORCE_INSTALL=1
fi

echo "[+] Checking if QModBus is already installed..."
if command -v qmodbus &>/dev/null && [[ "$FORCE_INSTALL" -ne 1 ]]; then
    echo "[✔] QModBus is already installed at: $(which qmodbus)"
    echo "    Use './install_qmodbus.sh --force' to reinstall."
    exit 0
fi

echo "[+] Installing build dependencies..."
sudo apt update
sudo apt install -y git qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools build-essential

BUILD_DIR="/tmp/qmodbus-build"

echo "[+] Cleaning build directory..."
rm -rf "$BUILD_DIR"

echo "[+] Cloning QModBus source via GitHub..."
git clone https://github.com/ed-chemnitz/qmodbus.git "$BUILD_DIR"

cd "$BUILD_DIR"

echo "[+] Building QModBus with qmake..."
qmake
make -j"$(nproc)"

echo "[+] Installing QModBus system-wide..."
sudo make install

echo "[✔] QModBus successfully installed!"
