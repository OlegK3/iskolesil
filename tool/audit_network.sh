#!/usr/bin/env bash
# Статический аудит: нет запрещённых зарубежных облачных SDK/телеметрии в зависимостях,
# и список всех URL в исходниках приложения (карта — Яндекс MapKit, ключ в коде отсутствует).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
BAD='firebase|crashlytics|sentry|google_maps|google_mobile_ads|mapbox|supabase|amplitude|mixpanel|appsflyer|facebook|onesignal|posthog'
if [ -f pubspec.lock ] && grep -Eiq "^  ($BAD)" pubspec.lock; then
  echo "ЗАПРЕЩЁННАЯ ЗАВИСИМОСТЬ:"; grep -Ei "^  ($BAD)" pubspec.lock; exit 1
fi
echo "== URL в lib/ (допустимы только документальные ссылки) =="
grep -rnoE "https?://[^'\" )]+" lib | sort -u || true
echo "Аудит зависимостей пройден. Динамический аудит трафика на устройстве нужно провести отдельно (docs/TESTING.md)."
