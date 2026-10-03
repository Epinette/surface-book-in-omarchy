# US, Canadian French, and Simplified Chinese keyboards

This optional Omarchy 4 setup starts with **English (US)**. Press **Left Alt +
Right Alt together** to cycle through English (US), French (Canada), Simplified
Chinese Pinyin, and back to English. The order in which you press the two Alt
keys does not matter. The Omarchy bar shows the selected XKB layout; Chinese
uses a US-shaped physical layout while Fcitx5 converts Pinyin to Simplified
Chinese characters.

The setup was checked on a Surface Book 2 running Omarchy 4.0.4. It uses
Omarchy's user configuration and should also work on other Omarchy 4 laptops
with Fcitx5, Hyprland Lua configuration, and a normal left/right Alt keyboard.
It does not change the desktop display language or the login/console layout.

## Install on another laptop

From this repository checkout, run as the desktop user in a terminal:

```bash
./keyboard-languages/install.sh
```

The installer uses `omarchy pkg add` for `fcitx5-chinese-addons` and
`fcitx5-configtool`, so administrator authentication may appear. It backs up
existing input files under `~/.local/state/omarchy-input-languages-*`, then:

1. Adds the [three XKB layouts](input.lua.append) and `grp:alts_toggle` to
   `~/.config/hypr/input.lua`. The first layout remains `us` for Omarchy's
   shortcuts.
2. Sets [Fcitx5's input methods](profile) to `keyboard-us`, `keyboard-ca`, and
   `pinyin`; keeps the selected method across applications.
3. Installs the [sync command](omarchy-input-language-sync) and a user
   [systemd service](omarchy-input-language-sync.service). Hyprland's two-Alt
   shortcut only changes an XKB layout. The service notices each layout change
   and selects the matching Fcitx5 method, which is what makes the Chinese
   position produce characters rather than merely change the keyboard label.

The installer preserves your other settings in `input.lua` and Fcitx's global
config. It refuses to replace a Fcitx profile with other input methods or an
existing sync command/service with different content. Review and merge those
files manually if that laptop has a custom input setup. Re-running the
installer is safe when its marked `input.lua` block is unchanged.

After installation, open a text field and try the shortcut. Typing `nihao` in
the Chinese position should offer `你好`. Check the service and configuration
with:

```bash
systemctl --user status omarchy-input-language-sync.service
hyprctl configerrors
hyprctl devices -j | jq '.keyboards[] | select(.main) | .active_keymap'
fcitx5-remote -n
```

The bar reports Hyprland's layout. Fcitx5's method is shown by
`fcitx5-remote -n` while a text field has focus. Some applications do not
support Pinyin composition in their own search fields; test in a regular text
editor or browser text box first.

## Restore the earlier setup

Disable the sync service before restoring the backed-up files:

```bash
systemctl --user disable --now omarchy-input-language-sync.service
```

Copy the saved `hypr-input.lua`, `fcitx5-profile`, and `fcitx5-config` files
from the backup directory printed by the installer to their original paths.
Stop `omarchy-fcitx5.service` before restoring its profile, then start it
again so it does not write the old profile over your restored copy. Run
`hyprctl reload` and `hyprctl configerrors` afterward. The two installed sync
files can then be removed from `~/.local/bin/` and
`~/.config/systemd/user/`, followed by `systemctl --user daemon-reload`.

The packages remain installed; `omarchy pkg` can remove them separately if
they are no longer needed.
