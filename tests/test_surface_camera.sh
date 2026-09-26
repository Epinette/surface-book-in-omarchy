#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_dir/bin/surface-camera"

temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
export XDG_CONFIG_HOME="$temporary/config"
unset SURFACE_CAMERA_ID SURFACE_CAMERA_SIZE SURFACE_CAMERA_FLIP

# Invalid direct-helper invocation must stop before hardware inspection.
# An empty tool path also prevents cat/modprobe/etc. if the early gate regresses.
if PATH="$temporary/no-tools" "$BASH" "$repo_dir/bin/surface-camera-dma" enable \
    > "$temporary/dma-output" 2>&1; then
  printf 'The direct DMA helper accepted enable without explicit risk acceptance.\n' >&2
  exit 1
fi
[[ $(< "$temporary/dma-output") == 'ERROR: enable requires --accept-camera-dma-risk:'* ]]

# Consent must be checked before preparation or any privileged command.
# These stubs also keep this regression test harmless if that check breaks.
admin() { printf 'admin\n' >> "$temporary/preparation-calls"; return 99; }
capture_ready() { printf 'capture_ready\n' >> "$temporary/preparation-calls"; }
if workaround_authorized; then
  printf 'Missing consent unexpectedly authorized the workaround.\n' >&2
  exit 1
fi
if ( prepare_camera ) > "$temporary/preparation-output" 2>&1; then
  printf 'Camera preparation unexpectedly accepted missing consent.\n' >&2
  exit 1
fi
[[ ! -e $temporary/preparation-calls ]]
[[ $(< "$temporary/preparation-output") == *'opt in explicitly'* ]]
mkdir -p "$XDG_CONFIG_HOME/surface-camera"
consent="$XDG_CONFIG_HOME/surface-camera/allow-dma-workaround"
for contents in '' true camera-only-identity-extra; do
  printf '%s\n' "$contents" > "$consent"
  if workaround_authorized; then
    printf 'Invalid consent unexpectedly authorized the workaround: %s\n' "$contents" >&2
    exit 1
  fi
done
printf 'camera-only-identity\n' > "$consent"
workaround_authorized

# Everything below uses fake enumeration and synthetic GStreamer frames only.
capture_ready() { :; }
prepare_camera() { :; }
cam() {
  cat <<'CAM'
Available cameras:
1: Internal back camera (\_SB_.PCI0.I2C3.CAMR)
2: Internal front camera (\_SB_.PCI0.I2C2.CAMF)
3: External camera (/base/usb/camera)
CAM
}
# Stub only external tools; never call a package or privilege operation.
timeout() { shift; "$@"; }
gst-inspect-1.0() { return 0; }
select_camera front
[[ $CAMERA_ID == '\_SB_.PCI0.I2C2.CAMF' ]]
select_camera rear
[[ $CAMERA_ID == '\_SB_.PCI0.I2C3.CAMR' ]]
select_camera front
prepare_pipeline
[[ ${PIPELINE[3]} == 'camera-name="\\_SB_.PCI0.I2C2.CAMF"' ]]
# Test the actual GStreamer parser, using only a synthetic frame.
result=$(gst-launch-1.0 -v fakesrc num-buffers=1 '!' fakesink "${PIPELINE[3]/camera-name=/name=}" silent=false 2>&1)
[[ $result == *'GstFakeSink:\_SB_.PCI0.I2C2.CAMF:'* ]]
if ( SURFACE_CAMERA_FLIP=9 prepare_pipeline ) >/dev/null 2>&1; then exit 1; fi
if ( SURFACE_CAMERA_SIZE='1280x720 ! filesink' prepare_pipeline ) >/dev/null 2>&1; then exit 1; fi
if ( select_camera infrared ) >/dev/null 2>&1; then exit 1; fi
cam() { printf '%s\n' 'Available cameras:'; }
if ( select_camera front ) >/dev/null 2>&1; then exit 1; fi
cam() { printf '%s\n' '1: Front (ID_A)' '2: Front (ID_B)'; }
if ( select_camera front ) >/dev/null 2>&1; then exit 1; fi
SURFACE_CAMERA_ID='exact custom ID' select_camera front
[[ $CAMERA_ID == 'exact custom ID' ]]
SURFACE_CAMERA_ID='custom "quoted" ID ! harmless' select_camera front
prepare_pipeline
result=$(gst-launch-1.0 -v fakesrc num-buffers=1 '!' fakesink "${PIPELINE[3]/camera-name=/name=}" silent=false 2>&1)
[[ $result == *'GstFakeSink:custom "quoted" ID ! harmless:'* ]]
printf 'PASS: explicit DMA consent, camera selection, ambiguous/missing-camera handling, GStreamer ID preservation, and invalid option rejection.\n'
