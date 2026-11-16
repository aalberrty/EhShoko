#!/usr/bin/env bash
# Runs a set of UI walks (the EhShokoUITests target, UITests/) on one simulator or device and
# writes their screenshots and a table of results.
#
#   run_walks.sh [options] <destination> <set>
#
# Destination:
#   simulator:<udid>      A simulator; booted first if it is not running.
#   device:<udid>         A device (its UDID, as xcodebuild names it), over the cable or the
#                         network. Needs --team (the app is signed for that team).
#   booted                The one booted simulator.
#
# Set: presets, swaps, mixes, device (the steps done once per device), all, or walk ids,
# comma-separated (preset-wall,mix-3,device-offer). UITests/Walks/WalkCatalogue.swift lists them.
#
# Options:
#   --out <dir>           Where the result bundle, screenshots and table go. Default: a new
#                         folder under ${TMPDIR}ehshoko-walks/.
#   --derived-data <dir>  The build's folder. Default: ${TMPDIR}ehshoko-walks/DerivedData-<platform>.
#   --no-build            Run the last build of that folder again (build-for-testing is skipped).
#   --team <TEAMID>       Device signing with this (personal) team: the app becomes
#                         app.ehshoko.<TEAMID> and the runner app.ehshoko.<TEAMID>.uitests.
#   --fixture <name>      offline (default): the part harness's whole shell, its seeded database
#                         and offline client. signedIn: the same, signed in with named folders
#                         and the first gallery's fuller page (-HarnessSignedIn YES -HarnessRich
#                         YES). live: the real app, its own data and the network.
#   --fixture-args "<a>"  Other launch arguments for the signed-in fixture (for example
#                         "-HarnessSignedIn YES -HarnessNetwork YES" to load lists through the
#                         harness's recording client).
#   --app-args "<a>"      More launch arguments for every launch.
#   --patience <s>        Seconds to wait for an element (default 20); raise it on a loaded Mac.
#   --dumps               Attach the accessibility tree at every screenshot (for writing walks).
#   --keep-going          After a failed part of a walk, note it and go on with the next part
#                         (to survey a new walk in one run); the walk still counts as failed.
#   --fresh               Remove the app from the destination first (the offer after install).
#   --release             Build Release with the HARNESS condition (optimised, as measured).
#   --append <file>       Also append the table's rows to this Markdown file (one table for
#                         several destinations).
#
# Writes into --out: walks.xcresult, one folder per walk with its screenshots
# (<nn>-<name>.png, FAILED.png and tree-*.txt when a step failed) and its record
# (walk-result.json), results.md (walk, destination, passed or the failing step, time) and
# results.json.
#
# Examples, from the repository root:
#   Scripts/run_walks.sh simulator:DF19E3E7-B596-4249-9090-CD32DE851CAB presets
#   Scripts/run_walks.sh --team ABCDE12345 device:00008027-0000000000000000 preset-shelf,mix-6
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

out=""
derived=""
build=YES
team=""
fixture=offline
fixture_args=""
app_args=""
patience=""
dumps=NO
keep_going=NO
fresh=NO
configuration=Debug
append=""

die() { echo "run_walks.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --derived-data) derived="$2"; shift 2 ;;
    --no-build) build=NO; shift ;;
    --team) team="$2"; shift 2 ;;
    --fixture) fixture="$2"; shift 2 ;;
    --fixture-args) fixture_args="$2"; shift 2 ;;
    --app-args) app_args="$2"; shift 2 ;;
    --patience) patience="$2"; shift 2 ;;
    --dumps) dumps=YES; shift ;;
    --keep-going) keep_going=YES; shift ;;
    --fresh) fresh=YES; shift ;;
    --release) configuration=Release; shift ;;
    --append) append="$2"; shift 2 ;;
    -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done

[[ $# -eq 2 ]] || die "usage: run_walks.sh [options] <destination> <set> (see --help)"
destination="$1"
set="$2"

case "$destination" in
  simulator:*) kind=simulator; udid="${destination#simulator:}" ;;
  device:*) kind=device; udid="${destination#device:}" ;;
  booted)
    kind=simulator
    udid="$(xcrun simctl list devices booted -j | python3 -I -c '
import json, sys
booted = [d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["state"] == "Booted"]
print(booted[0] if len(booted) == 1 else "")')"
    [[ -n "$udid" ]] || die "booted needs exactly one booted simulator" ;;
  *) die "destination must be simulator:<udid>, device:<udid> or booted" ;;
esac

if [[ "$kind" == simulator ]]; then
  xcode_destination="platform=iOS Simulator,id=$udid"
  platform=iphonesimulator
  bundle_id="app.ehshoko"
  signing=()
else
  [[ -n "$team" ]] || die "a device needs --team <TEAMID> to sign the app and the runner"
  xcode_destination="platform=iOS,id=$udid"
  platform=iphoneos
  bundle_id="app.ehshoko.$team"
  signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration
    "APP_BUNDLE_ID=$bundle_id" "DEVELOPMENT_TEAM=$team" CODE_SIGN_STYLE=Automatic
    PROVISIONING_PROFILE_SPECIFIER= "CODE_SIGN_IDENTITY=Apple Development")
fi

base="${TMPDIR:-/tmp/}ehshoko-walks"
derived="${derived:-$base/DerivedData-$platform}"
stamp="$(date +%Y%m%d-%H%M%S)"
out="${out:-$base/$stamp-${set//,/+}}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

build_settings=()
if [[ "$configuration" == Release ]]; then
  build_settings=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) HARNESS')
fi

if [[ "$kind" == simulator ]]; then
  state="$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
for ds in json.load(sys.stdin)["devices"].values():
    for d in ds:
        if d["udid"] == sys.argv[1]: print(d["state"])' "$udid")"
  [[ -n "$state" ]] || die "no simulator $udid"
  if [[ "$state" != Booted ]]; then
    echo "Booting $udid" >&2
    xcrun simctl boot "$udid" || die "the simulator did not boot"
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null
fi

if [[ "$build" == YES ]]; then
  echo "Building for testing ($configuration, $platform) into $derived" >&2
  # Only the UI tests: the scheme's package tests are not built for a device.
  xcodebuild build-for-testing -project "$root/EhShoko.xcodeproj" -scheme EhShoko \
    -configuration "$configuration" -destination "$xcode_destination" \
    -only-testing:EhShokoUITests -derivedDataPath "$derived" -skipMacroValidation -quiet \
    ${signing[@]+"${signing[@]}"} ${build_settings[@]+"${build_settings[@]}"} \
    > "$out/build.log" 2>&1 || { tail -30 "$out/build.log" >&2; die "the build failed (build.log)"; }
fi

xctestrun="$(ls -t "$derived"/Build/Products/*_"$platform"*.xctestrun 2>/dev/null | head -1 || true)"
[[ -n "$xctestrun" ]] || die "no .xctestrun for $platform in $derived; build first"

if [[ "$fresh" == YES ]]; then
  echo "Removing $bundle_id from $udid" >&2
  if [[ "$kind" == simulator ]]; then
    xcrun simctl uninstall "$udid" "$bundle_id" || true
  else
    xcrun devicectl device uninstall app --device "$udid" "$bundle_id" >/dev/null 2>&1 || true
  fi
fi

# What the runner reads (UITests/Walk/Walk.swift, WalkEnvironment). xcodebuild hands
# TEST_RUNNER_<name> to the runner as <name>.
export TEST_RUNNER_WALKS="$set"
export TEST_RUNNER_WALK_FIXTURE="$fixture"
[[ -n "$fixture_args" ]] && export TEST_RUNNER_WALK_FIXTURE_ARGS="$fixture_args"
[[ -n "$app_args" ]] && export TEST_RUNNER_WALK_EXTRA_ARGS="$app_args"
[[ -n "$patience" ]] && export TEST_RUNNER_WALK_PATIENCE="$patience"
[[ "$dumps" == YES ]] && export TEST_RUNNER_WALK_DUMPS=YES
[[ "$keep_going" == YES ]] && export TEST_RUNNER_WALK_KEEP_GOING=YES

printf '%s\n' "destination=$destination" "set=$set" "fixture=$fixture" "configuration=$configuration" \
  "xctestrun=$xctestrun" "started=$(date '+%Y-%m-%d %H:%M:%S')" > "$out/run.txt"

echo "Walking $set on $destination → $out" >&2
rm -rf "$out/walks.xcresult"
status=0
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$xcode_destination" \
  -only-testing:EhShokoUITests/WalkTests -resultBundlePath "$out/walks.xcresult" \
  > "$out/test.log" 2>&1 || status=$?
echo "finished=$(date '+%Y-%m-%d %H:%M:%S') status=$status" >> "$out/run.txt"
[[ -d "$out/walks.xcresult" ]] || { tail -30 "$out/test.log" >&2; die "no result bundle (test.log)"; }

python3 -I "$here/walk_report.py" "$out" --destination "$destination" ${append:+--append "$append"}
