#!/usr/bin/env bash
set -Eeuo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/install-common.sh
source "$REPO/scripts/install-common.sh"

usage() {
  cat <<'HELP'
Usage: ./uninstall.sh [--remove-dma-workaround]

Remove unchanged app files and the desktop entry owned by this installer.
Modified files, backups, packages, and unrelated configuration are preserved.

  --remove-dma-workaround  Also remove the exact managed boot hold configuration
                          and rebuild the running kernel's initramfs through
                          Omarchy's Limine tooling (administrator required)
  --help                   Show this help

No running driver is unloaded. Changes to the boot hold take effect after a
later manual reboot. This does not change the current boot's IOMMU mode.
HELP
}

main() {
  local remove_dma=0 arg key hash extra path kept=0
  for arg in "$@"; do
    case "$arg" in
      --remove-dma-workaround) remove_dma=1 ;;
      -h|--help) usage; return ;;
      *) usage >&2; fail "Unknown option: $arg" ;;
    esac
  done
  (( EUID != 0 )) || fail 'Run this uninstaller as your regular desktop user, not with sudo.'
  install_paths
  if (( remove_dma )); then admin "$REPO/scripts/configure-workaround" disable; fi
  if [[ ! -f $MANIFEST || -L $MANIFEST ]]; then
    note 'No valid install manifest was found; user app files were left untouched.'
    return
  fi
  UNINSTALL_MANIFEST=$(mktemp "$APP_STATE/.uninstall-XXXXXX")
  trap 'rm -f -- "$UNINSTALL_MANIFEST"' EXIT
  while IFS=$'\t' read -r key hash extra; do
    if ! path=$(owned_path "$key") || [[ ! $hash =~ ^[0-9a-f]{64}$ || -n $extra ]]; then
      note 'Ignoring an unrecognized install-manifest entry.'
      continue
    fi
    if [[ ! -e $path && ! -L $path ]]; then continue; fi
    if [[ -f $path && ! -L $path && $(file_hash "$path") == "$hash" ]]; then
      rm -- "$path"
      note "Removed $path"
    else
      note "Preserved modified file: $path"
      printf '%s\t%s\n' "$key" "$hash" >> "$UNINSTALL_MANIFEST"
      kept=1
    fi
  done < "$MANIFEST"
  if (( kept )); then
    chmod 600 "$UNINSTALL_MANIFEST"
    mv -fT -- "$UNINSTALL_MANIFEST" "$MANIFEST"
  else
    rm -- "$MANIFEST"
  fi
  refresh_desktop
  if (( !remove_dma )) && [[ -e /etc/modprobe.d/90-surface-camera-hold.conf ]]; then
    note 'Boot hold configuration retained. Use --remove-dma-workaround to remove the exact managed configuration.'
  fi
  note 'Uninstall complete. Backups and installed system packages were retained.'
}

main "$@"
