#!/usr/bin/env bash
# Собирает firmware/custom/assets/extras/WifiHub.apk (скан/подключение Wi‑Fi).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/scripts/wifihub"
OUT="$ROOT/firmware/custom/assets/extras"
BT="${ANDROID_BUILD_TOOLS:-$HOME/Library/Android/sdk/build-tools/35.0.1}"
ANDROID_JAR="${ANDROID_JAR:-$HOME/Library/Android/sdk/platforms/android-33/android.jar}"
BUILD="$SRC/build"

[[ -x "$BT/aapt" ]] || { echo "нет build-tools: $BT"; exit 1; }
[[ -f "$ANDROID_JAR" ]] || { echo "нет android.jar: $ANDROID_JAR"; exit 1; }
mkdir -p "$OUT" "$BUILD/gen" "$BUILD/classes"
rm -rf "$BUILD/classes"/* "$BUILD/gen"/*

"$BT/aapt" package -f -m -J "$BUILD/gen" -M "$SRC/AndroidManifest.xml" -S "$SRC/res" -I "$ANDROID_JAR"
find "$SRC/src" "$BUILD/gen" -name '*.java' > "$BUILD/sources.txt"
javac -source 1.8 -target 1.8 -Xlint:-options -bootclasspath "$ANDROID_JAR" \
  -classpath "$ANDROID_JAR" -d "$BUILD/classes" @"$BUILD/sources.txt"
"$BT/d8" --min-api 19 --output "$BUILD" "$BUILD/classes"/com/cytatv/wifihub/*.class
"$BT/aapt" package -f -M "$SRC/AndroidManifest.xml" -S "$SRC/res" -I "$ANDROID_JAR" -F "$BUILD/unsigned.apk"
( cd "$BUILD" && zip -q -u unsigned.apk classes.dex )

KS="$SRC/debug.keystore"
if [[ ! -f "$KS" ]]; then
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=CytaTV WiFiHub,O=CytaTV,C=RU"
fi
"$BT/zipalign" -f 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/WifiHub.apk" "$BUILD/aligned.apk"
echo "OK: $OUT/WifiHub.apk ($(wc -c <"$OUT/WifiHub.apk") bytes)"
