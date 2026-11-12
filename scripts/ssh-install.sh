#!/usr/bin/env bash
# Install from an SSH session, such as the iPhone Shortcut. codesign cannot use the login keychain over SSH, so the install runs in a plain
# launchd job in the logged-in desktop session, where it signs like a Terminal build. one-click-install.sh hands SSH runs to it.
#
#   BLUSION_IPHONE_UDID=<udid> scripts/ssh-install.sh setup   once, in Terminal: install the launchd job (again after moving the repo)
#   scripts/ssh-install.sh iphone|mac                          over SSH: queue an install, wait for it, print how it went
#   scripts/ssh-install.sh remove                              unload and delete the launchd job
#
# Needs the desktop session logged in; the screen may be locked. The last install's output is in ~/.blusion-install/last.log.
set -uo pipefail
# realpath gives the folder's real letter case, so the launchd job builds under the same paths as Terminal builds.
ROOT="$(/bin/realpath "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)")"
LABEL=app.blusion.install
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE="$HOME/.blusion-install"
QUEUE="$STATE/queue"
RESULTS="$STATE/results"
DOMAIN="gui/$(id -u)"
mkdir -p "$QUEUE" "$RESULTS"

setup() {
  [[ -n "${BLUSION_IPHONE_UDID:-}" ]] || { echo "ssh-install: set BLUSION_IPHONE_UDID to the intended device UDID" >&2; exit 1; }
  [[ -z "${SSH_CONNECTION:-}" ]] || { echo "ssh-install: run setup in Terminal on the Mac, not over SSH" >&2; exit 1; }
  mkdir -p "$(dirname "$PLIST")"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/scripts/ssh-install.sh</string><string>run</string></array>
  <key>QueueDirectories</key><array><string>$QUEUE</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>BLUSION_IPHONE_UDID</key><string>$BLUSION_IPHONE_UDID</string>
  </dict>
  <key>StandardOutPath</key><string>$STATE/launchd.log</string>
  <key>StandardErrorPath</key><string>$STATE/launchd.log</string>
</dict></plist>
EOF
  plutil -lint -s "$PLIST" || exit 1
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null || { sleep 1; launchctl bootstrap "$DOMAIN" "$PLIST"; } \
    || { echo "ssh-install: could not load $PLIST" >&2; exit 1; }
  echo "ssh-install: installed $LABEL"
}

# What launchd runs while the queue has files. Requests queued before a run starts share it.
run() {
  local first target udid file status result id ids
  rm -f "$QUEUE"/.[!.]*
  find "$RESULTS" -type f -mtime +1 -delete 2>/dev/null
  while first="$(ls "$QUEUE" | sort | head -n 1)"; [[ -n "$first" ]]; do
    target="${first##*.}"
    udid="$(head -n 1 "$QUEUE/$first" 2>/dev/null)"
    ids=()
    for file in "$QUEUE"/*."$target"; do ids+=("$(basename "$file" ".$target")"); rm -f "$file"; done
    echo "running $target since $(date '+%H:%M')" >"$STATE/status"
    BLUSION_IPHONE_UDID="${udid:-${BLUSION_IPHONE_UDID:-}}" "$ROOT/scripts/one-click-install.sh" "$target" >"$STATE/last.log" 2>&1
    status=$?
    if [[ "$status" == 0 ]]; then result=ok; else result="failed (exit $status)"; fi
    result="$result"$'\n'"$(tail -n 4 "$STATE/last.log")"
    for id in "${ids[@]}"; do printf '%s\n' "$result" >"$RESULTS/$id"; done
    printf '%s\n' "$result" >"$STATE/status"
  done
}

queue_and_wait() {
  local target="$1" id waited=0 outcome
  [[ -f "$PLIST" ]] || { echo "ssh-install: not set up; in Terminal on the Mac run BLUSION_IPHONE_UDID=<udid> scripts/ssh-install.sh setup" >&2; exit 1; }
  id="$(date +%Y%m%d-%H%M%S)-$$"
  printf '%s\n' "${BLUSION_IPHONE_UDID:-}" >"$STATE/$id.tmp" && mv "$STATE/$id.tmp" "$QUEUE/$id.$target"
  echo "ssh-install: queued the $target install; waiting for it to finish"
  while [[ ! -f "$RESULTS/$id" ]]; do
    if (( waited >= 60 )) && [[ -e "$QUEUE/$id.$target" ]] && ! grep -q '^running' "$STATE/status" 2>/dev/null; then
      rm -f "$QUEUE/$id.$target"
      echo "ssh-install: nothing picked up the install; log in on the Mac (the screen may stay locked)" >&2
      exit 1
    fi
    if (( waited >= 3600 )); then echo "ssh-install: still running after an hour; see ~/.blusion-install/last.log" >&2; exit 1; fi
    sleep 5
    waited=$(( waited + 5 ))
  done
  cat "$RESULTS/$id"
  outcome="$(head -n 1 "$RESULTS/$id")"
  rm -f "$RESULTS/$id"
  [[ "$outcome" == ok ]]
}

case "${1:-}" in
  setup) setup;;
  remove) launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null; rm -f "$PLIST"; echo "ssh-install: removed $LABEL";;
  run) run;;
  iphone|mac) queue_and_wait "$1";;
  *) sed -n '5,7p' "$0" >&2; exit 64;;
esac
