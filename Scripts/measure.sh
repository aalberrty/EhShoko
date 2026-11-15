#!/usr/bin/env bash
# Records a harness run or the app's signposts with Instruments (xctrace) on a simulator or a
# device, and prints the numbers the budgets of README.md section 9.5 are checked against.
#
#   measure.sh list [slot]     The list harness's scripted scroll over 500 synthetic galleries,
#                              run three times: for hitches, under Time Profiler and under
#                              Allocations. Prints the hitch time ratio, the worst hitch, the long
#                              hitches, the footprint, and the main thread's busy time and where it
#                              went. Slots: v3-rows (default), v3-grid; see ListHarnessSlot.
#                              Hitches: on a device, Instruments' Animation Hitches as well as the
#                              harness's own count; on a simulator, where Instruments cannot record
#                              hitches, the harness's count from its display link only.
#   measure.sh signposts [s]   Launches the app normally and records its Performance signposts
#                              for s seconds (default 30): Launch and FirstContent at once, and
#                              GalleryOpen, ReaderOpen and ListPage for whatever is opened meanwhile
#                              (by hand or with agent-device). Prints every interval and event.
#                              With --attach, records while the app already runs instead (no
#                              Launch or FirstContent then), so a screen can be reached first.
#   measure.sh report <dir>    Prints the numbers of an earlier run again.
#
# Options (before the run name):
#   --device <udid>       Simulator or device to record on. Default: $APP_DEVICE, else the
#                         booted simulator.
#   --app <EhShoko.app>   Build to install first. Default: none; the installed app is used.
#   --out <dir>           Where traces and the report go. Default: a new folder under
#                         ${TMPDIR}ehshoko-measure.
#   --templates <list>    Which recordings of a list run: hitches,time,alloc (default all three).
#   --speed <pt/s>        Scroll speed (default 2000).   --count <n>   Galleries (default 500).
#   --tags                Rows show their tags.          --latency <s> Cover latency (default 0.08).
#   --runs <n>            Repeat the hitches recording n times and report each (default 1).
#   --attach              signposts: attach to the running app rather than launching it.
#
# Example, from the repository root, with a Debug build installed on the iOS 26 simulator:
#   Scripts/measure.sh --device 37B2537D-E570-4030-B731-E2857E827B7E list v3-rows
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bundle_id="${APP_BUNDLE_ID:-app.ehshoko}"

device="${APP_DEVICE:-}"
app=""
out=""
templates="hitches,time,alloc"
speed=2000
count=500
tags=NO
latency=0.08
runs=1
attach=NO

die() { echo "measure.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) device="$2"; shift 2 ;;
    --app) app="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --templates) templates="$2"; shift 2 ;;
    --speed) speed="$2"; shift 2 ;;
    --count) count="$2"; shift 2 ;;
    --tags) tags=YES; shift ;;
    --latency) latency="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --attach) attach=YES; shift ;;
    -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done

run="${1:-}"
[[ -n "$run" ]] || die "name a run: list, signposts or report (see --help)"
shift

if [[ "$run" == report ]]; then
  [[ -n "${1:-}" ]] || die "report needs the folder of a run"
  exec python3 -I "$here/measure_report.py" "$1"
fi

if [[ -z "$device" ]]; then
  device="$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
booted = [d["udid"] for r in json.load(sys.stdin)["devices"].values() for d in r if d["state"] == "Booted"]
print(booted[0] if booted else "")')"
  [[ -n "$device" ]] || die "no booted simulator; boot one or pass --device"
fi

is_simulator() { xcrun simctl list devices -j | grep -q "\"$device\""; }

if [[ -n "$app" ]]; then
  if is_simulator; then
    xcrun simctl install "$device" "$app"
  else
    xcrun devicectl device install app --device "$device" "$app" >/dev/null
  fi
fi

# What xctrace launches: on a simulator the installed bundle, by its path inside the simulator.
if is_simulator; then
  target="$(xcrun simctl get_app_container "$device" "$bundle_id" app)" \
    || die "$bundle_id is not installed on $device; build it, or pass --app"
else
  target="$bundle_id"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out="${out:-${TMPDIR:-/tmp/}ehshoko-measure/$run-${1:-default}-$stamp}"
mkdir -p "$out"

terminate() {
  if is_simulator; then
    xcrun simctl terminate "$device" "$bundle_id" >/dev/null 2>&1 || true
  fi
}

# record <template> <trace> <time limit> <extra instruments...> -- <app arguments...>
record() {
  local template="$1" trace="$2" limit="$3"
  shift 3
  local instruments=()
  while [[ "$1" != -- ]]; do instruments+=(--instrument "$1"); shift; done
  shift
  terminate
  echo "Recording $template → $trace" >&2
  # xctrace exits non-zero for warnings too; whether the trace is usable shows in the report.
  xcrun xctrace record --quiet --no-prompt --device "$device" --template "$template" \
    ${instruments[@]+"${instruments[@]}"} --time-limit "$limit" --output "$trace" \
    --launch -- "$target" "$@" >/dev/null || echo "measure.sh: xctrace reported issues (above)" >&2
}

# Copies the list harness's result file of the last run to $1.
fetch_result() {
  if is_simulator; then
    local data
    data="$(xcrun simctl get_app_container "$device" "$bundle_id" data)"
    cp "$data/Library/Caches/ListHarness/result.json" "$1" 2>/dev/null
  else
    xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
      --domain-identifier "$bundle_id" --source Library/Caches/ListHarness/result.json \
      --destination "$1" >/dev/null 2>&1
  fi || echo "measure.sh: the harness wrote no result (did the run finish?)" >&2
}

case "$run" in
  list)
    slot="${1:-v3-rows}"
    harness_args=(-Harness list -HarnessSlot "$slot" -HarnessCount "$count" -HarnessSpeed "$speed"
      -HarnessTags "$tags" -HarnessCoverLatency "$latency" -HarnessAutoRun YES -HarnessExitWhenDone YES)
    printf '%s\n' "slot=$slot" "speed=$speed" "count=$count" "tags=$tags" "latency=$latency" \
      "device=$device" > "$out/run.txt"
    for template in ${templates//,/ }; do
      case "$template" in
        hitches)
          for ((index = 1; index <= runs; index++)); do
            if is_simulator; then
              # Instruments cannot record hitches on a simulator ("Hitches is not supported on
              # this platform"), so the run is the harness alone and its frame timing is reported.
              terminate
              echo "Scrolling, run $index (the harness's own frame timing)" >&2
              xcrun simctl launch --console-pty "$device" "$bundle_id" "${harness_args[@]}" > "$out/console-$index.txt" 2>&1 \
                || echo "measure.sh: the launch failed (see console-$index.txt)" >&2
            else
              record "Animation Hitches" "$out/hitches-$index.trace" 240s os_signpost -- "${harness_args[@]}"
            fi
            fetch_result "$out/result-$index.json"
          done ;;
        time) record "Time Profiler" "$out/time.trace" 240s os_signpost -- "${harness_args[@]}" ;;
        alloc) record "Allocations" "$out/alloc.trace" 240s -- "${harness_args[@]}" ;;
        *) die "unknown template $template (hitches, time, alloc)" ;;
      esac
    done
    ;;
  signposts)
    seconds="${1:-30}"
    echo "kind=signposts attach=$attach" > "$out/run.txt"
    if [[ "$attach" == YES ]]; then
      # xctrace cannot attach to a simulator's app by name or pid, so this records every
      # process; the report keeps the app's subsystem only.
      echo "Recording signposts of the running app for ${seconds} s → $out/signposts.trace" >&2
      xcrun xctrace record --quiet --no-prompt --device "$device" --template Logging \
        --instrument os_signpost --time-limit "${seconds}s" --output "$out/signposts.trace" \
        --all-processes >/dev/null || echo "measure.sh: xctrace reported issues (above)" >&2
      python3 -I "$here/measure_report.py" "$out"
      exit 0
    fi
    record "Logging" "$out/signposts.trace" "${seconds}s" os_signpost --
    ;;
  *) die "unknown run $run (list, signposts, report)" ;;
esac

terminate
python3 -I "$here/measure_report.py" "$out"
