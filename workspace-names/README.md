# Named Omarchy workspaces

This optional setup adds text labels beside the numbered workspace indicators in
Omarchy's top or bottom bar. Unnamed workspaces keep the stock number or focused
dot. A vertical bar stays compact, and hovering shows the name. Labels are saved
in `~/.config/omarchy/shell.json`, so they survive a shell restart. The widget
also displays a live Hyprland workspace rename when no saved label exists.

This is the setup used on the author's Surface Book 2 with Omarchy 4.0.4. It
copies Omarchy's built-in `omarchy.workspaces` widget into your user config, then
changes only that copy. Omarchy's packaged files remain untouched.

## Install

Run from an Omarchy desktop session as your regular user:

```bash
./workspace-names/install.sh
```

The script needs `jq`, `sed`, and Omarchy's `omarchy plugin` commands. It calls
`omarchy plugin clone omarchy.workspaces`, which puts a personal workspace widget
at `~/.config/omarchy/plugins/<username>.workspaces/` and switches the bar to it.
It installs the QML in this directory and the naming command at
`~/.local/bin/omarchy-workspace-name`. It stops if either destination already has
different custom content, so you can review or back it up first. Run
`omarchy plugin validate "$HOME/.config/omarchy/plugins/${USER:-$(id -un)}.workspaces"` to
check the installed manifest again. The shell normally reloads plugin changes
on save; `omarchy-shell shell rescanPlugins` can force a rescan.

The naming command uses the same `<username>.workspaces` ID as the clone. If
your clone uses another ID, set `OMARCHY_WORKSPACE_WIDGET_ID` to that ID when
running the command.

## Name and clear workspaces

```bash
~/.local/bin/omarchy-workspace-name 1 "Main"
~/.local/bin/omarchy-workspace-name 2 "Code"
~/.local/bin/omarchy-workspace-name            # List 1–10
~/.local/bin/omarchy-workspace-name 2 --clear
~/.local/bin/omarchy-workspace-name --current  # Prompt for the active workspace
```

The `--current` and `--prompt <number>` modes use `omarchy menu input`. Submit
an empty value to clear a label. Numbered workspaces 1–10 are supported;
workspace 10 appears as `0` in the bar, matching Omarchy's stock indicator.

To bind the graphical prompt to **Super + Alt + N**, first check whether that
key already has a binding with `omarchy menu keybindings --print`. If it already
runs `omarchy-workspace-name --current`, this step is done. Otherwise, add this
line to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + N", "Name current workspace", os.getenv("HOME") .. "/.local/bin/omarchy-workspace-name --current")
```

If the key is already bound, add `hl.unbind("SUPER + ALT + N")` before the new
binding. Hyprland reloads user config on save; run `hyprctl reload` and
`hyprctl configerrors` to verify it.

## Remove

Remove the binding line from `~/.config/hypr/bindings.lua`, then run
`omarchy plugin remove "${USER}.workspaces"` to restore the stock widget.
Remove `~/.local/bin/omarchy-workspace-name` if you no longer need the command.
Review the plugin's saved `names` map in `~/.config/omarchy/shell.json` before
removing it if you want to keep a copy of your labels.
