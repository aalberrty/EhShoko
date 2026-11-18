#!/usr/bin/env bash
# Runs a whole measuring session on a device, record only, block after block, so that the
# device is needed for the recordings and for nothing else. Report afterwards, with the device
# locked or gone: Scripts/measure_session_report.sh <session folder>.
#
#   measure_session.sh [options] <device udid> [block ...]
#
# A session is for a phone whose screen must not be left on a still picture. So:
#   - nothing is exported or reported while it runs (measure.sh --no-report);
#   - whenever no recording is on the screen (a trace being saved, the gap between two
#     blocks) the device shows the rest screen: black, one dim moving line (measure.sh rest);
#   - the lists scroll several times per launch, and hitches are recorded on the light
#     template, so no save takes minutes;
#   - the light recordings come first and the scrolls last.
# The device has to be unlocked once, at the start. The script waits for that (it tries to
# show the rest screen until the device lets it) and sounds the Mac's alert while it waits;
# from then on the app keeps the screen awake, and nobody has to touch the device until the
# script says the session is over. If a block records nothing the script waits for the device
# in the same way and tries that block once more.
#
# Blocks, in order (name them to run only some, in this order whatever the order given):
#   warm-up        The real app once with the gallery link and once with the page link, not
#                  measured: the gallery and the page's image URL are stored afterwards.
#   launch-shelf   Launch to first frame and first content, the real app under each preset:
#   launch-wall    Shelf (the tab bar, Home), Wall (the command bar, the Front Page), Ledger
#   launch-ledger  (the command bar, the Index). App Launch template, the app quits after 8 s.
#   gallery-shelf  The gallery opened from a link, in each gallery design: GalleryOpen, its
#   gallery-wall   Stored and Response events, the hitches of the opening.
#   gallery-ledger
#   reader-shelf   The reader opened on the gallery's first page with an empty image cache,
#   reader-wall    in each reader design: ReaderOpen, the hitches of the cover animation,
#   reader-ledger  the footprint 15 s after launch (memory while reading).
#   list-shelf, list-ledger, list-wall-medium, list-wall-small
#                  The list harness's scroll over 500 galleries, each list design by itself.
#   list-wall-large-bar, list-shelf-tags-bar
#                  The same under the command bar's glass: the largest covers, the tallest rows.
#   shell-tabs-wall-small, shell-tabs-shelf
#                  The scroll in the real shell under the tab bar and its accessory: the most
#                  cells per frame, and Shelf's own list.
#   stage          The moving preview playing for 40 s.
#
# With --plan finger the session is the finger check instead: four lists scrolled by a hand,
# then the same scroll by the script, as it is and with the cores awake, to see what a real
# scroll gets of the CPU and whether the script's figures stand for it:
#   hand-shelf, hand-shelf-grid, hand-ledger, hand-wall-medium
#                  Each list is on the screen for --seconds (default 30) and closes by itself.
#                  Whoever holds the device flicks it up, fast, for as long as it is there.
#   hand-wall-small
#                  Wall's five columns in the same way; only when named.
#   script-shelf, script-shelf-awake
#                  Shelf's list scrolled by the script, twice each; nobody is needed. The Mac
#                  plays another sound than its alert when the hand's part is over.
#
# Options:
#   --plan <name>      full (default): the blocks above. finger: the finger check.
#   --seconds <s>      finger: how long each hand-scrolled list stays (default 30).
#   --width <pt>       The lists' width (430: a phone's lists, for rehearsing on an iPad).
#   --bundle-id <id>   The app to measure. Default: $APP_BUNDLE_ID. Required one way or the
#                      other: a session never guesses which copy of the app it drives.
#   --app <path>       Install this build first (a Release build with the HARNESS condition;
#                      see measure.sh).
#   --out <dir>        The session's folder. Default: a new one under ${TMPDIR}ehshoko-session.
#   --quick            One run of every recording and two scrolls per list: a rehearsal that
#                      shows every block works, in a quarter of the time.
#   --animation        Record hitches on the Animation Hitches template instead of the light
#                      one (the saves take minutes).
#   --gallery <url>    The gallery link the real app opens. Default: the one the baseline used.
#   --page <url>       The link to that gallery's first image page.
#   --uninstall        Remove the app from the device when the session is over.
#   --after <command>  Run this (with sh -c) as soon as the last recording is made and the app
#                      has ended, before the alert that says the device can be locked: for
#                      what has to happen while the device is still awake and reachable, such
#                      as installing another build over the measured one.
#   --list             Print the blocks and their recordings, and do nothing.
#
# Writes into --out: one folder per block (traces, results; what measure.sh writes), the log
# of each block (<block>.log) and session.tsv: block, start, end, seconds, recordings made,
# recordings expected.
#
# Example, from the repository root, with the measured build installed:
#   APP_BUNDLE_ID=app.ehshoko.ABCDE12345.measure Scripts/measure_session.sh 00008120-0000000000000000
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bundle_id="${APP_BUNDLE_ID:-}"
app=""
out=""
quick=NO
light=YES
uninstall=NO
after=""
list_only=NO
plan=full
hand_seconds=30
width=""
# The baseline's gallery (measurements: an old, small, Non-H art book that is likely to stay).
gallery="https://e-hentai.org/g/80319/317c988b37/"
page="https://e-hentai.org/s/0c56814304/80319-1"

die() { echo "measure_session.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id) bundle_id="$2"; shift 2 ;;
    --app) app="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --quick) quick=YES; shift ;;
    --animation) light=NO; shift ;;
    --gallery) gallery="$2"; shift 2 ;;
    --page) page="$2"; shift 2 ;;
    --uninstall) uninstall=YES; shift ;;
    --plan) plan="$2"; shift 2 ;;
    --seconds) hand_seconds="$2"; shift 2 ;;
    --width) width="$2"; shift 2 ;;
    --after) after="$2"; shift 2 ;;
    --list) list_only=YES; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done

device="${1:-}"
[[ -n "$device" || "$list_only" == YES ]] || die "name the device (see --help)"
[[ $# -eq 0 ]] || shift
only=("$@")
[[ -n "$bundle_id" || "$list_only" == YES ]] || die "--bundle-id (or \$APP_BUNDLE_ID) is required"

# How often each recording is made, and how often each list scrolls in one launch.
if [[ "$quick" == YES ]]; then
  launch_runs=1 gallery_runs=1 reader_runs=1 shell_runs=2
  long_scrolls=2 short_scrolls=2
else
  launch_runs=6 gallery_runs=5 reader_runs=6 shell_runs=3
  # A scroll of Shelf's rows or of Wall's largest covers takes three quarters of a minute, the
  # others a quarter to a half.
  long_scrolls=4 short_scrolls=6
fi

hitches=()
[[ "$light" == NO ]] || hitches=(--light)
[[ "$plan" == full || "$plan" == finger ]] || die "unknown plan $plan (full, finger)"
# The lists' width, for the blocks that show the list harness.
narrow=()
[[ -z "$width" ]] || narrow=(--width "$width")

out="${out:-${TMPDIR:-/tmp/}ehshoko-session/$(date +%Y%m%d-%H%M%S)}"

# The launch arguments that put the real app under a preset, for this launch only: an
# argument overrides a stored setting without changing it. The offer after install would
# cover the first screen of a new copy.
preset_arguments=()
preset() {
  local bar=command part
  [[ "$1" != shelf ]] || bar=tabs
  preset_arguments=(--app-arg -settings.designBar --app-arg "$bar")
  for part in Start List Gallery Reader Search Library Look; do
    preset_arguments+=(--app-arg "-settings.design$part" --app-arg "$1")
  done
  # A Bool setting is read as a property list value, so "YES" would not do.
  preset_arguments+=(--app-arg -settings.experienceOfferShown --app-arg "<true/>")
}

selected() {
  [[ ${#only[@]} -gt 0 ]] || return 0
  local name
  for name in "${only[@]}"; do [[ "$name" != "$1" ]] || return 0; done
  return 1
}

# The Mac's alert, for the moments somebody has to do something with the device.
alert() {
  afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 || true
}

measure() {
  "$here/measure.sh" --device "$device" --bundle-id "$bundle_id" "$@"
}

# Shows the rest screen, waiting for as long as the device will not let an app start (it is
# locked): every 5 s, with the alert every half minute.
wait_for_device() {
  local label="$1" tries=0
  until xcrun devicectl device process launch --device "$device" --terminate-existing -- "$bundle_id" \
      -Harness rest -HarnessRestLabel "$label" >/dev/null 2>&1; do
    if (( tries % 6 == 0 )); then
      echo "[$(date +%H:%M:%S)] The device will not start the app: unlock it (waiting)" >&2
      alert
    fi
    tries=$((tries + 1))
    /bin/sleep 5
  done
}

blocks=()
total=0
index=0

# block <name> <recordings> <what the device shows> <measure.sh arguments...>
block() {
  local name="$1" expected="$2" shows="$3"
  shift 3
  selected "$name" || return 0
  if [[ "$list_only" == YES ]]; then
    printf '%-24s %2d recording(s)  %s\n    measure.sh %s\n' "$name" "$expected" "$shows" "$*"
    return 0
  fi
  index=$((index + 1))
  local folder="$out/$name" attempt made=0 started ended
  started="$(date +%s)"
  echo "[$(date +%H:%M:%S)] Block $index of $total: $name ($shows)" >&2
  for attempt in 1 2; do
    rm -rf "$folder"
    measure --no-report --rest "block $index of $total" --out "$folder" "$@" > "$out/$name.log" 2>&1 || true
    made="$(find "$folder" -maxdepth 1 -name '*.trace' | wc -l | tr -d ' ')"
    (( made < expected )) || break
    echo "[$(date +%H:%M:%S)] $name made $made of $expected recordings (attempt $attempt; see $name.log)" >&2
    [[ $attempt -eq 1 ]] || break
    wait_for_device "waiting to repeat block $index of $total"
  done
  ended="$(date +%s)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$(/bin/date -r "$started" +%H:%M:%S)" "$(/bin/date -r "$ended" +%H:%M:%S)" \
    "$((ended - started))" "$made" "$expected" >> "$out/session.tsv"
}

# Says, on the Mac, that the hand's part is over, with another sound than the alert (which
# means "the device needs you"). Not a block.
cue() {
  [[ "$list_only" == NO ]] || return 0
  echo "[$(date +%H:%M:%S)] $1" >&2
  afplay /System/Library/Sounds/Hero.aiff >/dev/null 2>&1 || true
}

# Whether a block was asked for by name: for the blocks a plan leaves out unless named.
named() {
  local name
  for name in ${only[@]+"${only[@]}"}; do [[ "$name" != "$1" ]] || return 0; done
  return 1
}

# The finger check: the hand's lists first, so that whoever flicks them can leave after them.
session_finger() {
  local hand="--count 3000"
  block hand-shelf 1 "Shelf's list, to be flicked by hand for $hand_seconds s" \
    ${hitches[@]+"${hitches[@]}"} ${narrow[@]+"${narrow[@]}"} $hand hand shelf "$hand_seconds"
  block hand-shelf-grid 1 "Shelf's list in its lazy grid, to be flicked by hand for $hand_seconds s" \
    ${hitches[@]+"${hitches[@]}"} ${narrow[@]+"${narrow[@]}"} $hand hand shelf-grid "$hand_seconds"
  block hand-ledger 1 "Ledger's list, to be flicked by hand for $hand_seconds s" \
    ${hitches[@]+"${hitches[@]}"} ${narrow[@]+"${narrow[@]}"} $hand hand ledger "$hand_seconds"
  block hand-wall-medium 1 "Wall's wall, three columns, to be flicked by hand for $hand_seconds s" \
    ${hitches[@]+"${hitches[@]}"} ${narrow[@]+"${narrow[@]}"} $hand hand wall-medium "$hand_seconds"
  # Only when named: the list that builds the most cells a second.
  if named hand-wall-small; then
    block hand-wall-small 1 "Wall's wall, five columns, to be flicked by hand for $hand_seconds s" \
      ${hitches[@]+"${hitches[@]}"} ${narrow[@]+"${narrow[@]}"} $hand hand wall-small "$hand_seconds"
  fi
  cue "The hand's part is over: the rest runs by itself"
  block script-shelf 1 "Shelf's list scrolled by the script, twice" \
    --templates hitches ${hitches[@]+"${hitches[@]}"} ${narrow[@]+"${narrow[@]}"} --scrolls 2 list shelf
  block script-shelf-awake 1 "Shelf's list scrolled by the script with the cores awake, twice" \
    --templates hitches ${hitches[@]+"${hitches[@]}"} ${narrow[@]+"${narrow[@]}"} --scrolls 2 --awake list shelf
}

# Every block of the session, in order. Called twice: to count the selected ones, then to run.
session() {
  if [[ "$plan" == finger ]]; then
    session_finger
    return
  fi
  preset shelf
  block warm-up 2 "the app; the test gallery and its first page open once" \
    --runs 2 --link "$page" --exit-after 12 "${preset_arguments[@]}" signposts 30

  local style
  for style in shelf wall ledger; do
    preset "$style"
    block "launch-$style" "$launch_runs" "the app starting on $style's first screen, $launch_runs times" \
      --runs "$launch_runs" --exit-after 8 "${preset_arguments[@]}" launch 20
  done
  for style in shelf wall ledger; do
    preset "$style"
    block "gallery-$style" "$gallery_runs" "the test gallery opening in $style's page, $gallery_runs times" \
      --runs "$gallery_runs" ${hitches[@]+"${hitches[@]}"} --link "$gallery" --exit-after 10 "${preset_arguments[@]}" signposts 30
  done
  for style in shelf wall ledger; do
    preset "$style"
    block "reader-$style" "$reader_runs" "the test gallery's first page opening in $style's reader, $reader_runs times" \
      --runs "$reader_runs" ${hitches[@]+"${hitches[@]}"} --link "$page" --clear-images --exit-after 15 "${preset_arguments[@]}" signposts 35
  done

  local list="--templates hitches"
  block list-shelf 1 "Shelf's list of synthetic covers scrolling, $long_scrolls times" \
    $list ${hitches[@]+"${hitches[@]}"} --scrolls "$long_scrolls" list shelf
  block list-ledger 1 "Ledger's list scrolling, $short_scrolls times" \
    $list ${hitches[@]+"${hitches[@]}"} --scrolls "$short_scrolls" list ledger
  block list-wall-medium 1 "Wall's wall, three columns, scrolling, $short_scrolls times" \
    $list ${hitches[@]+"${hitches[@]}"} --scrolls "$short_scrolls" list wall-medium
  block list-wall-small 1 "Wall's wall, five columns, scrolling, $short_scrolls times" \
    $list ${hitches[@]+"${hitches[@]}"} --scrolls "$short_scrolls" list wall-small
  block list-wall-large-bar 1 "Wall's wall, two columns, under the command bar, $long_scrolls times" \
    $list ${hitches[@]+"${hitches[@]}"} --scrolls "$long_scrolls" --bar list wall-large
  block list-shelf-tags-bar 1 "Shelf's list with tags under the command bar, $long_scrolls times" \
    $list ${hitches[@]+"${hitches[@]}"} --scrolls "$long_scrolls" --bar --tags list shelf
  # The part harness makes one scroll per launch (its stage, built again, is not found by
  # the scroller in time), so these two repeat the launch instead.
  block shell-tabs-wall-small "$shell_runs" "Wall's five columns in the shell under the tab bar, $shell_runs times" \
    ${hitches[@]+"${hitches[@]}"} --runs "$shell_runs" shell -HarnessPreset shelf -HarnessList wall -HarnessDensity small
  block shell-tabs-shelf "$shell_runs" "Shelf's list in the shell under the tab bar, $shell_runs times" \
    ${hitches[@]+"${hitches[@]}"} --runs "$shell_runs" shell -HarnessPreset shelf

  block stage 1 "the moving preview playing in a sheet for 40 s" \
    ${hitches[@]+"${hitches[@]}"} --app-arg -Harness --app-arg previews --app-arg -HarnessPage --app-arg stage \
    --app-arg -HarnessOpen --app-arg YES signposts 40
}

if [[ "$list_only" == YES ]]; then
  session
  exit 0
fi

# Count the blocks that will run, without running them.
total="$(list_only=YES; session | grep -c 'recording(s)')"
[[ "$total" -gt 0 ]] || die "no block of that name (see --help)"

mkdir -p "$out"
out="$(cd "$out" && pwd)"
printf 'block\tstart\tend\tseconds\trecordings\texpected\n' > "$out/session.tsv"
printf '%s\n' "device=$device" "bundle_id=$bundle_id" "plan=$plan" "quick=$quick" "light=$light" \
  "started=$(date '+%Y-%m-%d %H:%M:%S')" "load=$(uptime | sed 's/.*load averages*: //')" > "$out/session.txt"

if [[ -n "$app" ]]; then
  echo "[$(date +%H:%M:%S)] Installing $app" >&2
  xcrun devicectl device install app --device "$device" "$app" > "$out/install.log" 2>&1 \
    || { tail -5 "$out/install.log" >&2; die "the install failed (install.log)"; }
fi

echo "[$(date +%H:%M:%S)] $total blocks → $out" >&2
wait_for_device "starting"
echo "[$(date +%H:%M:%S)] The device shows the rest screen; recording starts" >&2
session
measure stop || { alert; alert; echo "[$(date +%H:%M:%S)] The app could not be ended: close it on the device by hand" >&2; }
echo "finished=$(date '+%Y-%m-%d %H:%M:%S')" >> "$out/session.txt"

if [[ "$uninstall" == YES ]]; then
  xcrun devicectl device uninstall app --device "$device" "$bundle_id" > "$out/uninstall.log" 2>&1 \
    || echo "measure_session.sh: could not remove the app (uninstall.log)" >&2
fi

if [[ -n "$after" ]]; then
  echo "[$(date +%H:%M:%S)] Running: $after" >&2
  sh -c "$after" > "$out/after.log" 2>&1 || echo "measure_session.sh: the --after command failed (after.log)" >&2
fi

alert
echo "[$(date +%H:%M:%S)] The session is over: the device can be locked. Folder: $out" >&2
column -t -s "$(printf '\t')" "$out/session.tsv" >&2
echo "Report: Scripts/measure_session_report.sh $out" >&2
