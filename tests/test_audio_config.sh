#!/usr/bin/env bash
# Hardware-free tests for the audio configuration helper.
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../scripts/configure-audio
source "$repo_dir/scripts/configure-audio"

temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
SYS_ROOT=$temporary/sys
PROC_ROOT=$temporary/proc
ETC_ROOT=$temporary/etc
MODULES_ROOT=$temporary/modules
FIRMWARE_ROOT=$temporary/firmware
STATE_ROOT=$temporary/state/audio
CONFIG_PATH=$ETC_ROOT/modprobe.d/90-surface-book2-audio.conf
WORK_DIR=$temporary/work
mkdir -p "$SYS_ROOT/class/dmi/id" \
  "$SYS_ROOT/bus/pci/devices/0000:00:1f.3" \
  "$PROC_ROOT/asound/card0" "$ETC_ROOT/modprobe.d" "$FIRMWARE_ROOT" \
  "$WORK_DIR"

printf 'ID=omarchy\n' > "$ETC_ROOT/os-release"
printf 'Microsoft Corporation\n' > "$SYS_ROOT/class/dmi/id/sys_vendor"
printf 'Surface Book 2\n' > "$SYS_ROOT/class/dmi/id/product_name"
printf 'Surface Book 2\n' > "$SYS_ROOT/class/dmi/id/board_name"
printf '0x8086\n' > "$SYS_ROOT/bus/pci/devices/0000:00:1f.3/vendor"
printf '0x9d71\n' > "$SYS_ROOT/bus/pci/devices/0000:00:1f.3/device"
printf '0x8086\n' > "$SYS_ROOT/bus/pci/devices/0000:00:1f.3/subsystem_vendor"
printf '0x7270\n' > "$SYS_ROOT/bus/pci/devices/0000:00:1f.3/subsystem_device"
printf 'Codec: Realtek ALC298\nVendor Id: 0x10ec0298\n' > "$PROC_ROOT/asound/card0/codec#0"
managed_config > "$WORK_DIR/managed.conf"

validate_machine
if ( printf '0x1234\n' > "$SYS_ROOT/bus/pci/devices/0000:00:1f.3/device"; validate_machine ) \
    >/dev/null 2>&1; then
  printf 'Audio hardware guard accepted the wrong PCI device.\n' >&2
  exit 1
fi
printf '0x9d71\n' > "$SYS_ROOT/bus/pci/devices/0000:00:1f.3/device"

# With no preceding file, apply state must roll back to absence.
remember_original_config
[[ $(< "$STATE_ROOT/previous-state") == absent ]]
install_managed_config
config_is_managed
restore_original_config
[[ ! -e $CONFIG_PATH ]]
rm -rf -- "$STATE_ROOT"

# A preceding file is retained outside modprobe.d and restored exactly.
printf 'options snd_intel_dspcfg dsp_driver=1\n' > "$CONFIG_PATH"
cp "$CONFIG_PATH" "$temporary/expected-previous"
remember_original_config
[[ $(< "$STATE_ROOT/previous-state") == file ]]
install_managed_config
config_is_managed
restore_original_config
cmp -s "$temporary/expected-previous" "$CONFIG_PATH"

# Active jack-retask artifacts must stop apply before any boot work.
touch "$FIRMWARE_ROOT/hda-jack-retask.fw"
if ( validate_no_retask ) >/dev/null 2>&1; then
  printf 'Audio guard accepted an active hda-jack-retask artifact.\n' >&2
  exit 1
fi

printf 'PASS: audio hardware guard, managed configuration, rollback, and retask safety checks.\n'
