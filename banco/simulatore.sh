#!/bin/bash
# Banco di prova: crea e accende un iPhone nel simulatore (come quello del signore: 393 x 852, Dynamic Island, se c'è).
set -euo pipefail
# il runtime iOS generico più recente (non quelli legati a un modello, tipo «iOS-27-2-iPhone19-4»)
RT=$(xcrun simctl list runtimes -j | python3 -c "
import json,sys,re
r=[x for x in json.load(sys.stdin)['runtimes'] if x.get('platform')=='iOS' and x.get('isAvailable')]
g=[x for x in r if re.search(r'iOS-[0-9]+-[0-9]+$', x['identifier'])]
print((g or r)[-1]['identifier'] if r else '')")
echo "runtime: $RT"
[ -n "$RT" ] || { xcrun simctl list runtimes; exit 1; }
UDID=""
for T in "iPhone 15 Pro" "iPhone 16" "iPhone 15" "iPhone 16 Pro" "iPhone 17" "iPhone 17 Pro"; do
  TID=$(xcrun simctl list devicetypes -j | python3 -c "
import json,sys
t=[x for x in json.load(sys.stdin)['devicetypes'] if x['name']=='$T']
print(t[0]['identifier'] if t else '')")
  [ -n "$TID" ] || continue
  if UDID=$(xcrun simctl create "banco" "$TID" "$RT" 2>/dev/null); then echo "dispositivo: $T"; break; fi
  UDID=""
done
[ -n "$UDID" ] || { xcrun simctl list devicetypes; exit 1; }
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl status_bar "$UDID" override --time "06:32" --batteryState discharging --batteryLevel 48 --wifiBars 3 --cellularMode active --cellularBars 2 || true
echo "UDID=$UDID" >> "$GITHUB_ENV"
