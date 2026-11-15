#!/usr/bin/env python3
"""Prints the numbers of a measure.sh run from its traces and the harness's result files.

    measure_report.py <run folder>

Reads, when present: hitches-<n>.trace (Animation Hitches with os_signpost), result-<n>.json
(the list harness's own result), time-<n>.trace (Time Profiler), alloc.trace (Allocations),
signposts-<n>.trace (os_signpost) and footprint-<n>.json (the footprint a timed run ended
with). With several runs it ends with the median and spread of each figure, and writes every
figure of every run to summary.json in the run folder. Only the standard library is used.
"""

import json
import re
import statistics
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SUBSYSTEM = "app.ehshoko"

# Every figure of every run, by name: {"Launch ms": [412.0, 398.5, ...]}. Printed as medians
# and spreads at the end and written to summary.json.
FIGURES = {}


def note(name, value):
    FIGURES.setdefault(name, []).append(float(value))


def export(trace, xpath):
    """The XML of one xctrace export query, or None when the trace has no such table.

    xctrace export crashes now and then (exit 139, no output; seen half the time on device
    traces under load), so a failed export is retried before the table counts as missing.
    """
    for _ in range(EXPORT_ATTEMPTS):
        result = subprocess.run(
            ["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", xpath],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            break
    else:
        print(f"    (xctrace export failed {EXPORT_ATTEMPTS} times for {trace.name}: exit {result.returncode})")
        return None
    if "<row" not in result.stdout:
        return None
    return ElementTree.fromstring(result.stdout)


EXPORT_ATTEMPTS = 6


def table_rows(trace, schema, with_resolver=False):
    """Rows of the first table with this schema, as dicts of column mnemonic -> element.

    xctrace writes a value once with an id and refers to it later with ref; the row's values
    are resolved, and with_resolver also returns the function that resolves nested ones.
    """
    root = export(trace, f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]')
    if root is None:
        return ([], lambda element: element) if with_resolver else []
    by_id = {}
    for element in root.iter():
        if "id" in element.attrib:
            by_id[element.attrib["id"]] = element

    def resolve(element):
        return by_id.get(element.attrib["ref"], element) if "ref" in element.attrib else element

    rows = []
    for node in root.iter("node"):
        columns = [col.findtext("mnemonic") for col in node.iter("col")]
        for row in node.iter("row"):
            values = {}
            for mnemonic, element in zip(columns, list(row)):
                values[mnemonic] = resolve(element)
            rows.append(values)
    return (rows, resolve) if with_resolver else rows


def number(element):
    """The raw value of an element (nanoseconds for times and durations)."""
    if element is None:
        return 0
    text = (element.text or "").strip()
    if not text:
        children = list(element)
        return number(children[0]) if children else 0
    try:
        return int(text)
    except ValueError:
        try:
            return float(text)
        except ValueError:
            return 0


def text(element):
    if element is None:
        return ""
    return element.attrib.get("fmt") or (element.text or "").strip()


def signpost_intervals(trace):
    """The app's os_signpost intervals: dicts of name, category, start, duration, messages."""
    intervals = []
    for row in table_rows(trace, "os-signpost-interval"):
        if text(row.get("subsystem")) != SUBSYSTEM:
            continue
        intervals.append({
            "name": text(row.get("name")),
            "category": text(row.get("category")),
            "start": number(row.get("start")),
            "duration": number(row.get("duration")),
            "begin": text(row.get("start-message")),
            "end": text(row.get("end-message")),
        })
    return sorted(intervals, key=lambda interval: interval["start"])


def scroll_window(intervals):
    runs = [interval for interval in intervals if interval["name"] == "HarnessScroll"]
    if not runs:
        return None
    return runs[0]["start"], runs[0]["start"] + runs[0]["duration"]


def report_hitches(trace, result_file, index, galleries=0):
    print(f"  Run {index}")
    if trace.exists():
        report_instruments_hitches(trace)
        # On a device the Animation Hitches template records a time profile too, so the main
        # thread's cost per row comes from the same scroll.
        report_time_profile(trace, galleries)
    result = json.loads(result_file.read_text()) if result_file.exists() else {}
    if result.get("stale"):
        print("    Harness: this run left no result (the app did not run)")
    elif result:
        print(f"    Harness: {result['frames']} frames in {result['duration']:.1f} s, "
              f"hitch time ratio {result['hitchRatioMsPerS']:.1f} ms/s, "
              f"worst {result['worstHitchMs']:.0f} ms, "
              f"{result['longHitchesAfterFirstScreen']} frames of 3+ durations after the first screen, "
              f"{'reached the end' if result['reachedEnd'] else 'did NOT reach the end'}")
        print(f"    Footprint at the end: {result['footprintMB']:.0f} MB (peak {result['peakFootprintMB']:.0f} MB), "
              f"{result['coversServed']} covers served")
        note("Harness hitch time ratio ms/s", result["hitchRatioMsPerS"])
        note("Harness worst hitch ms", result["worstHitchMs"])
        note("Harness long hitches after the first screen", result["longHitchesAfterFirstScreen"])
        note("Footprint at the end of the scroll MB", result["footprintMB"])
        note("Peak footprint during the scroll MB", result["peakFootprintMB"])
    else:
        print("    Harness: no result file")


# Three frames at 120 Hz.
LONG_HITCH_NS = 25_000_000


def report_instruments_hitches(trace):
    intervals = signpost_intervals(trace)
    window = scroll_window(intervals)
    # "hitches" on a device with Xcode 26; the summary table of earlier versions as a fallback.
    rows = table_rows(trace, "hitches") or table_rows(trace, "hitches-summary")
    hitches = []
    for row in rows:
        start = number(row.get("start"))
        duration = number(row.get("duration"))
        if window and not window[0] <= start <= window[1]:
            continue
        hitches.append(duration)
    if window:
        seconds = (window[1] - window[0]) / 1e9
        total = sum(hitches) / 1e6
        worst = max(hitches, default=0) / 1e6
        long_hitches = sum(1 for hitch in hitches if hitch >= LONG_HITCH_NS)
        print(f"    Instruments: scroll {seconds:.1f} s, {len(hitches)} hitches, "
              f"hitch time ratio {total / seconds:.1f} ms/s, worst hitch {worst:.0f} ms, "
              f"{long_hitches} of three frames or more")
        note("Instruments hitch time ratio ms/s", total / seconds)
        note("Instruments worst hitch ms", worst)
        note("Instruments hitches", len(hitches))
        note("Instruments hitches of 3+ frames", long_hitches)
    elif rows:
        print("    Instruments: no HarnessScroll interval in the trace; hitches not bounded to the run")
    else:
        print("    Instruments: no hitches table (Animation Hitches recorded nothing here)")


APP_BINARIES = ("EhShoko", "EhShoko.debug.dylib")


def report_time_profile(trace, galleries=0):
    """The main thread's busy time during the scroll, the leaf functions it spent it in, and
    the app's own functions nearest the leaf (where list and cell code shows up)."""
    window = scroll_window(signpost_intervals(trace))
    rows, resolve = table_rows(trace, "time-profile", with_resolver=True)
    if not rows:
        print(f"    {trace.name}: no time-profile table")
        return
    leaves, app_frames, total = {}, {}, 0
    for row in rows:
        if window and not window[0] <= number(row.get("time")) <= window[1]:
            continue
        if "Main Thread" not in text(row.get("thread")):
            continue
        weight = number(row.get("weight")) or 1_000_000
        total += weight
        stack = row.get("stack")
        frames = [resolve(frame) for frame in stack.iter("frame")] if stack is not None else []
        leaf = frames[0].attrib.get("name", "?") if frames else "?"
        leaves[leaf] = leaves.get(leaf, 0) + weight
        for frame in frames:
            binary = frame.find("binary")
            binary = resolve(binary) if binary is not None else None
            if binary is not None and binary.attrib.get("name") in APP_BINARIES:
                name = frame.attrib.get("name", "?")
                if name.endswith("$main()") or name == "main":
                    name = "(system frameworks only, under main)"
                app_frames[name] = app_frames.get(name, 0) + weight
                break
    seconds = (window[1] - window[0]) / 1e9 if window else 0
    print(f"  {trace.name}")
    if seconds:
        print(f"    Main thread busy {total / 1e6 / seconds:.0f} ms/s during the scroll "
              f"({total / 1e6:.0f} ms in {seconds:.1f} s)")
        note("Main thread busy during the scroll ms/s", total / 1e6 / seconds)
        if galleries:
            # Every row of the list appears once during the scroll, so this is the main thread's
            # whole cost per new row: the cell, and its share of scrolling and drawing.
            print(f"    Per new row: {total / 1e6 / galleries:.2f} ms of main-thread time ({galleries} rows)")
            note("Main thread per new row ms", total / 1e6 / galleries)
    print("    Heaviest leaf functions on the main thread:")
    for name, weight in sorted(leaves.items(), key=lambda item: -item[1])[:6]:
        print(f"      {weight / 1e6:7.0f} ms  {name[:100]}")
    print("    Heaviest app functions nearest the leaf:")
    for name, weight in sorted(app_frames.items(), key=lambda item: -item[1])[:6]:
        print(f"      {weight / 1e6:7.0f} ms  {name[:100]}")


def report_allocations(trace):
    print(f"  {trace.name}: open in Instruments for the cover check (one decoded bitmap per cover, "
          f"about 0.35 MB each: filter for CGImage / ImageIO)")


def report_signposts(trace):
    intervals = [interval for interval in signpost_intervals(trace) if interval["category"] == "Performance"]
    events = signpost_events(trace)
    print(f"  {trace.name}: {len(intervals)} intervals")
    seen = set()
    for interval in intervals:
        detail = " ".join(part for part in (interval["begin"], interval["end"]) if part)
        duration = interval["duration"] / 1e6
        print(f"    {interval['name']:<13} {duration:8.1f} ms  {detail}")
        # The first interval of each kind (and of each list) is the one a run measures.
        key = interval["name"] + (f" {interval['begin']}" if interval["name"] == "ListPage" else "")
        first = key not in seen
        seen.add(key)
        if first and interval["end"] != "abandoned":
            note(f"{key} ms", duration)
            since_start = re.match(r"(\d+) ms since process start", interval["end"])
            if interval["name"] == "Launch" and since_start:
                note("Launch since process start ms", int(since_start.group(1)))
        end = interval["start"] + interval["duration"]
        for event in events:
            if event["name"] == interval["name"] and interval["start"] <= event["time"] <= end:
                offset = (event["time"] - interval["start"]) / 1e6
                print(f"      event {event['message']} at {offset:.1f} ms, {(end - event['time']) / 1e6:.1f} ms before the end")
                if first:
                    note(f"{interval['name']} event {event['message']} at ms", offset)
                    note(f"{interval['name']} after event {event['message']} ms", (end - event["time"]) / 1e6)
    report_transition_hitches(trace, intervals)


def report_launch(trace):
    """Instruments' App Launch phases: the time to the first frame, from the start of process
    creation to the end of the initial frame's rendering, and the app's own part of it, which
    leaves out process creation (the system's, and longer when Instruments launches the app)."""
    rows = table_rows(trace, "life-cycle-period")
    phases = [(number(row.get("start")), number(row.get("duration")), text(row.get("period"))) for row in rows]
    if not phases:
        print(f"  {trace.name}: no life-cycle table")
        return
    begin = min(start for start, _, _ in phases)
    frames = [start + duration for start, duration, period in phases if "Initial Frame Rendering" in period]
    creation = sum(duration for _, duration, period in phases if "Process Creation" in period)
    if not frames:
        print(f"  {trace.name}: no initial frame in the trace")
        return
    total = (frames[0] - begin) / 1e6
    own = total - creation / 1e6
    print(f"  {trace.name}: first frame {total:.0f} ms after the process was created "
          f"(process creation {creation / 1e6:.0f} ms, the app's part {own:.0f} ms)")
    for start, duration, period in phases:
        print(f"      {(start - begin) / 1e6:8.1f} ms  {duration / 1e6:7.1f} ms  {period}")
    note("Time to first frame ms", total)
    note("Process creation ms", creation / 1e6)
    note("Time to first frame after process creation ms", own)


# How long after an opening begins its transition is watched for hitches.
TRANSITION_NS = 600_000_000


def report_transition_hitches(trace, intervals):
    """With an Animation Hitches recording: the hitches in the first 600 ms of the first
    GalleryOpen and ReaderOpen, which is when the sheet or the cover animates in."""
    rows = table_rows(trace, "hitches")
    if not rows:
        return
    hitches = [(number(row.get("start")), number(row.get("duration"))) for row in rows]
    for name in ("GalleryOpen", "ReaderOpen"):
        opening = next((interval for interval in intervals if interval["name"] == name), None)
        if opening is None:
            continue
        begin = opening["start"]
        inside = [duration for start, duration in hitches if begin <= start <= begin + TRANSITION_NS]
        worst = max(inside, default=0) / 1e6
        print(f"    {name} transition: {len(inside)} hitches in its first 600 ms, "
              f"{sum(inside) / 1e6:.0f} ms in all, worst {worst:.0f} ms")
        note(f"{name} transition hitches", len(inside))
        note(f"{name} transition hitch time ms", sum(inside) / 1e6)
        note(f"{name} transition worst hitch ms", worst)


def report_footprint(path):
    footprint = json.loads(path.read_text())
    if footprint.get("stale"):
        print(f"  {path.name}: none (the app did not run)")
        return
    print(f"  {path.name}: {footprint['footprintMB']:.0f} MB at the end (peak {footprint['peakFootprintMB']:.0f} MB)")
    note("Footprint at the end of the run MB", footprint["footprintMB"])
    note("Peak footprint MB", footprint["peakFootprintMB"])


def report_summary(folder):
    """The median of each figure over the runs, its range, and how far the runs stray from the
    median, which is what "repeatable to ±10%" is judged by."""
    (folder / "summary.json").write_text(json.dumps(FIGURES, indent=2, sort_keys=True))
    several = {name: values for name, values in FIGURES.items() if len(values) > 1}
    if not several:
        return
    print("Summary over the runs (median, range, largest deviation from the median, runs within ±10%)")
    for name, values in several.items():
        median = statistics.median(values)
        deviation = max(abs(value - median) for value in values)
        within = sum(1 for value in values if abs(value - median) <= abs(median) * 0.1)
        relative = f"±{deviation / abs(median) * 100:.0f}%" if median else "n/a"
        print(f"  {name:<52} {median:9.1f}   {min(values):9.1f} – {max(values):<9.1f} {relative:>6}   "
              f"{within}/{len(values)} in ±10%")


def signpost_events(trace):
    """The app's Performance signpost events (such as LaunchReady): name, message and time."""
    events = []
    for row in table_rows(trace, "os-signpost"):
        if text(row.get("event-type")) != "Event" or text(row.get("subsystem")) != SUBSYSTEM:
            continue
        if text(row.get("category")) != "Performance":
            continue
        events.append({"name": text(row.get("name")), "message": text(row.get("message")),
                       "time": number(row.get("time"))})
    return events


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = Path(sys.argv[1])
    run = folder / "run.txt"
    print(f"Run in {folder}")
    if run.exists():
        print("  " + ", ".join(run.read_text().split()))
    indices = sorted({int(re.sub(r"\D", "", path.stem) or 0)
                      for path in [*folder.glob("hitches-*.trace"), *folder.glob("result-*.json")]})
    galleries = 0
    if run.exists():
        match = re.search(r"^count=(\d+)$", run.read_text(), re.MULTILINE)
        galleries = int(match.group(1)) if match else 0
    for index in indices:
        report_hitches(folder / f"hitches-{index}.trace", folder / f"result-{index}.json", index, galleries)
    for trace in sorted(folder.glob("time*.trace"), key=run_index):
        report_time_profile(trace, galleries)
    if (folder / "alloc.trace").exists():
        report_allocations(folder / "alloc.trace")
    for trace in sorted(folder.glob("launch*.trace"), key=run_index):
        report_launch(trace)
        report_signposts(trace)
    for trace in sorted(folder.glob("signposts*.trace"), key=run_index):
        report_signposts(trace)
        footprint = folder / f"footprint-{run_index(trace)}.json"
        if footprint.exists():
            report_footprint(footprint)
    report_summary(folder)


def run_index(path):
    digits = re.sub(r"\D", "", path.stem)
    return int(digits) if digits else 0


if __name__ == "__main__":
    main()
