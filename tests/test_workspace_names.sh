#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_home=$(mktemp -d)
trap 'rm -rf -- "$test_home"' EXIT
mkdir -p "$test_home/.config/omarchy" "$test_home/fake-bin"
cat > "$test_home/.config/omarchy/shell.json" <<'JSON'
{"bar":{"layout":{"left":[{"id":"tester.workspaces","names":{"1":"Main"}}],"center":[],"right":[]}}}
JSON

cat > "$test_home/fake-bin/omarchy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == menu && $2 == input ]]; then
  printf '%s' "${FAKE_INPUT:-}"
elif [[ $1 == bar && $2 == set && $3 == tester.workspaces && $4 == names && $6 == --json ]]; then
  scratch=$(mktemp)
  jq --argjson names "$5" '.bar.layout.left[0].names = $names' \
    "$HOME/.config/omarchy/shell.json" > "$scratch"
  mv "$scratch" "$HOME/.config/omarchy/shell.json"
elif [[ $1 == plugin && $2 == clone && $3 == omarchy.workspaces ]]; then
  plugin_dir="$HOME/.config/omarchy/plugins/tester.workspaces"
  mkdir -p "$plugin_dir"
  printf '%s\n' '{"schemaVersion":1,"id":"tester.workspaces","name":"Named Workspaces","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Workspaces.qml"},"omarchy":{"clonedFrom":"omarchy.workspaces"}}' > "$plugin_dir/manifest.json"
  printf 'stock widget\n' > "$plugin_dir/Workspaces.qml"
elif [[ $1 == plugin && $2 == validate ]]; then
  jq -e '.id == "tester.workspaces" and .omarchy.clonedFrom == "omarchy.workspaces"' "$3/manifest.json" >/dev/null
  [[ -f $3/Workspaces.qml ]]
else
  printf 'Unexpected omarchy invocation: %s\n' "$*" >&2
  exit 1
fi
SH
cat > "$test_home/fake-bin/hyprctl" <<'SH'
#!/usr/bin/env bash
[[ $1 == -j && $2 == activeworkspace ]] || exit 1
printf '{"id":3}\n'
SH
chmod +x "$test_home/fake-bin/omarchy" "$test_home/fake-bin/hyprctl"

export HOME="$test_home" USER=tester PATH="$test_home/fake-bin:$PATH"
command="$repo/workspace-names/omarchy-workspace-name"
"$repo/workspace-names/install.sh" >/dev/null
"$repo/workspace-names/install.sh" >/dev/null
[[ -x $HOME/.local/bin/omarchy-workspace-name ]]
[[ $(< "$HOME/.config/omarchy/plugins/tester.workspaces/Workspaces.qml") == *'moduleName: "tester.workspaces"'* ]]

"$command" 2 Code >/dev/null
jq -e '.bar.layout.left[0].names == {"1":"Main","2":"Code"}' "$HOME/.config/omarchy/shell.json" >/dev/null
FAKE_INPUT=Planning "$command" --current >/dev/null
jq -e '.bar.layout.left[0].names["3"] == "Planning"' "$HOME/.config/omarchy/shell.json" >/dev/null
"$command" 2 --clear >/dev/null
jq -e '.bar.layout.left[0].names == {"1":"Main","3":"Planning"}' "$HOME/.config/omarchy/shell.json" >/dev/null
FAKE_INPUT='' "$command" --prompt 3 >/dev/null
jq -e '.bar.layout.left[0].names == {"1":"Main"}' "$HOME/.config/omarchy/shell.json" >/dev/null
if "$command" 11 Invalid >/dev/null 2>&1; then
  printf 'Expected workspace 11 to be rejected.\n' >&2
  exit 1
fi
printf 'personal widget\n' > "$HOME/.config/omarchy/plugins/tester.workspaces/Workspaces.qml"
if "$repo/workspace-names/install.sh" >/dev/null 2>&1; then
  printf 'Expected installer to preserve a changed widget.\n' >&2
  exit 1
fi
printf 'PASS: Named workspace install, set, prompt, clear, and bounds.\n'
