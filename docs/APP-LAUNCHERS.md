# Optimized application launchers

These launch profiles target the Blade hybrid-graphics layout: Plasma Wayland
runs on the Intel `7d67` display device, while the NVIDIA `2c18` GPU remains
available for CUDA and compute workloads.

## Zen Browser

`~/.local/bin/zen-browser` sets `MOZ_ENABLE_WAYLAND=1` and launches the packaged
browser. The local `zen.desktop` override routes launcher actions and URL opens
through that wrapper. Native Wayland avoids the extra XWayland presentation copy
and keeps mixed-DPI input and 120 Hz output behavior consistent.

No forced WebRender, VA-API, sandbox, or driver-workaround preferences are used.
Zen/Firefox already chooses those from its runtime graphics probe, and stale
forced preferences are a common source of browser crashes after driver updates.

## Antigravity

The Arch launcher already reads `~/.config/antigravity-flags.conf`. The setup
adds only:

```text
--ozone-platform=wayland
```

Antigravity's Electron 39 build already enables Ozone and Wayland window
decorations. Repeating its full feature switch would risk replacing internal
defaults, so experimental raster, zero-copy, and disabled-workaround flags are
deliberately excluded.

## Zed

Zed renders through Vulkan. The wrapper sets `ZED_DEVICE_ID=0x7d67`, the Intel
GPU already driving Plasma, to avoid PRIME frame copies and unpredictable device
selection. This follows Zed's supported device-selection interface.

For a one-off RTX-backed session, override the default:

```bash
ZED_DEVICE_ID=0x2c18 zeditor
```

That is useful for GPU-heavy editor experiments, but the Intel device is usually
the faster and more power-efficient path for normal text UI on this display
topology.

## Verification and rollback

```bash
./scripts/verify-app-launchers.sh
```

Close every window of an application before testing a changed launcher; Zen and
Antigravity otherwise forward the request to the already-running process.

To return to package defaults, remove the two local desktop overrides, the two
wrappers, and `~/.config/antigravity-flags.conf`. The system package files under
`/usr` are never modified.

References: [Zen Linux installation](https://docs.zen-browser.app/guides/install-linux),
[Zed on Linux](https://zed.dev/docs/linux), and
[Zed Linux backend behavior](https://zed.dev/docs/development/linux).
