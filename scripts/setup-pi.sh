#!/usr/bin/env bash
# One-time provisioning. Run this ON THE PI, not on the Mac.
set -euo pipefail

CONFIG=/boot/firmware/config.txt

echo "==> Installing packages"
sudo apt update
sudo apt install -y libsdl2-dev libdrm-dev libgbm-dev build-essential pkg-config rsync

echo "==> Enabling composite output"
sudo cp "$CONFIG" "$CONFIG.bak.$(date +%s)"
# The ,composite suffix on the KMS overlay is what actually enables the TRRS output.
if grep -q '^dtoverlay=vc4-kms-v3d' "$CONFIG"; then
  sudo sed -i 's/^dtoverlay=vc4-kms-v3d.*/dtoverlay=vc4-kms-v3d,composite/' "$CONFIG"
else
  echo 'dtoverlay=vc4-kms-v3d,composite' | sudo tee -a "$CONFIG" > /dev/null
fi
# Not needed by the KMS driver, but gives a firmware bootsplash on composite — the fastest
# way to tell "the Pi isn't outputting" apart from "my code isn't drawing".
grep -q '^enable_tvout=1' "$CONFIG" || echo 'enable_tvout=1' | sudo tee -a "$CONFIG" > /dev/null

echo "==> Adding $USER to video, render, input"
sudo usermod -aG video,render,input "$USER"

echo "==> Expanding swap to 2G for cargo builds"
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo dphys-swapfile setup
sudo dphys-swapfile swapon

echo
echo "Install Rust if you haven't:"
echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
echo
echo "Then reboot. HDMI will go dark; composite becomes the only output."
echo "  sudo reboot"
