#!/usr/bin/env bash
# Static gate for the Freenet Explorer plugin. No node, no display, no network.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail() {
  echo "tests/run.sh: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

manifest=$root/manifest.json
[[ -f $manifest ]] || fail "missing manifest.json"
jq -e . "$manifest" >/dev/null || fail "manifest.json is not valid JSON"

jq -e '.schemaVersion == 1' "$manifest" >/dev/null \
  || fail "schemaVersion must be the number 1"

jq -e '
  .id == "io.mcmurray.freenet-explorer"
  and (.name | type == "string" and length > 0)
  and (.version | type == "string" and length > 0)
  and (.kinds | type == "array" and length > 0)
  and (.entryPoints | type == "object")
' "$manifest" >/dev/null || fail "manifest is missing id, name, version, kinds, or entryPoints"

jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection"))) then
    .barWidget.defaultSection as $section
    | ($section | type) == "string"
      and (["left", "centerBegin", "center", "centerEnd", "tray", "right"] | index($section)) != null
  else
    true
  end
' "$manifest" >/dev/null || fail "barWidget.defaultSection is not a known bar section"

while IFS= read -r ep; do
  [[ -n $ep ]] || fail "entry point path is empty"
  [[ $ep != /* ]] || fail "entry point must be relative: $ep"
  [[ $ep != *..* ]] || fail "entry point must not contain ..: $ep"
  [[ -f $root/$ep ]] || fail "entry point file not found: $ep"
done < <(jq -r '.entryPoints | to_entries[] | .value' "$manifest")

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$root"
fi

if command -v qmllint >/dev/null 2>&1; then
  qmllint "$root"/*.qml
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$root"/tests/run.sh
  if [[ -f $root/bin/setup ]]; then
    shellcheck "$root"/bin/setup
  fi
fi

echo "ok"
