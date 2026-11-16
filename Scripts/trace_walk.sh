#!/usr/bin/env bash
# Records an Instruments trace (Time Profiler, Allocations, Hitches and the app's signposts)
# of one UI walk on a device, for the performance pass.
#
#   trace_walk.sh [options] <device udid> <walk id>
#
# The walk runs as run_walks.sh runs it (UITests/, WalkTests). After the walk's first launch the
# app holds still for --hold seconds; meanwhile xctrace attaches to it, and records until the
# walk ends and the app quits, or for --limit seconds. Whatever happened before the attach
# (the launch itself) is not in the trace: measure launch with measure.sh.
#
# What an attached recording holds (iPad, iPadOS 26.7, Xcode 26.2): the time profile and the
# Allocations track (open walk.trace in Instruments; xctrace cannot export Allocations). The
# Hitches and os_signpost tables came back empty when attaching; for hitches and the app's
# signposts use measure.sh, whose recordings launch the app.
#
# Options:
#   --team <TEAMID>       The (personal) team the app and the runner are signed with. Required.
#   --out <dir>           Where the trace, the result bundle and the screenshots go. Default: a
#                         new folder under ${TMPDIR}ehshoko-walks/.
#   --derived-data <dir>  The build's folder. Default: ${TMPDIR}ehshoko-walks/DerivedData-iphoneos-<configuration>.
#   --no-build            Use the last build of that folder.
#   --debug               Trace a Debug build (default: Release with the HARNESS condition, as
#                         the budgets are measured).
#   --hold <s>            How long the app waits for xctrace after launching (default 25).
#   --limit <s>           The longest recording (default 600).
#   --fixture, --fixture-args, --app-args, --patience: as run_walks.sh.
#
# Writes walk.trace (open it in Instruments), toc.xml (what it holds), the walk's screenshots
# and results.md, as run_walks.sh does.
#
# Example, from the repository root:
#   Scripts/trace_walk.sh --team ABCDE12345 00008027-0000000000000000 preset-wall
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

team=""
out=""
derived=""
build=YES
configuration=Release
hold=25
limit=600
fixture=offline
fixture_args=""
app_args=""
patience=""

die() { echo "trace_walk.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) team="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --derived-data) derived="$2"; shift 2 ;;
    --no-build) build=NO; shift ;;
    --debug) configuration=Debug; shift ;;
    --hold) hold="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --fixture) fixture="$2"; shift 2 ;;
    --fixture-args) fixture_args="$2"; shift 2 ;;
    --app-args) app_args="$2"; shift 2 ;;
    --patience) patience="$2"; shift 2 ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done

[[ $# -eq 2 ]] || die "usage: trace_walk.sh [options] <device udid> <walk id> (see --help)"
udid="$1"
walk="$2"
[[ -n "$team" ]] || die "--team <TEAMID> is required: the app and the runner are signed for it"
[[ "$walk" != *,* ]] || die "one walk at a time"

bundle_id="app.ehshoko.$team"
destination="platform=iOS,id=$udid"
base="${TMPDIR:-/tmp/}ehshoko-walks"
derived="${derived:-$base/DerivedData-iphoneos-$configuration}"
out="${out:-$base/$(date +%Y%m%d-%H%M%S)-trace-$walk}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

if [[ "$build" == YES ]]; then
  echo "Building for testing ($configuration) into $derived" >&2
  build_settings=()
  [[ "$configuration" == Release ]] && build_settings=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) HARNESS')
  xcodebuild build-for-testing -project "$root/EhShoko.xcodeproj" -scheme EhShoko \
    -configuration "$configuration" -destination "$destination" -only-testing:EhShokoUITests \
    -derivedDataPath "$derived" -skipMacroValidation -quiet \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration "APP_BUNDLE_ID=$bundle_id" \
    "DEVELOPMENT_TEAM=$team" CODE_SIGN_STYLE=Automatic PROVISIONING_PROFILE_SPECIFIER= \
    "CODE_SIGN_IDENTITY=Apple Development" ${build_settings[@]+"${build_settings[@]}"} \
    > "$out/build.log" 2>&1 || { tail -30 "$out/build.log" >&2; die "the build failed (build.log)"; }
fi

xctestrun="$(ls -t "$derived"/Build/Products/*_iphoneos*.xctestrun 2>/dev/null | head -1 || true)"
[[ -n "$xctestrun" ]] || die "no .xctestrun in $derived; build first"

# The pid of our app on the device: the process whose executable is inside this bundle's
# install folder, so nothing else on the device is ever touched.
app_pid() {
  local apps="$out/.apps.json" processes="$out/.processes.json"
  xcrun devicectl device info apps --device "$udid" --bundle-id "$bundle_id" --json-output "$apps" >/dev/null 2>&1 || return 0
  xcrun devicectl device info processes --device "$udid" --json-output "$processes" >/dev/null 2>&1 || return 0
  python3 -I - "$apps" "$processes" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]
folders = [app["url"] for app in apps if app.get("url")]
for process in json.load(open(sys.argv[2]))["result"]["runningProcesses"]:
    executable = process.get("executable", "")
    if folders and any(executable.startswith(folder) for folder in folders):
        print(process["processIdentifier"])
        break
PY
  rm -f "$apps" "$processes"
}

export TEST_RUNNER_WALKS="$walk"
export TEST_RUNNER_WALK_FIXTURE="$fixture"
export TEST_RUNNER_WALK_HOLD="$hold"
[[ -n "$fixture_args" ]] && export TEST_RUNNER_WALK_FIXTURE_ARGS="$fixture_args"
[[ -n "$app_args" ]] && export TEST_RUNNER_WALK_EXTRA_ARGS="$app_args"
[[ -n "$patience" ]] && export TEST_RUNNER_WALK_PATIENCE="$patience"

printf '%s\n' "device=$udid" "walk=$walk" "fixture=$fixture" "configuration=$configuration" \
  "hold=$hold" "started=$(date '+%Y-%m-%d %H:%M:%S')" > "$out/run.txt"

echo "Walking $walk on $udid" >&2
rm -rf "$out/walks.xcresult" "$out/walk.trace"
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" \
  -only-testing:EhShokoUITests/WalkTests -resultBundlePath "$out/walks.xcresult" \
  > "$out/test.log" 2>&1 &
test_pid=$!
trap 'kill "$test_pid" 2>/dev/null || true' EXIT

# A pid seen before the walk's own launch belongs to an app left from an earlier run.
stale="$(app_pid)"
pid=""
echo "Waiting for the walk to launch the app" >&2
for _ in $(seq 1 300); do
  kill -0 "$test_pid" 2>/dev/null || die "the test ended before the app was seen (test.log)"
  pid="$(app_pid)"
  [[ -n "$pid" && "$pid" != "$stale" ]] && break
  pid=""
  /bin/sleep 2
done
[[ -n "$pid" ]] || die "the app did not start within ten minutes"

echo "Recording pid $pid → $out/walk.trace" >&2
echo "attached=$(date '+%Y-%m-%d %H:%M:%S') pid=$pid" >> "$out/run.txt"
# xctrace exits non-zero for warnings too; whether the trace is usable shows in its toc.
xcrun xctrace record --quiet --no-prompt --device "$udid" --template "Time Profiler" \
  --instrument Allocations --instrument Hitches --instrument os_signpost \
  --attach "$pid" --time-limit "${limit}s" --output "$out/walk.trace" \
  > "$out/xctrace.log" 2>&1 || echo "trace_walk.sh: xctrace reported issues (xctrace.log)" >&2

wait "$test_pid" || true
trap - EXIT
echo "finished=$(date '+%Y-%m-%d %H:%M:%S')" >> "$out/run.txt"

if [[ -d "$out/walk.trace" ]]; then
  xcrun xctrace export --input "$out/walk.trace" --toc --output "$out/toc.xml" >/dev/null 2>&1 || true
  echo "Tables in the trace:" >&2
  grep -o 'schema="[^"]*"' "$out/toc.xml" 2>/dev/null | sort -u | sed 's/^/  /' >&2 || true
fi
[[ -d "$out/walks.xcresult" ]] && python3 -I "$here/walk_report.py" "$out" --destination "device:$udid"
