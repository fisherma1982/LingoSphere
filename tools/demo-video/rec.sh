#!/bin/zsh
# usage: rec.sh <name> <record-seconds> KEY=VALUE...   (record-seconds 0 = no recording)
cd "${0:A:h}"
name=$1; dur=$2; shift 2
envargs=()
for kv in "$@"; do envargs+=(--env "$kv"); done
rm -f "$name.log" rect.txt "$name.mov"
open -n "$PWD/LingoDemo.app" "${envargs[@]}" --args "$PWD/$name.log" "$PWD/rect.txt"
for i in $(seq 1 80); do [ -s rect.txt ] && break; sleep 0.1; done
if [ "$dur" != "0" ]; then
  screencapture -x -v -V "$dur" -R "$(cat rect.txt)" "$name.mov"
fi
for i in $(seq 1 200); do grep -q '^done' "$name.log" 2>/dev/null && break; sleep 0.1; done
sleep 0.6
cat "$name.log"
