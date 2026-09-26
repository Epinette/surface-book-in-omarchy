#!/usr/bin/env bash
# Shared user-install helpers. This file never runs privileged operations itself.
set -Eeuo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

install_paths() {
  [[ -n ${HOME:-} && $HOME == /* ]] || fail 'HOME must be an absolute path.'
  APP_BIN=$HOME/.local/bin
  APP_DATA=${XDG_DATA_HOME:-$HOME/.local/share}/applications
  APP_CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}/surface-camera
  APP_STATE=${XDG_STATE_HOME:-$HOME/.local/state}/surface-camera
  local directory
  for directory in "$APP_BIN" "$APP_DATA" "$APP_CONFIG" "$APP_STATE"; do
    [[ $directory == /* && $directory != *$'\n'* && $directory != *$'\r'* && $directory != *$'\t'* ]] ||
      fail 'HOME and XDG paths must be absolute and contain no tabs or newlines.'
  done
  MANIFEST=$APP_STATE/install-manifest.tsv
  APP_NAMES=(camera-feed camera-feed-launch surface-camera surface-camera-dma)
}

owned_path() {
  case "$1" in
    bin/camera-feed|bin/camera-feed-launch|bin/surface-camera|bin/surface-camera-dma)
      printf '%s/%s' "$APP_BIN" "${1#bin/}" ;;
    applications/camera-feed.desktop) printf '%s/camera-feed.desktop' "$APP_DATA" ;;
    config/allow-dma-workaround) printf '%s/allow-dma-workaround' "$APP_CONFIG" ;;
    *) return 1 ;;
  esac
}

file_hash() { sha256sum < "$1" | cut -d ' ' -f 1; }

backup_existing() {
  local key=$1 path=$2
  if [[ -e $path || -L $path ]]; then
    [[ ! -d $path || -L $path ]] || fail "Refusing to replace directory: $path"
    if [[ -z ${BACKUP_DIR:-} ]]; then
      mkdir -p -- "$APP_STATE/backups"
      BACKUP_DIR=$(mktemp -d "$APP_STATE/backups/install-$(date +%Y%m%d-%H%M%S)-XXXXXX")
      note "Backing up replaced files to $BACKUP_DIR"
    fi
    mkdir -p -- "$BACKUP_DIR/$(dirname "$key")"
    cp -Pp -- "$path" "$BACKUP_DIR/$key"
  fi
}

install_owned() {
  local key=$1 source=$2 mode=$3 destination temporary
  destination=$(owned_path "$key") || fail "Unknown install file: $key"
  mkdir -p -- "$(dirname "$destination")"
  if [[ -L $destination || ! -f $destination ]] || ! cmp -s -- "$source" "$destination"; then
    backup_existing "$key" "$destination"
    temporary=$(mktemp "$(dirname "$destination")/.surface-camera-install-XXXXXX")
    install -m "$mode" -- "$source" "$temporary"
    mv -fT -- "$temporary" "$destination"
  else
    chmod "$mode" -- "$destination"
  fi
  printf '%s\t%s\n' "$key" "$(file_hash "$destination")" >> "$NEW_MANIFEST"
}

write_desktop_entry() {
  # Exec has two escaping layers: Desktop Entry string escapes, then argument
  # quoting. A literal percent must also be escaped as %% for field-code parsing.
  python3 - "$APP_BIN/camera-feed-launch" <<'PY'
import sys
path = sys.argv[1]
quoted = ''.join('\\' + c if c in '\\"`$' else c for c in path)
quoted = quoted.replace('\\', '\\\\').replace('%', '%%')
print('[Desktop Entry]\nType=Application\nName=Camera feed')
print('Comment=Start and stop the Surface Book 2 camera feed')
print('Exec="' + quoted + '"')
print('Icon=camera-video\nTerminal=false\nCategories=AudioVideo;Video;')
print('StartupNotify=false\nX-Surface-Camera-Managed=true')
PY
}

refresh_desktop() {
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$APP_DATA" || note 'Desktop database refresh failed; the app entry is installed.'
  fi
  # Older Omarchy launchers use Walker. Do not reset any desktop configuration.
  if command -v omarchy-refresh-applications >/dev/null; then
    omarchy-refresh-applications || note 'Application-menu refresh failed; reopen the launcher.'
  fi
}

admin() {
  if [[ -t 0 ]]; then
    command -v sudo >/dev/null || fail 'sudo is required for the optional boot configuration.'
    sudo /usr/bin/bash "$@"
  else
    command -v pkexec >/dev/null || fail 'Run this installer in a terminal for administrator authentication.'
    pkexec /usr/bin/bash "$@"
  fi
}
