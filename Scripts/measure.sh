#!/usr/bin/env bash
# Records a harness run or the app's signposts with Instruments (xctrace) on a simulator or a
# device, and prints the numbers the budgets of README.md section 9.5 are checked against.
#
#   measure.sh list [slot]     The list harness's scripted scroll over 500 synthetic galleries,
#                              run three times: for hitches, under Time Profiler and under
#                              Allocations. Prints the hitch time ratio, the worst hitch, the long
#                              hitches, the footprint, and the main thread's busy time and where it
#                              went. Slots: shelf (default), wall-medium, ledger, …; see ListHarnessSlot.
#                              Hitches: on a device, Instruments' Animation Hitches as well as the
#                              harness's own count; on a simulator, where Instruments cannot record
#                              hitches, the harness's count from its display link only. On a
#                              device the hitches recording has a time profile of its own, so
#                              --templates hitches,alloc gives every figure in fewer runs.
#   measure.sh signposts [s]   Launches the app normally and records its Performance signposts
#                              for s seconds (default 30): Launch and FirstContent at once, and
#                              GalleryOpen, ReaderOpen and ListPage for whatever is opened meanwhile
#                              (by hand, with agent-device, or with --link). Prints every interval
#                              and event, and with --runs the median and spread of each.
#                              With --attach, records while the app already runs instead (no
#                              Launch or FirstContent then), so a screen can be reached first.
#   measure.sh launch          Launches the app under Instruments' App Launch template (with the
#                              signposts), --runs times, and prints the time to the first frame,
#                              split into the system's process creation and the app's own part,
#                              and the Launch signpost.
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
#   --runs <n>            Repeat the hitches and time recordings of a list run, or a signposts
#                         run, n times; reports each and the median and spread (default 1).
#   --attach              signposts: attach to the running app rather than launching it.
#   --link <url>          signposts: open this gallery link at launch (an image page link also
#                         opens the reader). Needs a build with the harness (see below).
#   --clear-images        signposts: empty the image cache before the link is opened.
#   --exit-after <s>      signposts: the app writes its footprint and quits s seconds after its
#                         root appears, which ends the recording early.
#   --template <name>     signposts: the Instruments template (default Logging). With
#                         "Animation Hitches" the report counts the hitches of the first 600 ms
#                         of GalleryOpen and ReaderOpen, the opening transition.
#   --app-arg <arg>       signposts: one more launch argument, repeatable (for example
#                         --app-arg -Harness --app-arg reader to time the reader harness).
#   --bundle-id <id>      The app to measure. Default: $APP_BUNDLE_ID, else app.ehshoko.
#
# Every launch gets -Tips hide, so the Favourite tip never shows during a recording.
#
# The harness and the launch arguments above exist in Debug builds, and in any build compiled
# with the HARNESS condition, which measures optimised code: add
#   'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) HARNESS'
# to the Release xcodebuild command that builds the app for the device.
#
# Example, from the repository root, with a Debug build installed on the iOS 26 simulator:
#   Scripts/measure.sh --device 37B2537D-E570-4030-B731-E2857E827B7E list shelf
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
link=""
clear_images=NO
exit_after=""
extra_args=()
signpost_template=Logging
# Every launch shows no tip (TipKit's Favourite tip), so nothing interrupts a recorded run.
tips_args=(-Tips hide)

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
    --link) link="$2"; shift 2 ;;
    --clear-images) clear_images=YES; shift ;;
    --exit-after) exit_after="$2"; shift 2 ;;
    --bundle-id) bundle_id="$2"; shift 2 ;;
    --app-arg) extra_args+=("$2"); shift 2 ;;
    --template) signpost_template="$2"; shift 2 ;;
    -h|--help) sed -n '2,64p' "$0"; exit 0 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done

run="${1:-}"
[[ -n "$run" ]] || die "name a run: list, signposts, launch or report (see --help)"
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
    return
  fi
  # On a device: the processes whose executable is inside this bundle's install folder, so
  # another build of the app (installed beside it under another bundle id) is never touched.
  local apps processes pid
  apps="$out/.apps.json"
  processes="$out/.processes.json"
  xcrun devicectl device info apps --device "$device" --bundle-id "$bundle_id" --json-output "$apps" >/dev/null 2>&1 || return 0
  xcrun devicectl device info processes --device "$device" --json-output "$processes" >/dev/null 2>&1 || return 0
  for pid in $(python3 -I - "$apps" "$processes" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]
folders = [app["url"] for app in apps if app.get("url")]
for process in json.load(open(sys.argv[2]))["result"]["runningProcesses"]:
    executable = process.get("executable", "")
    if folders and any(executable.startswith(folder) for folder in folders):
        print(process["processIdentifier"])
PY
  ); do
    xcrun devicectl device process terminate --device "$device" --pid "$pid" >/dev/null 2>&1 || true
  done
  rm -f "$apps" "$processes"
}

# record <template> <trace> <time limit> <extra instruments...> -- <app arguments...>
record() {
  local template="$1" trace="$2" limit="$3"
  shift 3
  local instruments=()
  while [[ "$1" != -- ]]; do instruments+=(--instrument "$1"); shift; done
  shift
  local attempt issues="$out/.xctrace-issues.txt"
  for attempt in 1 2 3 4 5; do
    terminate
    rm -rf "$trace"
    echo "Recording $template → $trace" >&2
    # xctrace exits non-zero for warnings too; whether the trace is usable shows in the report.
    xcrun xctrace record --quiet --no-prompt --device "$device" --template "$template" \
      ${instruments[@]+"${instruments[@]}"} --time-limit "$limit" --output "$trace" \
      --launch -- "$target" "$@" "${tips_args[@]}" >/dev/null 2>"$issues" || echo "measure.sh: xctrace reported issues" >&2
    cat "$issues" >&2
    # A device refuses to record ("an unknown problem") while the app still runs, which a
    # terminate that timed out under load leaves behind, and for a while after a heavy
    # recording (Animation Hitches) ends; terminate again and retry, waiting longer each time.
    grep -q "preventing this device from recording" "$issues" || break
    echo "measure.sh: the device would not record (attempt $attempt); retrying" >&2
    sleep $((attempt * 20))
  done
  rm -f "$issues"
}

# mark_stale <file in Library/Caches/ListHarness>: replaces what an earlier run left there with
# {"stale": true}, so a run that never started cannot hand on the last run's result; the
# report skips such a file.
mark_stale() {
  local source="Library/Caches/ListHarness/$1" marker="$out/.stale.json"
  echo '{"stale": true}' > "$marker"
  if is_simulator; then
    local data
    data="$(xcrun simctl get_app_container "$device" "$bundle_id" data)"
    mkdir -p "$data/Library/Caches/ListHarness" && cp "$marker" "$data/$source"
  else
    xcrun devicectl device copy to --device "$device" --domain-type appDataContainer \
      --domain-identifier "$bundle_id" --source "$marker" --destination "$source" >/dev/null 2>&1
  fi || echo "measure.sh: could not reset $1 on the device" >&2
  rm -f "$marker"
}

# fetch_file <file in Library/Caches/ListHarness> <destination>: copies what the harness wrote
# in the last run.
fetch_file() {
  local source="Library/Caches/ListHarness/$1"
  if is_simulator; then
    local data
    data="$(xcrun simctl get_app_container "$device" "$bundle_id" data)"
    cp "$data/$source" "$2" 2>/dev/null
  else
    xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
      --domain-identifier "$bundle_id" --source "$source" --destination "$2" >/dev/null 2>&1
  fi || echo "measure.sh: the harness wrote no $1 (did the run finish?)" >&2
}

case "$run" in
  list)
    slot="${1:-shelf}"
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
              xcrun simctl launch --console-pty "$device" "$bundle_id" "${harness_args[@]}" "${tips_args[@]}" > "$out/console-$index.txt" 2>&1 \
                || echo "measure.sh: the launch failed (see console-$index.txt)" >&2
            else
              mark_stale result.json
              record "Animation Hitches" "$out/hitches-$index.trace" 240s os_signpost -- "${harness_args[@]}"
            fi
            fetch_file result.json "$out/result-$index.json"
          done ;;
        time)
          for ((index = 1; index <= runs; index++)); do
            record "Time Profiler" "$out/time-$index.trace" 240s os_signpost -- "${harness_args[@]}"
          done ;;
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
    app_args=(${extra_args[@]+"${extra_args[@]}"})
    [[ -z "$link" ]] || app_args+=(-HarnessLink "$link")
    [[ "$clear_images" == NO ]] || app_args+=(-HarnessClearImageCache YES)
    [[ -z "$exit_after" ]] || app_args+=(-HarnessExitAfter "$exit_after")
    printf '%s\n' "link=${link:-none}" "clear_images=$clear_images" "exit_after=${exit_after:-none}" "arguments=${extra_args[*]:-none}" "template=$signpost_template" \
      "device=$device" >> "$out/run.txt"
    for ((index = 1; index <= runs; index++)); do
      [[ -z "$exit_after" ]] || mark_stale footprint.json
      record "$signpost_template" "$out/signposts-$index.trace" "${seconds}s" os_signpost -- ${app_args[@]+"${app_args[@]}"}
      [[ -z "$exit_after" ]] || fetch_file footprint.json "$out/footprint-$index.json"
    done
    ;;
  launch)
    printf '%s\n' "kind=launch" "device=$device" > "$out/run.txt"
    for ((index = 1; index <= runs; index++)); do
      record "App Launch" "$out/launch-$index.trace" 10s os_signpost --
    done
    ;;
  *) die "unknown run $run (list, signposts, launch, report)" ;;
esac

terminate
python3 -I "$here/measure_report.py" "$out"
