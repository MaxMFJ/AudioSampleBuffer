#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifacts_dir="$script_dir/artifacts"
publish_dir="$artifacts_dir/win-x64"
archive="$artifacts_dir/SoundDesk-win-x64.zip"

dotnet publish "$script_dir/WindowsDesktopPlayer.csproj" \
  --configuration Release \
  --runtime win-x64 \
  --self-contained true \
  --property:EnableWindowsTargeting=true \
  --output "$publish_dir"

(cd "$artifacts_dir" && zip -qrFS "$archive" win-x64)
printf 'Windows test package: %s\n' "$archive"
