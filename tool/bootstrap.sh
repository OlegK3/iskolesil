#!/usr/bin/env bash
# Создаёт Android-проект (android/) во временной папке и копирует его сюда,
# затем применяет патч (разрешения, foreground service, localhost-only cleartext).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [ ! -d android ]; then
  S=$(mktemp -d)
  flutter create --project-name iskolesil --org ru.iskolesil --platforms android "$S/app"
  cp -r "$S/app/android" ./android
fi
python3 tool/patch_android.py "$ROOT"
