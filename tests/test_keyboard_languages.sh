#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_home=$(mktemp -d)
trap 'rm -rf -- "$test_home"' EXIT
mkdir -p "$test_home/.config/hypr" "$test_home/.config/fcitx5" "$test_home/fake-bin"
cat > "$test_home/.config/hypr/input.lua" <<'LUA'
hl.config({ input = { touchpad = { natural_scroll = true } } })
LUA
cat > "$test_home/.config/fcitx5/profile" <<'PROFILE'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=keyboard-us
[Groups/0/Items/0]
Name=keyboard-us
[GroupOrder]
0=Default
PROFILE
cat > "$test_home/.config/fcitx5/config" <<'CONFIG'
[Hotkey/TriggerKeys]
0=Control+space
CONFIG
cat > "$test_home/fake-bin/omarchy" <<'SH'
#!/usr/bin/env bash
[[ $1 == pkg && $2 == add && $3 == fcitx5-chinese-addons && $4 == fcitx5-configtool ]]
SH
cat > "$test_home/fake-bin/systemctl" <<'SH'
#!/usr/bin/env bash
[[ $1 == --user ]]
SH
cat > "$test_home/fake-bin/hyprctl" <<'SH'
#!/usr/bin/env bash
case "$1" in
  reload) printf 'ok\n' ;;
  configerrors) ;;
  *) exit 1 ;;
esac
SH
chmod +x "$test_home/fake-bin/omarchy" "$test_home/fake-bin/systemctl" "$test_home/fake-bin/hyprctl"

export HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" XDG_STATE_HOME="$test_home/.local/state"
export PATH="$test_home/fake-bin:$PATH"
"$repo/keyboard-languages/install.sh" >/dev/null
"$repo/keyboard-languages/install.sh" >/dev/null

[[ $(rg -c '^-- BEGIN surface-book-in-omarchy keyboard languages$' "$HOME/.config/hypr/input.lua") == 1 ]]
rg -q 'natural_scroll = true' "$HOME/.config/hypr/input.lua"
rg -q 'kb_layout = "us,ca,cn"' "$HOME/.config/hypr/input.lua"
rg -q '^Name=pinyin$' "$HOME/.config/fcitx5/profile"
rg -q '^ShareInputState=All$' "$HOME/.config/fcitx5/config"
rg -q '^0=Control\+space$' "$HOME/.config/fcitx5/config"
[[ -x $HOME/.local/bin/omarchy-input-language-sync ]]
[[ -f $HOME/.config/systemd/user/omarchy-input-language-sync.service ]]

# A laptop with other input methods must not lose them on install.
sed -i 's/^Name=pinyin$/Name=rime/' "$HOME/.config/fcitx5/profile"
if "$repo/keyboard-languages/install.sh" >/dev/null 2>&1; then
  printf 'Expected custom Fcitx profile to be preserved.\n' >&2
  exit 1
fi
rg -q '^Name=rime$' "$HOME/.config/fcitx5/profile"
printf 'PASS: Keyboard language install, repeat install, and custom-profile guard.\n'
