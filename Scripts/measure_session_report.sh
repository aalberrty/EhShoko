#!/usr/bin/env bash
# Reports a session recorded by measure_session.sh: exports and prints the numbers of every
# block's folder (measure.sh report), which needs the traces and not the device, then writes
# one table of all of them.
#
#   measure_session_report.sh <session folder> [block ...]
#
# Writes <block>.report.txt beside each block's folder and session-report.md in the session
# folder, and prints the table. Blocks already reported are reported again only when named.
# Exporting a list block's time profile takes a few minutes.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  ""|-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
esac
session="$(cd "$1" && pwd)"
shift
[[ -f "$session/session.tsv" ]] || { echo "measure_session_report.sh: no session.tsv in $session" >&2; exit 1; }

for folder in "$session"/*/; do
  name="$(basename "$folder")"
  [[ -f "$folder/run.txt" ]] || continue
  if [[ $# -gt 0 ]]; then
    [[ " $* " == *" $name "* ]] || continue
  elif [[ -f "$session/$name.report.txt" && -f "$folder/summary.json" ]]; then
    continue
  fi
  echo "Reporting $name" >&2
  python3 -I "$here/measure_report.py" "$folder" > "$session/$name.report.txt" 2>&1 \
    || echo "measure_session_report.sh: the report of $name failed ($name.report.txt)" >&2
done

python3 -I "$here/measure_report.py" --session "$session" | tee "$session/session-report.md"
