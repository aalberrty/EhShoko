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
#                              With --scrolls n the harness scrolls n times in one launch (new
#                              covers and an empty image cache each time), so one recording and
#                              one save stand for n; the report splits it by scroll.
#   measure.sh hand [slot] [s] The list harness's list scrolled by a hand: the list is on the
#                              screen for s seconds (default 30) and closes by itself; the
#                              harness marks every stretch of movement, and the report sets
#                              Instruments' hitches of those stretches beside a scripted
#                              scroll's. Whoever holds the device flicks the list for as long
#                              as it is there.
#   measure.sh shell [args]    The same scripted scroll in the real shell: the part harness's
#                              list (-Harness part -HarnessPart list) under the chosen bar, look
#                              and designs, which the arguments name as the part harness reads
#                              them (-HarnessBar tabs -HarnessList wall -HarnessDensity small …;
#                              see PartHarnessOptions). A hitches recording, with --scrolls.
#   measure.sh signposts [s]   Launches the app normally and records its Performance signposts
#                              for s seconds (default 30): Launch and FirstContent at once, and
#                              GalleryOpen, ReaderOpen and ListPage for whatever is opened meanwhile
#                              (by hand, with agent-device, or with --link). Prints every interval
#                              and event, and with --runs the median and spread of each.
#                              With --attach, records while the app already runs instead (no
#                              Launch or FirstContent then), so a screen can be reached first.
#   measure.sh launch [s]      Launches the app under Instruments' App Launch template (with the
#                              signposts) for s seconds (default 10), --runs times, and prints the
#                              time to the first frame, split into the system's process creation
#                              and the app's own part, and the signposts (Launch, FirstContent).
#   measure.sh rest [label]    Shows the rest screen on the device (-Harness rest): black, one dim
#                              moving line, the screen kept awake. What a phone shows between
#                              the recordings of a session instead of its home screen.
#   measure.sh stop            Ends the app on the device (the end of a session).
#   measure.sh report <dir>    Prints the numbers of an earlier run again, or of a run recorded
#                              with --no-report for the first time.
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
#                         or launch run, n times; reports each and the median and spread
#                         (default 1).
#   --scrolls <n>         list, shell: n scripted scrolls in each launch (default 1).
#   --look <name>         list: the look the list is drawn in (shelf, wall, ledger; default the
#                         slot's own design).
#   --bar, --dock         list: the command bar, or a gallery dock, floats over the list.
#   --width <pt>          list, hand: the list's width (430: a phone's list on an iPad).
#   --awake               list, hand, shell: a thread keeps the performance cores at their top
#                         speed while the list scrolls. A scripted scroll leaves the main
#                         thread idle between rows, and the system then runs it slowly (on a
#                         phone, on its efficiency cores); with --awake the figure is the
#                         list's, without it the list's and the power management's. The
#                         report says which cores the main thread ran on.
#   --covers-ready        list: every cover is in memory before a scroll starts.
#   --light               Record hitches with the Time Profiler template plus the Hitches
#                         instrument instead of the Animation Hitches template, whose traces are
#                         ten times the size and take as much longer to save.
#   --limit <s>           The longest a list or shell recording may last (default: 60 s and
#                         75 s for each scroll). The harness quits when it is done.
#   --no-report           Record only. Nothing is exported or printed; run
#                         "measure.sh report <dir>" on the folder later, when the device is no
#                         longer needed.
#   --rest <label>        On a device: as soon as a recording has ended, while xctrace still
#                         saves its trace, and after the last one, show the rest screen with
#                         this label instead of leaving the device on its home screen.
#   --attach              signposts: attach to the running app rather than launching it.
#   --link <url>          signposts: open this gallery link at launch (an image page link also
#                         opens the reader). Needs a build with the harness (see below).
#   --clear-images        signposts: empty the image cache before the link is opened.
#   --exit-after <s>      signposts, launch: the app writes its footprint and quits s seconds
#                         after its root appears, which ends the recording early.
#   --template <name>     signposts: the Instruments template (default Logging). With
#                         "Animation Hitches", or with --light, the report counts the hitches
#                         of the first 600 ms of GalleryOpen and ReaderOpen, the opening
#                         transition.
#   --app-arg <arg>       One more launch argument, repeatable (for example
#                         --app-arg -Harness --app-arg reader to time the reader harness, or
#                         --app-arg -settings.designBar --app-arg command for the real app
#                         under another design; a launch argument changes no stored setting).
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
scrolls=1
look=""
width=""
awake=NO
covers_ready=NO
bar=NO
dock=NO
light=NO
limit=""
report=YES
rest=""
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
    --scrolls) scrolls="$2"; shift 2 ;;
    --look) look="$2"; shift 2 ;;
    --bar) bar=YES; shift ;;
    --dock) dock=YES; shift ;;
    --width) width="$2"; shift 2 ;;
    --awake) awake=YES; shift ;;
    --covers-ready) covers_ready=YES; shift ;;
    --light) light=YES; shift ;;
    --limit) limit="$2"; shift 2 ;;
    --no-report) report=NO; shift ;;
    --rest) rest="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done

run="${1:-}"
[[ -n "$run" ]] || die "name a run: list, hand, shell, signposts, launch, rest, stop or report (see --help)"
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
[[ "$run" == rest || "$run" == stop ]] || out="${out:-${TMPDIR:-/tmp/}ehshoko-measure/$run-${1:-default}-$stamp}"
out="${out:-${TMPDIR:-/tmp/}ehshoko-measure/.scratch}"
mkdir -p "$out"

# The pids of the app on a device: the processes whose executable is inside this bundle's
# install folder, so another build of the app (installed beside it under another bundle id)
# is never touched.
device_pids() {
  local apps="$out/.apps.json" processes="$out/.processes.json"
  xcrun devicectl device info apps --device "$device" --bundle-id "$bundle_id" --json-output "$apps" >/dev/null 2>&1 || return 0
  xcrun devicectl device info processes --device "$device" --json-output "$processes" >/dev/null 2>&1 || return 0
  python3 -I - "$apps" "$processes" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]
folders = [app["url"] for app in apps if app.get("url")]
for process in json.load(open(sys.argv[2]))["result"]["runningProcesses"]:
    executable = process.get("executable", "")
    if folders and any(executable.startswith(folder) for folder in folders):
        print(process["processIdentifier"])
PY
  rm -f "$apps" "$processes"
}

terminate() {
  if is_simulator; then
    xcrun simctl terminate "$device" "$bundle_id" >/dev/null 2>&1 || true
    return
  fi
  local pid
  for pid in $(device_pids); do
    xcrun devicectl device process terminate --device "$device" --pid "$pid" >/dev/null 2>&1 || true
  done
}

# Ends the app and makes sure of it: an app launched a moment ago (the rest screen) may not
# be listed yet, and a rest screen left running keeps a device's screen awake for good.
stop_for_good() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    terminate
    is_simulator && return 0
    /bin/sleep 2
    [[ -n "$(device_pids)" ]] || return 0
  done
  echo "measure.sh: the app is STILL RUNNING on the device; end it by hand" >&2
  return 1
}

# show_rest <label>: the rest screen in place of whatever the device shows. On a simulator
# nothing: its screen needs no care.
show_rest() {
  is_simulator && return 0
  xcrun devicectl device process launch --device "$device" --terminate-existing -- "$bundle_id" \
    -Harness rest -HarnessRestLabel "$1" >/dev/null 2>&1 \
    || echo "measure.sh: could not show the rest screen" >&2
}

# Records hitches with: the Animation Hitches template, or with --light the Time Profiler
# template and the Hitches instrument (the frames' lateness and the time profile, without the
# thread states and the display's frames that make an Animation Hitches trace so large).
if [[ "$light" == YES ]]; then
  hitches_template="Time Profiler"
  hitches_instruments=(Hitches os_signpost)
else
  hitches_template="Animation Hitches"
  hitches_instruments=(os_signpost)
fi

# record <template> <trace> <time limit> <extra instruments...> -- <app arguments...>
record() {
  local template="$1" trace="$2" limit="$3"
  shift 3
  local instruments=()
  while [[ "$1" != -- ]]; do instruments+=(--instrument "$1"); shift; done
  shift
  local attempt issues="$out/.xctrace-issues.txt" progress="$out/.xctrace-progress.txt" recorder waited
  for attempt in 1 2 3 4 5; do
    terminate
    rm -rf "$trace"
    echo "Recording $template → $trace" >&2
    # xctrace exits non-zero for warnings too; whether the trace is usable shows in the report.
    xcrun xctrace record --no-prompt --device "$device" --template "$template" \
      ${instruments[@]+"${instruments[@]}"} --time-limit "$limit" --output "$trace" \
      --launch -- "$target" "$@" "${tips_args[@]}" >"$progress" 2>"$issues" &
    recorder=$!
    if [[ -n "$rest" ]]; then
      # xctrace saves the trace before it returns, which takes from seconds to minutes; the
      # app has gone by then. The rest screen takes the device's screen for that time.
      waited=0
      while kill -0 "$recorder" 2>/dev/null; do
        if grep -qiE "exited|Recording completed|Saving" "$progress" 2>/dev/null; then
          show_rest "$rest"
          break
        fi
        /bin/sleep 1
        waited=$((waited + 1))
      done
    fi
    wait "$recorder" || echo "measure.sh: xctrace reported issues" >&2
    cat "$issues" >&2
    # A device refuses to record ("an unknown problem") while the app still runs, which a
    # terminate that timed out under load leaves behind, and for a while after a heavy
    # recording (Animation Hitches) ends; terminate again and retry, waiting longer each time.
    grep -q "preventing this device from recording" "$issues" || break
    echo "measure.sh: the device would not record (attempt $attempt); retrying" >&2
    /bin/sleep $((attempt * 20))
  done
  rm -f "$issues" "$progress"
  [[ -d "$trace" ]] || echo "measure.sh: no trace was written ($trace)" >&2
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

# fetch_file <file in Library/Caches/ListHarness> <destination> [the run before's copy]: copies
# what the harness wrote in the last run. A series marks the file stale once, before its first
# run (each mark is a round trip to the device, seconds a phone's screen waits for); a later
# run that never started leaves the run before's file there, byte for byte, which is told
# here and marked stale.
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
  if [[ -n "${3:-}" && -f "$2" && -f "$3" ]] && cmp -s "$2" "$3"; then
    echo "measure.sh: this run left no $1 of its own" >&2
    echo '{"stale": true}' > "$2"
  fi
}

# The scripted scrolls of one launch, recorded for hitches --runs times.
#   scroll_runs <harness arguments...>
scroll_runs() {
  local index scroll_limit="${limit:-$((60 + scrolls * 75))}"
  for ((index = 1; index <= runs; index++)); do
    if is_simulator; then
      # Instruments cannot record hitches on a simulator ("Hitches is not supported on
      # this platform"), so the run is the harness alone: its footprint and its main
      # thread's time, and no hitch figure.
      terminate
      echo "Scrolling, run $index (the harness alone: no hitches on a simulator)" >&2
      xcrun simctl launch --console-pty "$device" "$bundle_id" "$@" "${tips_args[@]}" > "$out/console-$index.txt" 2>&1 \
        || echo "measure.sh: the launch failed (see console-$index.txt)" >&2
    else
      [[ $index -gt 1 ]] || mark_stale result.json
      record "$hitches_template" "$out/hitches-$index.trace" "${scroll_limit}s" "${hitches_instruments[@]}" -- "$@"
    fi
    fetch_file result.json "$out/result-$index.json" "$out/result-$((index - 1)).json"
  done
}

case "$run" in
  rest)
    show_rest "${1:-}"
    exit 0
    ;;
  stop)
    stop_for_good
    exit $?
    ;;
  list)
    slot="${1:-shelf}"
    harness_args=(-Harness list -HarnessSlot "$slot" -HarnessCount "$count" -HarnessSpeed "$speed"
      -HarnessTags "$tags" -HarnessCoverLatency "$latency" -HarnessBar "$bar" -HarnessDock "$dock"
      -HarnessAutoRun YES -HarnessRuns "$scrolls" -HarnessExitWhenDone YES)
    [[ -z "$look" ]] || harness_args+=(-HarnessLook "$look")
    [[ -z "$width" ]] || harness_args+=(-HarnessWidth "$width")
    [[ "$awake" == NO ]] || harness_args+=(-HarnessCoresAwake YES)
    [[ "$covers_ready" == NO ]] || harness_args+=(-HarnessCoversReady YES)
    harness_args+=(${extra_args[@]+"${extra_args[@]}"})
    printf '%s\n' "slot=$slot" "speed=$speed" "count=$count" "tags=$tags" "latency=$latency" \
      "bar=$bar" "dock=$dock" "look=${look:-own}" "width=${width:-window}" "awake=$awake" \
      "covers_ready=$covers_ready" "scrolls=$scrolls" "light=$light" "device=$device" > "$out/run.txt"
    for template in ${templates//,/ }; do
      case "$template" in
        hitches) scroll_runs "${harness_args[@]}" ;;
        time)
          for ((index = 1; index <= runs; index++)); do
            record "Time Profiler" "$out/time-$index.trace" "${limit:-$((60 + scrolls * 75))}s" os_signpost -- "${harness_args[@]}"
          done ;;
        alloc) record "Allocations" "$out/alloc.trace" "${limit:-$((60 + scrolls * 75))}s" -- "${harness_args[@]}" ;;
        *) die "unknown template $template (hitches, time, alloc)" ;;
      esac
    done
    ;;
  hand)
    slot="${1:-shelf}"
    seconds="${2:-30}"
    harness_args=(-Harness list -HarnessSlot "$slot" -HarnessCount "$count" -HarnessTags "$tags"
      -HarnessCoverLatency "$latency" -HarnessBar "$bar" -HarnessDock "$dock"
      -HarnessObserve "$seconds" -HarnessExitWhenDone YES)
    [[ -z "$look" ]] || harness_args+=(-HarnessLook "$look")
    [[ -z "$width" ]] || harness_args+=(-HarnessWidth "$width")
    [[ "$awake" == NO ]] || harness_args+=(-HarnessCoresAwake YES)
    harness_args+=(${extra_args[@]+"${extra_args[@]}"})
    printf '%s\n' "kind=hand" "slot=$slot" "seconds=$seconds" "count=$count" "tags=$tags" "latency=$latency" \
      "bar=$bar" "dock=$dock" "look=${look:-own}" "width=${width:-window}" "awake=$awake" \
      "light=$light" "device=$device" > "$out/run.txt"
    is_simulator && die "hand records Instruments' hitches, which a simulator does not have"
    # The list closes by itself; the limit is for a launch that never got that far.
    limit="${limit:-$((seconds + 30))}"
    scroll_runs "${harness_args[@]}"
    ;;
  shell)
    harness_args=(-Harness part -HarnessPart list -HarnessPanel NO -HarnessCount "$count" -HarnessSpeed "$speed"
      -HarnessTags "$tags" -HarnessAutoRun YES -HarnessRuns "$scrolls" -HarnessExitWhenDone YES "$@"
      ${extra_args[@]+"${extra_args[@]}"})
    [[ "$awake" == NO ]] || harness_args+=(-HarnessCoresAwake YES)
    printf '%s\n' "kind=shell" "arguments=$*" "speed=$speed" "count=$count" "tags=$tags" \
      "awake=$awake" "scrolls=$scrolls" "light=$light" "device=$device" > "$out/run.txt"
    scroll_runs "${harness_args[@]}"
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
      [[ "$report" == NO ]] || python3 -I "$here/measure_report.py" "$out"
      exit 0
    fi
    app_args=(${extra_args[@]+"${extra_args[@]}"})
    [[ -z "$link" ]] || app_args+=(-HarnessLink "$link")
    [[ "$clear_images" == NO ]] || app_args+=(-HarnessClearImageCache YES)
    [[ -z "$exit_after" ]] || app_args+=(-HarnessExitAfter "$exit_after")
    signpost_instruments=(os_signpost)
    if [[ "$light" == YES ]]; then
      signpost_template="Time Profiler"
      signpost_instruments=(Hitches os_signpost)
    fi
    printf '%s\n' "link=${link:-none}" "clear_images=$clear_images" "exit_after=${exit_after:-none}" "arguments=${extra_args[*]:-none}" "template=$signpost_template" \
      "light=$light" "device=$device" >> "$out/run.txt"
    for ((index = 1; index <= runs; index++)); do
      [[ -z "$exit_after" || $index -gt 1 ]] || mark_stale footprint.json
      record "$signpost_template" "$out/signposts-$index.trace" "${seconds}s" "${signpost_instruments[@]}" -- ${app_args[@]+"${app_args[@]}"}
      [[ -z "$exit_after" ]] || fetch_file footprint.json "$out/footprint-$index.json" "$out/footprint-$((index - 1)).json"
    done
    ;;
  launch)
    seconds="${1:-10}"
    app_args=(${extra_args[@]+"${extra_args[@]}"})
    [[ -z "$exit_after" ]] || app_args+=(-HarnessExitAfter "$exit_after")
    printf '%s\n' "kind=launch" "exit_after=${exit_after:-none}" "arguments=${extra_args[*]:-none}" "device=$device" > "$out/run.txt"
    for ((index = 1; index <= runs; index++)); do
      [[ -z "$exit_after" || $index -gt 1 ]] || mark_stale footprint.json
      record "App Launch" "$out/launch-$index.trace" "${seconds}s" os_signpost -- ${app_args[@]+"${app_args[@]}"}
      [[ -z "$exit_after" ]] || fetch_file footprint.json "$out/footprint-$index.json" "$out/footprint-$((index - 1)).json"
    done
    ;;
  *) die "unknown run $run (list, hand, shell, signposts, launch, rest, stop, report)" ;;
esac

if [[ -n "$rest" ]]; then
  # A recording that ran to its time limit leaves the app on screen; the rest screen takes
  # its place either way.
  show_rest "$rest"
else
  terminate
fi
[[ "$report" == NO ]] || python3 -I "$here/measure_report.py" "$out"
