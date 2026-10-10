#!/usr/bin/env bash
# Generiše Flutter platformske foldere i ubacuje našu aplikaciju (app/).
# Upotreba: bash tools/prepare.sh android|windows|linux|macos
set -euo pipefail
PLAT="${1:?platforma: android|windows|linux|macos}"

rm -rf build_app
flutter create --project-name stb_player --org ba.stbplayer --platforms="$PLAT" build_app
rm -rf build_app/lib build_app/test build_app/analysis_options.yaml
cp app/pubspec.yaml build_app/pubspec.yaml
cp -r app/lib build_app/lib

if [ "$PLAT" = "android" ]; then
  python3 tools/patch_android.py build_app
fi

(cd build_app && flutter pub get)
