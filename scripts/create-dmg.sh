#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 "Usage: $0 /path/to/Markowski.app /path/to/Markowski.dmg"
  exit 64
fi

app_path="$1"
output_path="$2"

if [[ ! -d "$app_path" || "${app_path:t}" != "Markowski.app" ]]; then
  print -u2 "Expected a Markowski.app bundle."
  exit 66
fi

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

ditto "$app_path" "$staging_dir/Markowski.app"
ln -s /Applications "$staging_dir/Applications"
rm -f "$output_path"

hdiutil create \
  -volname "Markowski Beta" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$output_path"
