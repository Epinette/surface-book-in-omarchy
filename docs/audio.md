# Surface Book 2 speaker noise on Omarchy

This is a tested workaround for grainy or white-noise-like built-in speaker
output on one Microsoft Surface Book 2 running Omarchy. The same speakers were
clean under Windows 11. On Linux, the legacy Intel HDA path logged repeated DMA
FIFO errors while audio played.

The workaround selects Intel AVS (`snd_soc_avs`) instead of the legacy
`snd_hda_intel` DSP path. It does not replace PipeWire, change volume, retask
speaker pins, or install a custom kernel.

## Tested hardware and symptoms

| Component | Tested value |
| --- | --- |
| Computer | Microsoft Surface Book 2 |
| Audio controller | Intel Sunrise Point-LP HD Audio, `8086:9d71` |
| Codec | Realtek ALC298, vendor `10ec:0298`, subsystem `10ec:10ca` |
| Omarchy | 4.0.4 |
| Kernel | `7.2.5-3-omarchy` |
| PipeWire / WirePlumber | 1.6.8 / 0.5.17 |
| Failing driver | `snd_hda_intel` |
| Working driver | `snd_soc_avs` |

The failure also occurred with direct ALSA playback, which ruled out a browser
or PipeWire-only problem. During longer playback the kernel repeatedly logged:

```text
snd_hda_intel 0000:00:1f.3: stream 7 dma error: 0x28
```

`0x2c` was also observed. Disabling HDA power saving and trying legacy HDA
timing parameters (`position_fix`, `bdl_pos_adj`, and MSI selection) did not
survive a 30-second playback test. They are not part of this fix.

## Apply safely

Run the inspection first as your normal user:

```bash
./scripts/configure-audio check
```

The script refuses to apply unless it sees the exact Surface Book 2 model and
Intel `8086:9d71` controller. If ALSA exposes codec metadata, it also requires
the expected ALC298 codec. Review the output, then run:

```bash
sudo ./scripts/configure-audio apply
```

This writes the following managed file and rebuilds the running kernel's
Omarchy/Limine unified kernel image:

```text
/etc/modprobe.d/90-surface-book2-audio.conf
```

```conf
options snd_intel_dspcfg dsp_driver=4
```

If a different file already occupies that path, the script preserves it as
rollback state under `/var/lib/surface-book-in-omarchy/audio`. It also refuses
to continue when another `snd_intel_dspcfg` option or an active
`hda-jack-retask` artifact could make the result ambiguous.

The script never unloads the live audio driver and never restarts the computer.
After it succeeds, save your work and reboot manually:

```bash
omarchy system reboot
```

Do not try to make the change take effect immediately by unloading, unbinding,
or reprobeing the controller. The helper never calls `rmmod`, `modprobe -r`, PCI
bind/unbind, `driver_override`, or an audio-service restart. Apply and rollback
only stage the next boot. If a hot-switch or kernel oops has already occurred,
stop testing and reboot cleanly after saving your work.

## Verify after reboot

Run:

```bash
./scripts/configure-audio check
lspci -nnk -s 00:1f.3
wpctl status
```

The expected results are:

- `Active driver: snd_soc_avs`
- `DSP driver setting: 4`
- an AVS analog stereo sink for the built-in speakers
- no new `snd_hda_intel ... dma error` or `IRQ timing workaround` messages
  during at least 30 seconds of playback

AVS may report that `intel/avs/hda-10ec0298-tplg.bin` is absent and that it is
using `hda-generic-tplg.bin`. That fallback was present during the successful
test and did not prevent analog audio from working.

AVS also changes ALSA card names and numbers. The validated system exposed
`PROBE`, `HDAudio`, and `HDMI` cards, so software with a hard-coded `hw:N`
device may need its audio device selected again.

The live driver switch was validated with an audible tone and a 30-second
PipeWire stream with no new DMA, underrun, or timing errors. The persistent UKI
configuration was built successfully; because this repository does not reboot
machines automatically, confirm the post-reboot state using the checks above.

## Important pin-retask warning

Do **not** click **Apply now** in `hda-jack-retask` and do not write to an HDA
codec's sysfs `reconfig` file while AVS owns this device. On the tested kernel,
hot reconfiguration caused a kernel NULL-pointer oops in the HDA codec reset
path. The machine recovered, but this is unsafe to automate.

This codec pin-retask failure is distinct from the driver hot-switch warning
above; neither operation is needed for the AVS workaround.

If either of these active files exists, the apply command stops without making
changes:

```text
/etc/modprobe.d/hda-jack-retask.conf
/usr/lib/firmware/hda-jack-retask.fw
```

Move or disable those overrides deliberately, rebuild the UKI, and start from a
clean reboot before applying the AVS selection. Files whose names do not end in
`.conf` are not read as modprobe configuration.

## Roll back

From the same checkout, run:

```bash
sudo ./scripts/configure-audio rollback
```

Rollback restores the configuration saved before the first apply, rebuilds the
Omarchy UKI, and leaves the current live driver alone. Reboot manually afterward.
It refuses to remove the managed file if somebody has edited it since apply.

## Runbook for another agent

An agent working on another Surface Book 2 should follow this order:

1. Run `./scripts/configure-audio check` and retain its output.
2. Confirm the model is exactly `Surface Book 2`, PCI audio is `8086:9d71`, and
   the noisy path is `snd_hda_intel`. Do not generalize this fix to another
   Surface model or controller.
3. Inspect active modprobe and jack-retask configuration. Let the script stop on
   conflicts; do not silently delete user configuration.
4. Run `sudo ./scripts/configure-audio apply` in the user's terminal. Confirm the
   Limine rebuild completed without an error.
5. Ask the user to save work before rebooting. Do not reboot without their clear
   authorization.
6. After reboot, rerun `check`, select the AVS analog output if needed, play
   audio for at least 30 seconds, and inspect the current boot's kernel log for
   new DMA errors.
7. If audio is missing or worse, use `rollback`; do not hot-retask the codec or
   repeatedly unload/reload the audio stack.

This is a hardware-specific workaround, not an upstream driver fix. Preserve
diagnostics when testing newer kernels because the legacy-path defect may be
fixed—or AVS behavior may change—over time.
