#!/usr/bin/env bash
# One-time provisioning. Run this ON THE PI, not on the Mac.
#
# The Pi compiles nothing. The binary is built on the Mac inside an aarch64
# Linux container and copied across, so there is no Rust toolchain here, no
# build-essential, and no swap to enlarge. What the Pi needs is the SDL2
# runtime, composite video, and device access.
set -euo pipefail

CONFIG=/boot/firmware/config.txt

echo "==> Installing the SDL2 runtime"
# libsdl2-2.0-0 rather than libsdl2-dev: no headers are needed because nothing
# is compiled here. It pulls in the libdrm and libgbm the KMSDRM backend uses.
sudo apt update
sudo apt install -y libsdl2-2.0-0

echo "==> Enabling composite output"
sudo cp "$CONFIG" "$CONFIG.bak.$(date +%s)"
# The ,composite suffix on the KMS overlay is what actually enables the TRRS
# output; it defaults to NTSC.
if grep -q '^dtoverlay=vc4-kms-v3d' "$CONFIG"; then
  sudo sed -i 's/^dtoverlay=vc4-kms-v3d.*/dtoverlay=vc4-kms-v3d,composite/' "$CONFIG"
else
  echo 'dtoverlay=vc4-kms-v3d,composite' | sudo tee -a "$CONFIG" > /dev/null
fi
# Not needed by the KMS driver, but it gives a firmware bootsplash on composite,
# which is the fastest way to tell "the Pi isn't outputting" apart from "my code
# isn't drawing".
grep -q '^enable_tvout=1' "$CONFIG" || echo 'enable_tvout=1' | sudo tee -a "$CONFIG" > /dev/null

echo "==> Adding $USER to video, render, input"
# Outside of X, SDL reads input directly from evdev. Without the input group the
# game runs fine and silently receives no keyboard or gamepad events.
sudo usermod -aG video,render,input "$USER"

echo
echo "Reboot now. HDMI goes dark; composite becomes the only output."
echo "  sudo reboot"
echo
echo "Then confirm the connector exists without needing to look at the TV:"
echo "  ls /sys/class/drm/     # expect a card0-Composite-1 entry"
