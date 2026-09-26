#!/usr/bin/env bash
set -Eeuo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/install-common.sh
source "$REPO/scripts/install-common.sh"

usage() {
  cat <<'HELP'
Usage: ./install.sh [--app-only | --enable-dma-workaround]

Default: install missing dependencies through Omarchy, then install the app
and its desktop entry for the current user. Run as your desktop user.

  --app-only               Install user files only; skip hardware/dependency setup
  --enable-dma-workaround  Also opt in to the camera-only DMA isolation bypass
  --help                   Show this help

The optional workaround holds the IPU3 driver at boot. The app can later place
only the validated camera IOMMU group in identity mode, reducing DMA isolation
for that device. Administrator authentication is required for boot changes.
No capture, driver unloading, or reboot is performed by this installer.
If the driver is already loaded, save your work and reboot manually later.
HELP
}

main() {
  local app_only=0 enable_dma=0 arg name
  for arg in "$@"; do
    case "$arg" in
      --app-only) app_only=1 ;;
      --enable-dma-workaround) enable_dma=1 ;;
      -h|--help) usage; return ;;
      *) usage >&2; fail "Unknown option: $arg" ;;
    esac
  done
  (( !app_only || !enable_dma )) || fail '--app-only cannot be combined with --enable-dma-workaround.'
  (( EUID != 0 )) || fail 'Run this installer as your regular desktop user, not with sudo.'
  install_paths
  command -v python3 >/dev/null || { (( !app_only )) || fail 'python3 is required; install the documented dependencies first.'; }
  for name in "${APP_NAMES[@]}"; do
    [[ -f $REPO/bin/$name ]] || fail "Missing packaged program: bin/$name"
  done
  if (( !app_only )); then bash "$REPO/bin/surface-camera" setup; fi
  command -v python3 >/dev/null || fail 'python3 is required to create the desktop entry.'

  mkdir -p -- "$APP_STATE"
  INSTALL_SCRATCH=$(mktemp -d "$APP_STATE/.install-XXXXXX")
  trap 'rm -rf -- "$INSTALL_SCRATCH"' EXIT
  NEW_MANIFEST=$INSTALL_SCRATCH/manifest
  : > "$NEW_MANIFEST"
  write_desktop_entry > "$INSTALL_SCRATCH/camera-feed.desktop"
  if command -v desktop-file-validate >/dev/null; then
    desktop-file-validate "$INSTALL_SCRATCH/camera-feed.desktop"
  fi
  if (( enable_dma )); then
    note 'Opt-in: the camera-only workaround reduces DMA isolation for the camera device.'
    admin "$REPO/scripts/configure-workaround" enable
  fi
  for name in "${APP_NAMES[@]}"; do install_owned "bin/$name" "$REPO/bin/$name" 755; done
  install_owned applications/camera-feed.desktop "$INSTALL_SCRATCH/camera-feed.desktop" 644

  if (( enable_dma )); then
    printf 'camera-only-identity\n' > "$INSTALL_SCRATCH/consent"
    install_owned config/allow-dma-workaround "$INSTALL_SCRATCH/consent" 600
  elif [[ -f $MANIFEST ]]; then
    # Preserve ownership of an unchanged consent marker on app-only upgrades.
    local key hash extra path
    while IFS=$'\t' read -r key hash extra; do
      [[ $key == config/allow-dma-workaround && $hash =~ ^[0-9a-f]{64}$ && -z $extra ]] || continue
      path=$(owned_path "$key")
      if [[ -f $path && ! -L $path && $(file_hash "$path") == "$hash" ]]; then
        printf '%s\t%s\n' "$key" "$hash" >> "$NEW_MANIFEST"
      fi
    done < "$MANIFEST"
  fi
  chmod 600 "$NEW_MANIFEST"
  mv -fT -- "$NEW_MANIFEST" "$MANIFEST"
  refresh_desktop
  note 'Installed Camera feed. Open it from the application launcher.'
  note "Command: $APP_BIN/camera-feed"
  if (( !enable_dma )) && [[ ! -f $APP_CONFIG/allow-dma-workaround ]]; then
    note 'The DMA workaround is not authorized. See README.md before explicitly opting in.'
  fi
}

main "$@"
