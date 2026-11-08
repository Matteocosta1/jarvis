#!/bin/bash
# Banco di prova: installa l'app e registra il video di ogni scena (il copione lo fa la radice di prova, BancoProva.swift).
set -uo pipefail
OUT=banco/out
mkdir -p "$OUT"
APP=$(find dd/Build/Products -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1)
echo "app: $APP"
[ -n "$APP" ] || exit 1
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
BID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant all "$BID" || true
xcrun simctl spawn "$UDID" log stream --style compact --predicate "process == \"$(basename "$APP" .app)\"" > "$OUT/console.log" 2>&1 &
LOGP=$!
for S in "$@"; do
  case "$S" in mail*) DUR=16 ;; studio*) DUR=33 ;; *) DUR=15 ;; esac
  # un primo avvio a vuoto (la prima volta il simulatore è lento a caricare l'app)
  if [ ! -f "$OUT/.caldo" ]; then
    xcrun simctl launch "$UDID" "$BID" -banco nulla; sleep 6; xcrun simctl terminate "$UDID" "$BID" || true; sleep 1; touch "$OUT/.caldo"
  fi
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$S.mp4" > "$OUT/rec-$S.log" 2>&1 &
  REC=$!
  sleep 2
  xcrun simctl launch "$UDID" "$BID" -banco "$S"
  sleep "$DUR"
  xcrun simctl io "$UDID" screenshot "$OUT/$S-fine.png" || true
  kill -INT $REC; wait $REC || true
  xcrun simctl terminate "$UDID" "$BID" || true
  sleep 1
done
kill $LOGP 2>/dev/null || true
ls -la "$OUT"
