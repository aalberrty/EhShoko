#!/usr/bin/env bash
# Records a list scrolled by touches on a device: a UI test (EhShokoUITests, ScrollProbeTests)
# flicks the list harness's list while Instruments records the app, so that a touch-driven
# scroll can be set beside the harness's scripted one (measure.sh list). The touches come
# through the system as a finger's do; the hand itself is measure.sh hand.
#
#   measure_touch.sh [options] <device udid> <slot> [seconds]
#
# The UI test starts first and waits for the app; when it is running, measure.sh hand launches
# the list (which closes by itself after the seconds, default 45) and records it; the test
# flicks it meanwhile. The report is measure.sh's for a list scrolled by hand.
#
# Options:
#   --team <TEAMID>       The team the app and the runner are signed with. Required: the app
#                         is app.ehshoko.<TEAMID> and the runner app.ehshoko.<TEAMID>.uitests.
#   --derived-data <dir>  The build's folder. Default: ${TMPDIR}ehshoko-touch/DerivedData.
#   --no-build            Use that folder's last build (build-for-testing is skipped).
#   --out <dir>           Where the trace, the test's log and the result go. Default: a new
#                         folder under ${TMPDIR}ehshoko-touch.
#   --width <pt>          The list's width (430: a phone's list on an iPad).
#   --count <n>           Galleries in the list (default 3000, enough for a minute of flicks).
#   --flicks <n>          How many flicks (default 12).   --velocity <pt/s>   Their speed (default 3000).
#   --awake               A thread keeps the performance cores awake (see measure.sh --awake).
#   --no-report           Record only; report later with measure.sh report <dir>.
#   --chime               Sound the Mac's alert, three times, while the runner waits for the
#                         device to allow UI automation (8 s after the runner is up, then
#                         every 6 s until the test starts), and once when a run ends because
#                         the device did not allow it: the device may be asking for its
#                         passcode, and somebody has to look at it. Off unless asked for.
#
# UI automation on a device needs Settings › Developer › Enable UI Automation. A start that
# fails for that reason is tried once more straight away; then the script gives up.
#
# Example, from the repository root:
#   Scripts/measure_touch.sh --team ABCDE12345 --width 430 00008027-0000000000000000 shelf
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

team=""
derived=""
build=YES
out=""
width=""
count=3000
flicks=12
velocity=3000
awake=NO
report=YES
chimes=NO

die() { echo "measure_touch.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) team="$2"; shift 2 ;;
    --derived-data) derived="$2"; shift 2 ;;
    --no-build) build=NO; shift ;;
    --out) out="$2"; shift 2 ;;
    --width) width="$2"; shift 2 ;;
    --count) count="$2"; shift 2 ;;
    --flicks) flicks="$2"; shift 2 ;;
    --velocity) velocity="$2"; shift 2 ;;
    --awake) awake=YES; shift ;;
    --no-report) report=NO; shift ;;
    --chime) chimes=YES; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done

[[ $# -ge 2 ]] || die "usage: measure_touch.sh [options] <device udid> <slot> [seconds] (see --help)"
udid="$1"
slot="$2"
seconds="${3:-45}"
[[ -n "$team" ]] || die "--team <TEAMID> is required: the app and the runner are signed for it"

bundle_id="app.ehshoko.$team"
destination="platform=iOS,id=$udid"
base="${TMPDIR:-/tmp/}ehshoko-touch"
derived="${derived:-$base/DerivedData}"
out="${out:-$base/$(date +%Y%m%d-%H%M%S)-$slot}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

# The Mac's alert, for whoever has to look at the device.
chime() {
  [[ "$chimes" == YES ]] || return 0
  osascript -e 'set volume output volume 100' -e 'set volume without output muted' >/dev/null 2>&1 || true
  local index
  for index in 1 2 3; do afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 || true; done
}

if [[ "$build" == YES ]]; then
  echo "Building for testing into $derived" >&2
  xcodebuild build-for-testing -project "$root/EhShoko.xcodeproj" -scheme EhShoko -configuration Release \
    -destination "$destination" -only-testing:EhShokoUITests -derivedDataPath "$derived" \
    -skipMacroValidation -quiet -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "APP_BUNDLE_ID=$bundle_id" "DEVELOPMENT_TEAM=$team" CODE_SIGN_STYLE=Automatic PROVISIONING_PROFILE_SPECIFIER= \
    "CODE_SIGN_IDENTITY=Apple Development" 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) HARNESS' \
    > "$out/build.log" 2>&1 || { tail -30 "$out/build.log" >&2; die "the build failed (build.log)"; }
fi

xctestrun="$(ls -t "$derived"/Build/Products/*_iphoneos*.xctestrun 2>/dev/null | head -1 || true)"
[[ -n "$xctestrun" ]] || die "no .xctestrun in $derived; build first"
app="$derived/Build/Products/Release-iphoneos/EhShoko.app"
[[ -d "$app" ]] || die "no app in $derived; build first"
xcrun devicectl device install app --device "$udid" "$app" > "$out/install.log" 2>&1 \
  || { tail -5 "$out/install.log" >&2; die "the install failed (install.log)"; }

runner_is_up() {
  xcrun devicectl device info processes --device "$udid" 2>/dev/null | grep -q "EhShokoUITests-Runner"
}

# Whether the run's log says the device did not allow UI automation.
was_refused() {
  grep -qE "Authentication canceled|enabling automation mode" "$1" 2>/dev/null
}

# One attempt: 0 when the list was recorded, 2 when UI automation did not start, 1 otherwise.
attempt() {
  local log="$out/test-$1.log" test_pid up="" last_chime=0 now
  export TEST_RUNNER_PROBE_FLICKS="$flicks" TEST_RUNNER_PROBE_VELOCITY="$velocity"
  xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" \
    -only-testing:EhShokoUITests/ScrollProbeTests -resultBundlePath "$out/touch-$1.xcresult" > "$log" 2>&1 &
  test_pid=$!
  echo "[$(date +%H:%M:%S)] Attempt $1: waiting for the UI test to start" >&2
  # The runner is up, the test has not started: UI automation is waiting for the device.
  until grep -q "testFlicks.*started" "$log" 2>/dev/null; do
    kill -0 "$test_pid" 2>/dev/null || break
    # A locked device keeps xcodebuild waiting for good; nothing can be recorded.
    if grep -q "because the device is locked" "$log" 2>/dev/null; then
      kill "$test_pid" 2>/dev/null || true
      wait "$test_pid" 2>/dev/null || true
      echo "measure_touch.sh: the device is locked: wake and unlock it, then run this again" >&2
      return 1
    fi
    now="$(date +%s)"
    if [[ -z "$up" ]]; then
      ! runner_is_up || up="$now"
    elif (( now - up >= 8 && now - last_chime >= 6 )); then
      echo "[$(date +%H:%M:%S)] The test has not started: the device may be asking for something" >&2
      chime
      last_chime="$(date +%s)"
    fi
    /bin/sleep 1
  done
  if ! grep -q "testFlicks.*started" "$log" 2>/dev/null; then
    wait "$test_pid" 2>/dev/null || true
    grep -E "Timed out|Authentication|initialize|is locked|error:" "$log" | head -3 >&2 || true
    if was_refused "$log"; then
      chime
      return 2
    fi
    return 1
  fi
  echo "[$(date +%H:%M:%S)] The test is running: recording $slot" >&2
  local options=(--device "$udid" --bundle-id "$bundle_id" --light --count "$count" --no-report --out "$out")
  [[ -z "$width" ]] || options+=(--width "$width")
  [[ "$awake" == NO ]] || options+=(--awake)
  "$here/measure.sh" "${options[@]}" hand "$slot" "$seconds" >&2 || true
  # The list has closed by itself; the test's last flicks find no app and end it.
  wait "$test_pid" 2>/dev/null || true
  [[ -d "$out/hitches-1.trace" ]]
}

status=0
attempt 1 || status=$?
if [[ $status -eq 2 ]]; then
  echo "[$(date +%H:%M:%S)] UI automation did not start; trying once more" >&2
  status=0
  attempt 2 || status=$?
fi
[[ $status -eq 0 ]] || die "nothing was recorded (see the test's log in $out)"

printf '%s\n' "touch=ui-test" "flicks=$flicks" "velocity=$velocity" >> "$out/run.txt"
[[ "$report" == NO ]] || python3 -I "$here/measure_report.py" "$out"
