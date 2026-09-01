#!/usr/bin/env bash
# One-time provisioning. Run this ON THE PI, not on the Mac. Safe to re-run.
#
# The Pi compiles nothing. The binary is built on the Mac inside an aarch64
# Linux container and copied across, so there is no Rust toolchain here, no
# build-essential, and no swap to enlarge. What the Pi needs is the SDL2
# runtime, an EGL stack, composite video, and device access.
set -euo pipefail

CONFIG=/boot/firmware/config.txt
UNIT=/etc/systemd/system/piblob-composite.service

echo "==> Installing the SDL2 runtime and its EGL dependencies"
# libsdl2-2.0-0 rather than libsdl2-dev: no headers are needed because nothing
# is compiled here.
#
# The EGL packages are not optional and are not pulled in automatically. SDL2
# dlopens libEGL.so.1 at runtime, so apt sees no dependency, but its KMSDRM
# backend builds every window on a GBM surface behind an EGL display. Without
# them SDL initializes the video driver and then fails window creation with
# "EGL not initialized". This is true even when you only ever intend to use the
# software renderer.
sudo apt update
sudo apt install -y libsdl2-2.0-0 libegl1 libegl-mesa0 libgles2

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

echo "==> Forcing the composite connector to report connected"
# Analog video has no load detection, so the vc4 encoder reports this connector
# as "unknown" forever, even with a TV attached and displaying. SDL2 only counts
# a connector as usable when it reports "connected" with at least one mode, so
# it concludes there is no display and refuses to bring up KMSDRM at all.
#
# Writing "on" to the connector's status overrides detection. This is done with
# a systemd unit rather than a "video=" kernel parameter: a malformed
# cmdline.txt on a board whose only output is composite is painful to recover
# from, while a failed unit still leaves a bootable machine.
sudo tee "$UNIT" > /dev/null <<'UNITEOF'
[Unit]
Description=Force the composite DRM connector to report connected
Documentation=https://github.com/wayjake/PiBlob
DefaultDependencies=no
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service
Before=piblob.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for c in /sys/class/drm/card*-Composite-*/status; do echo on > "$c"; done'

[Install]
WantedBy=multi-user.target
UNITEOF

sudo systemctl daemon-reload
sudo systemctl enable --now piblob-composite.service

echo "==> Adding $USER to video, render, input"
# Outside of X, SDL reads input directly from evdev. Without the input group the
# game runs fine and silently receives no keyboard or gamepad events.
sudo usermod -aG video,render,input "$USER"

echo
echo "Connector status now:"
for c in /sys/class/drm/card*-Composite-*/status; do echo "  $c -> $(cat "$c")"; done
echo
echo "If you changed config.txt for the first time, reboot. HDMI goes dark and"
echo "composite becomes the only output."
echo "  sudo reboot"
