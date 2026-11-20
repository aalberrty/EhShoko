#!/usr/bin/env bash
# Launches a harness on a simulator, waits for what it writes and prints it.
#
#   harness_check.sh reader <check> [launch args...]
#       A reader harness check: -Harness reader -ReaderHarnessCheck <check> (calls, firstpage,
#       rotation, walk) and any further arguments (-ReaderHarnessModes a,b,
#       -ReaderHarnessRepeat <n>, -ReaderHarnessLook ledger). Waits until
#       Library/Caches/ReaderHarness/<check>-report.txt ends with "##### done", copies that
#       folder to --out and prints the report.
#   harness_check.sh part <seconds> [launch args...]
#       The part harness launched as the app (-Harness part and the arguments, for example
#       -HarnessPart library -HarnessLibrary wall -HarnessNetwork YES). Waits that long (for a
#       walk by hand, a scripted memory check or a sign-in that comes later), then copies the
#       files it writes in Documents/ to --out and prints them: harness-requests.txt (every
#       request), harness-decodes.txt (covers decoded and served) and part-harness-heap*.txt.
#   harness_check.sh files
#       Copies and prints the part harness's files again, without launching anything.
#
# Options (before the command):
#   --device <udid>     Simulator. Default: $APP_DEVICE, else the booted simulator.
#   --launcher <cmd>    Launch through this agent-device command (the one a device session hands
#                       out): "<cmd> open <bundle> --relaunch --launch-args <arg> ...". Without it
#                       the app is launched with simctl.
#   --out <dir>         Where the files go. Default: a new folder under ${TMPDIR}ehshoko-harness.
#   --timeout <s>       How long to wait for a reader report. Default: 1800.
#   --bundle-id <id>    Default: $APP_BUNDLE_ID, else app.ehshoko.
#
# Needs a Debug build (or one compiled with the HARNESS condition, see measure.sh) installed.
# Example, from the repository root:
#   Scripts/harness_check.sh --device 88CE204F-... reader walk
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

device="${APP_DEVICE:-}"
launcher=""
out=""
timeout=1800
bundle_id="${APP_BUNDLE_ID:-app.ehshoko}"

die() { echo "harness_check.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) device="$2"; shift 2 ;;
    --launcher) launcher="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --bundle-id) bundle_id="$2"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) break ;;
  esac
done

command="${1:-}"
[[ -n "$command" ]] || die "name a command: reader, part or files (see --help)"
shift

if [[ -z "$device" ]]; then
  device="$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1)"
  [[ -n "$device" ]] || die "no booted simulator; pass --device"
fi
[[ -n "$out" ]] || out="$(mktemp -d "${TMPDIR:-/tmp/}ehshoko-harness.XXXXXX")"
mkdir -p "$out"

# The app's data container, found on disk: simctl can take minutes on a loaded Mac.
container() {
  local metadata
  for metadata in "$HOME/Library/Developer/CoreSimulator/Devices/$device/data/Containers/Data/Application"/*/.com.apple.mobile_container_manager.metadata.plist; do
    [[ -f "$metadata" ]] || continue
    if [[ "$(plutil -extract MCMMetadataIdentifier raw "$metadata" 2>/dev/null)" == "$bundle_id" ]]; then
      dirname "$metadata"
      return 0
    fi
  done
  xcrun simctl get_app_container "$device" "$bundle_id" data 2>/dev/null
}

# Relaunches the app with these launch arguments.
launch() {
  if [[ -n "$launcher" ]]; then
    local tool=() args=()
    read -r -a tool <<< "$launcher"
    local argument
    for argument in "$@"; do args+=(--launch-args "$argument"); done
    "${tool[@]}" open "$bundle_id" --relaunch "${args[@]}" | tail -2
  else
    xcrun simctl launch --terminate-running-process "$device" "$bundle_id" "$@" >/dev/null
  fi
}

part_files() {
  local folder="$1/Documents" file found=0
  for file in "$folder"/harness-requests.txt "$folder"/harness-decodes.txt "$folder"/part-harness-heap*.txt; do
    [[ -f "$file" ]] || continue
    found=1
    cp "$file" "$out/"
    echo "===== $(basename "$file")"
    cat "$file"
  done
  [[ $found -eq 1 ]] || echo "No part harness files in $folder."
}

case "$command" in
  reader)
    check="${1:-}"
    [[ -n "$check" ]] || die "name a reader check: calls, firstpage, rotation or walk"
    shift
    data="$(container)" || true
    report_dir="${data:+$data/Library/Caches/ReaderHarness}"
    # A report left by an earlier run must not pass for this one's.
    [[ -n "$report_dir" ]] && rm -f "$report_dir/$check-report.txt" "$report_dir/log.txt"
    launch -Harness reader -ReaderHarnessCheck "$check" ${@+"$@"}
    [[ -n "$data" ]] || data="$(container)" || die "the app ($bundle_id) is not installed on $device"
    report="$data/Library/Caches/ReaderHarness/$check-report.txt"
    waited=0
    until grep -q '^##### done' "$report" 2>/dev/null; do
      if (( waited >= timeout )); then
        echo "harness_check.sh: no finished report after $timeout s" >&2
        break
      fi
      /bin/sleep 5
      waited=$((waited + 5))
    done
    cp "$data/Library/Caches/ReaderHarness/"* "$out/" 2>/dev/null || true
    echo "===== $check-report.txt (waited $waited s; files in $out)"
    cat "$report" 2>/dev/null || true
    grep -q '^##### done' "$report" 2>/dev/null
    ;;
  part)
    seconds="${1:-}"
    [[ "$seconds" =~ ^[0-9]+$ ]] || die "part needs the seconds to wait"
    shift
    launch -Harness part ${@+"$@"}
    /bin/sleep "$seconds"
    data="$(container)" || die "the app ($bundle_id) is not installed on $device"
    echo "Files in $out"
    part_files "$data"
    ;;
  files)
    data="$(container)" || die "the app ($bundle_id) is not installed on $device"
    echo "Files in $out"
    part_files "$data"
    ;;
  *)
    die "unknown command $command (reader, part, files)"
    ;;
esac
