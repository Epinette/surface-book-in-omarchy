#!/usr/bin/env bash
# Optional US / Canadian Multilingual Standard / Simplified Chinese input for Omarchy 4.
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
input=$config_home/hypr/input.lua
profile=$config_home/fcitx5/profile
fcitx_config=$config_home/fcitx5/config
command_target=$HOME/.local/bin/omarchy-input-language-sync
service_target=$config_home/systemd/user/omarchy-input-language-sync.service

fail() { printf 'keyboard-languages: %s\n' "$*" >&2; exit 1; }

(( EUID != 0 )) || fail 'Run as your desktop user, without sudo.'
[[ -f $input && ! -L $input ]] || fail "Expected a regular Omarchy input file at $input"
for command in omarchy hyprctl systemctl python3 sha256sum; do
  command -v "$command" >/dev/null || fail "Missing command: $command"
done
for target in "$profile" "$fcitx_config"; do
  [[ ! -L $target ]] || fail "Review symlink $target before installing."
done

# Do not silently replace another input-method setup.
python3 - "$profile" <<'PY'
import configparser
from pathlib import Path
import sys

path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit(0)
config = configparser.ConfigParser(interpolation=None)
config.optionxform = str
try:
    config.read(path)
    sections = set(config.sections())
    items = [config[f"Groups/0/Items/{n}"].get("Name") for n in range(3)
             if f"Groups/0/Items/{n}" in config]
except (configparser.Error, KeyError) as error:
    raise SystemExit(f"Cannot read Fcitx profile: {error}")
allowed = ({"Groups/0", "Groups/0/Items/0", "GroupOrder"},
           {"Groups/0", "Groups/0/Items/0", "Groups/0/Items/1",
            "Groups/0/Items/2", "GroupOrder"})
if sections not in allowed or items not in (["keyboard-us"],
                                              ["keyboard-us", "keyboard-ca", "pinyin"],
                                              ["keyboard-us", "keyboard-ca-multix", "pinyin"]):
    raise SystemExit("Fcitx profile has other input methods; review it and the "
                     "documented manual steps before replacing it.")
PY

for target in "$command_target" "$service_target"; do
  if [[ -e $target || -L $target ]]; then
    [[ -f $target && ! -L $target ]] || fail "Review existing $target before installing."
    source_file=$here/$(basename "$target")
    if ! cmp -s -- "$source_file" "$target"; then
      # An exact copy of the previous sync command can be upgraded safely.
      old_sync_sha=fd4274cdbcc6d2e96b74239eb882ac207ecbab42ac79e96b43c9918c5b394b08
      current_sha=$(sha256sum < "$target")
      [[ $target == "$command_target" && ${current_sha%% *} == "$old_sync_sha" ]] ||
        fail "Review existing $target before installing."
    fi
  fi
done

python3 - "$input" "$here/input.lua.append" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
block = Path(sys.argv[2]).read_text().strip()
old_block = block.replace("Canadian Multilingual Standard", "French (Canada)").replace(
    'kb_variant = ",multix,"', 'kb_variant = ",fr,"')
start = "-- BEGIN surface-book-in-omarchy keyboard languages"
end = "-- END surface-book-in-omarchy keyboard languages"
if start in text or end in text:
    if text.count(start) != 1 or text.count(end) != 1 or not any(
        candidate in text for candidate in (block, old_block)
    ):
        raise SystemExit("The existing keyboard-language block was changed; review it first.")
PY

# Omarchy already runs Fcitx5. Only its Chinese engine and editor are missing.
omarchy pkg add fcitx5-chinese-addons fcitx5-configtool

mkdir -p -- "$state_home"
backup_dir=$(mktemp -d "$state_home/omarchy-input-languages-XXXXXXXX")
for source_file in "$input" "$profile" "$fcitx_config"; do
  if [[ -f $source_file ]]; then
    cp -p -- "$source_file" "$backup_dir/$(basename "$(dirname "$source_file")")-$(basename "$source_file")"
  fi
done
printf 'Saved existing input configuration in %s\n' "$backup_dir"

# Fcitx writes its profile on exit. Stop it before replacing that profile.
systemctl --user stop omarchy-fcitx5.service
restart_fcitx() { systemctl --user start omarchy-fcitx5.service || true; }
trap restart_fcitx EXIT

mkdir -p -- "$(dirname "$profile")" "$(dirname "$service_target")"
install -m 644 -- "$here/profile" "$profile"
python3 - "$fcitx_config" <<'PY'
import configparser
import os
from pathlib import Path
import tempfile
import sys

path = Path(sys.argv[1])
config = configparser.ConfigParser(interpolation=None)
config.optionxform = str
if path.exists():
    config.read(path)
if not config.has_section("Behavior"):
    config.add_section("Behavior")
config["Behavior"]["ActiveByDefault"] = "False"
config["Behavior"]["ShareInputState"] = "All"
with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as tmp:
    config.write(tmp, space_around_delimiters=False)
    temp_path = tmp.name
os.chmod(temp_path, 0o644)
os.replace(temp_path, path)
PY

python3 - "$input" "$here/input.lua.append" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
snippet = Path(sys.argv[2]).read_text()
new = snippet.strip()
old = new.replace("Canadian Multilingual Standard", "French (Canada)").replace(
    'kb_variant = ",multix,"', 'kb_variant = ",fr,"')
text = path.read_text()
if old in text:
    path.write_text(text.replace(old, new, 1))
elif new not in text:
    path.write_text(text + snippet)
PY
install -Dm755 -- "$here/omarchy-input-language-sync" "$command_target"
install -Dm644 -- "$here/omarchy-input-language-sync.service" "$service_target"

systemctl --user start omarchy-fcitx5.service
trap - EXIT
hyprctl reload
errors=$(hyprctl configerrors)
[[ -z $errors ]] || fail "Hyprland reported errors: $errors"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-input-language-sync.service
systemctl --user is-active --quiet omarchy-input-language-sync.service || fail 'Input sync service did not start.'
printf 'Installed US, Canadian Multilingual Standard, and Simplified Chinese Pinyin. Press Left Alt + Right Alt to cycle.\n'
