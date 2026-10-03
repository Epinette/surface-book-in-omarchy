# Surface Book 2 on Omarchy

Tested, reversible workarounds for Surface Book 2 hardware on Omarchy:

- a front-camera bridge for browser video calls; and
- an Intel AVS workaround for grainy built-in speaker output.

For the camera, install the small **Camera feed** terminal app. Press
**Super + Space**, search for **Camera feed**, then type `open` or `close`.
For speaker noise, follow the [audio guide](docs/audio.md) and use the guarded
`scripts/configure-audio` helper.

These setups were tested on one Surface Book 2 running Omarchy 4.0.4 and kernel
`7.2.5-3-omarchy`. They are hardware-specific workarounds, not new drivers or a
promise of compatibility with every Surface or kernel.

## What you get

- `install.sh`: missing dependencies, user commands, and a searchable launcher.
- **Camera feed**: `open`, `close`, `status`, `help`, and `quit` commands.
- `surface-camera`: diagnostics, capture tests, and a browser webcam bridge.
- An **optional, explicitly enabled** workaround for the tested IPU3 DMA fault.
- [`scripts/configure-audio`](scripts/configure-audio): check, apply, and roll
  back the tested Intel AVS speaker workaround.
- An optional [named-workspace widget](workspace-names/README.md) with a command
  and keyboard prompt for labels on workspaces 1–10.
- An optional [three-language keyboard setup](keyboard-languages/README.md) for
  US English, French (Canada), and Simplified Chinese Pinyin, switched with both
  Alt keys.
- `uninstall.sh` and automated tests that do not access camera hardware.

The app opens with the camera off. Closing its window, pressing Ctrl+D, or
typing `quit` stops the feed it started. Reopening the launcher focuses the
existing app window. No camera capture is configured at login or boot.

## Compatibility and limits

| Component | Tested setup |
| --- | --- |
| Computer | Microsoft Surface Book 2 |
| Image processor | Intel IPU3, `8086:1919`, PCI `0000:00:05.0` |
| Front sensor | OV5693, `\_SB_.PCI0.I2C2.CAMF` |
| Desktop | Omarchy 4.0.4 / Hyprland / Foot |
| Kernel | `7.2.5-3-omarchy` |
| Camera stack | libcamera 0.7.2, v4l2loopback 0.15.4 |
| Output | 1280 × 720 at approximately 29 fps, virtual `/dev/video42` |
| Browser test | Chromium 152, `getUserMedia`, 30 received video frames |
| Audio controller | Intel `8086:9d71`, Realtek ALC298 codec |
| Working audio path | Intel AVS (`snd_soc_avs`) |

The rear-camera command exists but was not hardware-tested. IR / Windows Hello
is not implemented. Microphone setup is separate. A Zoom or WhatsApp call was
not placed during validation; their website must offer calling and allow camera
access. Picture quality and tuning remain limitations of the Linux camera stack.
See the [linux-surface camera support guide](https://github.com/linux-surface/linux-surface/wiki/Camera-Support).

## Camera install

Run these commands as your normal desktop user, not from a root shell:

```bash
git clone https://github.com/Epinette/surface-book-in-omarchy.git
cd surface-book-in-omarchy
./install.sh
```

The installer uses Omarchy to install missing packages, including libcamera,
GStreamer, v4l2loopback/DKMS, matching kernel headers, Python, and Foot. It installs
the commands under `~/.local/bin` and creates a desktop launcher. Existing user
files it replaces are backed up. It does not start the camera, upgrade the
whole system, unload drivers, or reboot.

An existing installation with dependencies already available can use:

```bash
./install.sh --app-only
```

This skips package and hardware setup. It does not grant consent for the DMA
workaround. The packaged capture helper requires the explicit opt-in below.

## Speaker audio

If built-in speaker output sounds grainy or like white noise while Windows 11
sounds clean, inspect the machine with:

```bash
./scripts/configure-audio check
```

The tested failure was below PipeWire: direct ALSA playback also produced the
noise, while the legacy HDA driver logged repeated stream DMA errors. The
working workaround selects Intel AVS at boot. Read the full
[speaker-noise guide](docs/audio.md) before applying it; the helper includes
exact hardware guards, conflict checks, rollback state, and an Omarchy UKI
rebuild. It never unloads a live driver or reboots automatically.

## Optional named workspaces

To show labels such as **Main** or **Code** beside the workspace indicators,
follow the [named-workspace guide](workspace-names/README.md). Its installer
clones Omarchy's built-in workspace widget into your user config and installs
the naming command. The camera installer does not change your bar or bindings.

## Optional keyboard languages

To reproduce the English (US), French (Canada), and Simplified Chinese Pinyin
setup on another Omarchy 4 laptop, follow the
[keyboard-language guide](keyboard-languages/README.md) and run its separate
installer. **Left Alt + Right Alt** cycles all three, with US English first.
The setup uses Omarchy's XKB layout switch and a small user service to keep
Fcitx5's input method in step. The camera installer does not change keyboard
settings.

## Optional camera DMA workaround

**Read this before enabling:** the tested kernel failed to start the camera with
a DMA fault. Unloading or unbinding the image-processor driver also caused a
kernel fault, so these scripts never attempt either operation.

The workaround removes **IOMMU DMA memory isolation for the internal camera
controller only**. A faulty controller could access memory outside its normal
camera buffers. Other devices retain their protection. The helper verifies that
the camera is the only device in its IOMMU group and refuses otherwise.
This tradeoff follows the [kernel's IOMMU group interface](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-kernel-iommu_groups).

If you accept that tradeoff, run:

```bash
./install.sh --enable-dma-workaround
```

This writes a small camera-driver blacklist and rebuilds the running kernel's
Omarchy/Limine boot image. It also records your user-level opt-in. **Save your
work and reboot manually before first use if instructed.** The installer never
restarts the computer itself.

After a clean boot, `open` prepares the camera before loading its driver. A
system password dialog may appear. DMA isolation returns at reboot, and the
workaround is applied again only when you explicitly start or prepare the camera.
The blacklist persists until removed. Other software cannot use the built-in
camera while its image-processor driver remains held unloaded.

If the driver is already loaded without the workaround, the helper refuses to
detach it. Follow the setup/reboot instructions instead of trying `rmmod`,
`modprobe -r`, or PCI unbind commands.

## Use the app

1. Press **Super + Space**, type **Camera feed**, and press Enter.
2. Type `open`, then press Enter. If authentication is needed, use the system
   password dialog. Ctrl+C cancels startup.
3. Wait for **Camera is OPEN**. Reload the video-call webpage, allow camera
   access, and select **Surface Camera**.
4. Leave the app window open during the call.
5. Type `close` to stop the feed, or `quit` to stop it and exit.

`status` shows whether the app's camera process is running. `close` stops only
the feed owned by this app; it will not kill a camera producer in another window.
The startup check consumes two video frames without saving images. Diagnostic
text is kept in `~/.local/state/camera-feed/feed.log` and replaced on each start.
This project does not record or upload footage; a calling website uses the feed
when you permit it.

## Command-line use

```bash
surface-camera doctor          # Hardware, packages, device permissions
surface-camera prepare         # Opted-in preparation for this boot, no capture
surface-camera test front      # Two bounded capture tests; no images saved
surface-camera webcam front    # Feed the browser camera until Ctrl+C
surface-camera preview         # qcam preview; close before starting another feed
surface-camera-dma status      # Inspect the camera's DMA mode
```

To change output size or orientation for one terminal session:

```bash
SURFACE_CAMERA_SIZE=640x480 surface-camera webcam front
SURFACE_CAMERA_FLIP=2 surface-camera webcam front
```

`SURFACE_CAMERA_FLIP=2` rotates 180 degrees; the default is unchanged. The app
inherits these environment variables if launched from a shell that sets them.
Only one helper capture command may run at a time.

## Troubleshooting

- **Missing package indexes:** some fresh Omarchy images have only offline
  package metadata. The installer stops. Complete a normal Omarchy update when
  convenient, reboot if it updates the kernel, and rerun the installer. This
  project does not run a standalone `pacman -Sy` or mix downloaded packages.
- **Missing matching headers or loopback module:** ensure installed kernel files
  match `uname -r`. Check `dkms status` and run `surface-camera doctor`.
- **Another camera command is running:** close its camera terminal or qcam before
  typing `open`. Repeated `open` in the same app does not start another producer.
- **Zoom has no picture:** wait for the app to report OPEN before reloading the
  webpage and selecting **Surface Camera**. The virtual device advertises capture
  only while a producer is attached; see [v4l2loopback's exclusive-caps option](https://github.com/v4l2loopback/v4l2loopback#options).
- **A kernel fault occurred this boot:** stop testing. Save work and arrange a
  clean restart. The helpers block further capture and never reload the driver
  to recover from this state.
- **Unvalidated kernel or different hardware:** do not assume this workaround is
  needed or sufficient. Keep diagnostics and consult upstream camera support.

## Remove

Stop the feed and exit the app, then use the checkout:

```bash
./uninstall.sh
```

User files are removed only when they still match the installer's ownership
record; modified files are preserved. Packages and system boot configuration
remain installed. To also remove this project's camera startup hold:

```bash
./uninstall.sh --remove-dma-workaround
```

This rebuilds the boot image but does not unload a driver or reboot. Reboot
manually to restore the original boot behavior and DMA isolation. The original
camera limitation may return. The low-level `surface-camera-dma restore` command
is usable only while the camera driver is still unloaded.

## Development and validation

```bash
./tests/run.sh
```

Tests require Python 3, Bash, desktop-file-utils, GStreamer tools and base plugins.
They cover command lifecycle, duplicate instances, startup errors, termination,
camera selection, GStreamer argument escaping, consent gates, and the guarded
audio configuration/rollback logic, plus the optional keyboard installer. They
use temporary files, fake camera processes, or synthetic GStreamer frames,
never live hardware. GitHub Actions
runs the same checks.

The initial hardware validation received live front-camera frames repeatedly,
tested the V4L2 bridge and Chromium API, and confirmed clean stop/start behavior.
No firmware or package binaries are distributed here.

## Background

- [Matching IPU3 DMA fault discussed by an Intel IOMMU maintainer](https://lkml.iu.edu/hypermail/linux/kernel/2301.0/04069.html)
- [libcamera GStreamer documentation](https://libcamera.org/getting-started.html)
- [linux-surface project](https://github.com/linux-surface/linux-surface)

MIT licensed. This project is independent of Microsoft, Omarchy, and linux-surface.
