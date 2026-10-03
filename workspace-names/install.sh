#!/usr/bin/env bash
# Install the optional named-workspace widget into the current Omarchy session.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
plugin_id="${USER:-$(id -un)}.workspaces"
plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
command_target="$HOME/.local/bin/omarchy-workspace-name"

fail() { printf 'workspace-names: %s\n' "$*" >&2; exit 1; }

(( EUID != 0 )) || fail 'Run as your desktop user, without sudo.'
[[ $plugin_id =~ ^[A-Za-z0-9._-]+$ ]] || fail "Unsupported plugin ID: $plugin_id"
for tool in omarchy jq sed cmp; do
  command -v "$tool" >/dev/null || fail "Missing command: $tool"
done
[[ -f $HOME/.config/omarchy/shell.json ]] || fail 'Omarchy shell.json was not found.'

scratch=$(mktemp)
trap 'rm -f -- "$scratch"' EXIT
sed "s/__PLUGIN_ID__/$plugin_id/g" "$repo_dir/Workspaces.qml.in" > "$scratch"

# Existing files may contain personal changes. Refuse to replace them.
if [[ -e $command_target && ! -L $command_target ]] && ! cmp -s "$repo_dir/omarchy-workspace-name" "$command_target"; then
  fail "$command_target already exists with different content. Back it up or review it before installing."
fi
[[ ! -L $command_target ]] || fail "$command_target is a symlink; review it before installing."
if [[ -e $plugin_dir || -L $plugin_dir ]]; then
  [[ -d $plugin_dir && ! -L $plugin_dir ]] || fail "$plugin_dir is not a regular directory."
  jq -e --arg id "$plugin_id" '.id == $id and .omarchy.clonedFrom == "omarchy.workspaces"' \
    "$plugin_dir/manifest.json" >/dev/null || fail "$plugin_dir is not the expected Omarchy workspace clone."
  if [[ -e $plugin_dir/Workspaces.qml ]] && ! cmp -s "$scratch" "$plugin_dir/Workspaces.qml"; then
    fail "$plugin_dir/Workspaces.qml has different content. Back it up or review it before installing."
  fi
else
  omarchy plugin clone omarchy.workspaces
  [[ -d $plugin_dir ]] || fail "The clone was not created at $plugin_dir."
fi

install -m 644 "$scratch" "$plugin_dir/Workspaces.qml"
install -Dm755 "$repo_dir/omarchy-workspace-name" "$command_target"
omarchy plugin validate "$plugin_dir"

printf 'Installed %s and %s\n' "$plugin_id" "$command_target"
printf 'Add the optional Super+Alt+N binding from workspace-names/README.md.\n'
