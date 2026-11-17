#!/usr/bin/env python3
"""Prints the numbers of a measure.sh run from its traces and the harness's result files.

    measure_report.py <run folder>
    measure_report.py --session <session folder>    one table of a session's blocks, each
                                                     reported before (measure_session_report.sh)

Reads, when present: hitches-<n>.trace (Animation Hitches with os_signpost), result-<n>.json
(the list harness's own result), time-<n>.trace (Time Profiler), alloc.trace (Allocations),
signposts-<n>.trace (os_signpost) and footprint-<n>.json (the footprint a timed run ended
with). With several runs it ends with the median and spread of each figure, and writes every
figure of every run to summary.json in the run folder. Only the standard library is used.
"""

import json
import re
import statistics
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SUBSYSTEM = "app.ehshoko"

# Every figure of every run, by name: {"Launch ms": [412.0, 398.5, ...]}. Printed as medians
# and spreads at the end and written to summary.json.
FIGURES = {}


def note(name, value):
    FIGURES.setdefault(name, []).append(float(value))


def export(trace, xpath):
    """The path of a file holding the XML of one xctrace export query, or None when the trace
    has no such table. The caller removes the file.

    xctrace export crashes at random (exit 139, no output: an over-release inside the tool,
    whatever the template and however quiet the Mac; one export in two to one in eight
    succeeds), so a failed export is retried many times before the table counts as missing.
    """
    handle, path = tempfile.mkstemp(suffix=".xml", prefix="ehshoko-export-")
    os.close(handle)
    for _ in range(EXPORT_ATTEMPTS):
        result = subprocess.run(
            ["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", xpath, "--output", path],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            return path
    os.remove(path)
    print(f"    (xctrace export failed {EXPORT_ATTEMPTS} times for {trace.name}: exit {result.returncode})")
    return None


EXPORT_ATTEMPTS = 40


def iter_rows(trace, schema):
    """The rows of the first table with this schema, one at a time, as pairs of a dict
    (column mnemonic -> element) and the function that resolves a reference.

    xctrace writes a value once with an id and refers to it later with ref; a row's own values
    are resolved. The export is read as a stream and each row is dropped once it has been
    handed over, so a time profile of several minutes (gigabytes of XML) does not have to fit
    in memory: only the values later rows refer to are kept.
    """
    path = export(trace, f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]')
    if path is None:
        return
    by_id = {}

    def resolve(element):
        return by_id.get(element.attrib["ref"], element) if "ref" in element.attrib else element

    try:
        columns, node = [], None
        for event, element in ElementTree.iterparse(path, events=("start", "end")):
            if event == "start":
                # Several tables of one schema come as several nodes; only the first names
                # the columns.
                if element.tag == "node":
                    node = element
                elif element.tag == "schema":
                    columns = []
                continue
            if "id" in element.attrib:
                by_id[element.attrib["id"]] = element
            if element.tag == "col":
                columns.append(element.findtext("mnemonic"))
            elif element.tag == "row":
                yield {mnemonic: resolve(value) for mnemonic, value in zip(columns, list(element))}, resolve
                if node is not None:
                    node.remove(element)
    except ElementTree.ParseError:
        # An export without the table is a document with no rows, or an empty file.
        return
    finally:
        os.remove(path)


def table_rows(trace, schema):
    """Rows of the first table with this schema, as dicts of column mnemonic -> element."""
    return [row for row, _ in iter_rows(trace, schema)]


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


def scroll_windows(intervals):
    """The start and end of every scripted scroll in the trace, in order."""
    return [(interval["start"], interval["start"] + interval["duration"])
            for interval in intervals if interval["name"] == "HarnessScroll"]


def harness_results(result_file):
    """The harness's results of one launch, one per scroll. A launch of an older build wrote
    one result at the top level."""
    if not result_file.exists():
        return []
    result = json.loads(result_file.read_text())
    if result.get("stale"):
        return [None]
    return result.get("runs", [result])


def report_hitches(trace, result_file, index, galleries=0):
    print(f"  Run {index}")
    windows = []
    if trace.exists():
        windows = scroll_windows(signpost_intervals(trace))
        report_instruments_hitches(trace, windows)
        # On a device the recording holds a time profile too, so the main thread's cost per
        # row comes from the same scroll.
        report_time_profile(trace, galleries, windows)
    results = harness_results(result_file)
    if not results:
        print("    Harness: no result file")
    if trace.exists() and results != [None] and len(results) != len(windows):
        print(f"    (the trace holds {len(windows)} scrolls, the harness reported {len(results)})")
    for scroll, result in enumerate(results, start=1):
        label = f"Harness, scroll {scroll}" if len(results) > 1 else "Harness"
        if result is None:
            print("    Harness: this run left no result (the app did not run)")
            continue
        print(f"    {label}: {result['slot']}, {result['frames']} frames in {result['duration']:.1f} s, "
              f"hitch time ratio {result['hitchRatioMsPerS']:.1f} ms/s, "
              f"worst {result['worstHitchMs']:.0f} ms, "
              f"{result['longHitchesAfterFirstScreen']} frames of 3+ durations after the first screen, "
              f"{'reached the end' if result['reachedEnd'] else 'did NOT reach the end'}")
        print(f"      Footprint at the end: {result['footprintMB']:.0f} MB (peak {result['peakFootprintMB']:.0f} MB), "
              f"{result['coversServed']} covers served, {result.get('coversDecoded', 0)} decoded by CoverImage; "
              f"main thread {result.get('mainThreadCPUMs', 0):.0f} ms of CPU for {result.get('cellsCreated', 0)} cells, "
              f"{result.get('cpuPerCellMs', 0):.2f} ms a cell")
        note("Harness hitch time ratio ms/s", result["hitchRatioMsPerS"])
        note("Harness worst hitch ms", result["worstHitchMs"])
        note("Harness long hitches after the first screen", result["longHitchesAfterFirstScreen"])
        note("Footprint at the end of the scroll MB", result["footprintMB"])
        note("Peak footprint during the scroll MB", result["peakFootprintMB"])
        if result.get("cellsCreated"):
            note("Harness main-thread CPU per created cell ms", result["cpuPerCellMs"])
            note("Harness main-thread CPU during the scroll ms/s",
                 result["mainThreadCPUMs"] / result["duration"] if result["duration"] else 0)
            note("Covers decoded per cover served", result.get("coversDecoded", 0) / max(result["coversServed"], 1))


# Three frames at 120 Hz.
LONG_HITCH_NS = 25_000_000


def report_instruments_hitches(trace, windows):
    # "hitches" on a device with Xcode 26; the summary table of earlier versions as a fallback.
    rows = table_rows(trace, "hitches") or table_rows(trace, "hitches-summary")
    hitches = [(number(row.get("start")), number(row.get("duration"))) for row in rows]
    if not windows:
        if rows:
            print("    Instruments: no HarnessScroll interval in the trace; hitches not bounded to the run")
        else:
            print("    Instruments: no hitches table (the recording holds no hitches)")
        return
    for scroll, (begin, end) in enumerate(windows, start=1):
        inside = [duration for start, duration in hitches if begin <= start <= end]
        seconds = (end - begin) / 1e9
        total = sum(inside) / 1e6
        worst = max(inside, default=0) / 1e6
        long_hitches = sum(1 for hitch in inside if hitch >= LONG_HITCH_NS)
        label = f"Instruments, scroll {scroll}" if len(windows) > 1 else "Instruments"
        print(f"    {label}: scroll {seconds:.1f} s, {len(inside)} hitches, "
              f"hitch time ratio {total / seconds:.1f} ms/s, worst hitch {worst:.0f} ms, "
              f"{long_hitches} of three frames or more")
        note("Instruments hitch time ratio ms/s", total / seconds)
        note("Instruments worst hitch ms", worst)
        note("Instruments hitches", len(inside))
        note("Instruments hitches of 3+ frames", long_hitches)
    if not rows:
        print("    (the trace has no hitches table: no hitch, or the instrument recorded nothing)")


APP_BINARIES = ("EhShoko", "EhShoko.debug.dylib")


def report_time_profile(trace, galleries=0, windows=None):
    """The main thread's busy time during each scroll, the leaf functions it spent it in, and
    the app's own functions nearest the leaf (where list and cell code shows up)."""
    if windows is None:
        windows = scroll_windows(signpost_intervals(trace))
    leaves, app_frames, totals, seen = {}, {}, [0] * max(len(windows), 1), False
    for row, resolve in iter_rows(trace, "time-profile"):
        seen = True
        time = number(row.get("time"))
        scroll = next((index for index, (begin, end) in enumerate(windows) if begin <= time <= end), None)
        if windows and scroll is None:
            continue
        if "Main Thread" not in text(row.get("thread")):
            continue
        weight = number(row.get("weight")) or 1_000_000
        totals[scroll or 0] += weight
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
    if not seen:
        print(f"    {trace.name}: no time-profile table")
        return
    print(f"  {trace.name}")
    for scroll, (begin, end) in enumerate(windows):
        seconds, total = (end - begin) / 1e9, totals[scroll]
        label = f"Scroll {scroll + 1}: main" if len(windows) > 1 else "Main"
        line = (f"    {label} thread busy {total / 1e6 / seconds:.0f} ms/s during the scroll "
                f"({total / 1e6:.0f} ms in {seconds:.1f} s)")
        note("Main thread busy during the scroll ms/s", total / 1e6 / seconds)
        if galleries:
            # Every row of the list appears once during the scroll, so this is the main thread's
            # whole cost per new row: the cell, and its share of scrolling and drawing.
            line += f"; per new row {total / 1e6 / galleries:.2f} ms ({galleries} rows)"
            note("Main thread per new row ms", total / 1e6 / galleries)
        print(line)
    print("    Heaviest leaf functions on the main thread:")
    for name, weight in sorted(leaves.items(), key=lambda item: -item[1])[:6]:
        print(f"      {weight / 1e6:7.0f} ms  {name[:100]}")
    print("    Heaviest app functions nearest the leaf:")
    for name, weight in sorted(app_frames.items(), key=lambda item: -item[1])[:6]:
        print(f"      {weight / 1e6:7.0f} ms  {name[:100]}")


def report_allocations(trace):
    print(f"  {trace.name}: open in Instruments for the cover check (one decoded bitmap per cover, "
          f"about 0.35 MB each: filter for CGImage / ImageIO)")


# What a Response event's message starts with (PerformanceInterval.responseEvent).
RESPONSE = "Response"


def belongs(event, interval):
    """Whether an event is one of this interval's. Several ListPage intervals run at once (the
    first screen's lists), so a ListPage's Response event names its list."""
    if event["name"] != interval["name"]:
        return False
    if not interval["start"] <= event["time"] <= interval["start"] + interval["duration"]:
        return False
    if interval["name"] == "ListPage" and event["message"].startswith(RESPONSE):
        return event["message"] == f"{RESPONSE} {interval['begin']}"
    return True


def report_signposts(trace):
    every = [interval for interval in signpost_intervals(trace) if interval["category"] == "Performance"]
    intervals = [interval for interval in every if interval["name"] in BUDGET_INTERVALS]
    events = signpost_events(trace)
    print(f"  {trace.name}: {len(intervals)} intervals")
    report_drawing(every)
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
        own = [event for event in events if belongs(event, interval)]
        for event in own:
            offset = (event["time"] - interval["start"]) / 1e6
            print(f"      event {event['message']} at {offset:.1f} ms, {(end - event['time']) / 1e6:.1f} ms before the end")
        if not first or interval["end"] == "abandoned":
            continue
        # An operation that asked twice (an empty page skipped) has two answers; the last
        # one is the answer that was applied.
        latest = {}
        for event in own:
            latest[event["message"].split(" ")[0] if event["message"].startswith(RESPONSE) else event["message"]] = event
        for message, event in latest.items():
            note(f"{key} event {message} at ms", (event["time"] - interval["start"]) / 1e6)
            note(f"{key} after event {message} ms", (end - event["time"]) / 1e6)
    report_first_content_response(intervals, events)
    report_transition_hitches(trace, intervals)


# The intervals of PerformanceSignposts.Name, one line each. The category holds others that
# come once per drawn frame (the previews' SchematicDraw, the moving preview's StageDraw),
# which are counted instead.
BUDGET_INTERVALS = ("Launch", "FirstContent", "GalleryOpen", "ReaderOpen", "ListPage")


def report_drawing(intervals):
    """The per-frame drawing intervals of the previews, by name: how many, their median,
    their longest and their sum, which is main-thread time."""
    by_name = {}
    for interval in intervals:
        if interval["name"] not in BUDGET_INTERVALS:
            by_name.setdefault(interval["name"], []).append(interval["duration"] / 1e6)
    for name, durations in by_name.items():
        print(f"    {name}: {len(durations)} intervals, median {statistics.median(durations):.2f} ms, "
              f"longest {max(durations):.2f} ms, {sum(durations):.1f} ms in all")
        note(f"{name} intervals", len(durations))
        note(f"{name} median ms", statistics.median(durations))
        note(f"{name} longest ms", max(durations))


def report_first_content_response(intervals, events):
    """How long after the site's answer the first screen's rows were in its model: from the
    last Response of the list that ended FirstContent to FirstContent's end."""
    first = next((interval for interval in intervals if interval["name"] == "FirstContent"), None)
    if first is None or first["end"] == "abandoned":
        return
    end = first["start"] + first["duration"]
    answers = [event for event in events
               if event["name"] == "ListPage" and event["message"].startswith(f"{RESPONSE} {first['end']}")
               and event["time"] <= end]
    if not answers:
        return
    after = (end - max(event["time"] for event in answers)) / 1e6
    print(f"    FirstContent: rows in the model {after:.1f} ms after the response ({first['end']})")
    note("FirstContent after the response ms", after)


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


def report_session(folder):
    """One table for a session (measure_session.sh): a row per figure of each block, from the
    summary.json measure_report.py wrote in each block's folder."""
    session = folder / "session.tsv"
    blocks = [line.split("\t") for line in session.read_text().splitlines()[1:]] if session.exists() else []
    names = [block[0] for block in blocks] or sorted(path.parent.name for path in folder.glob("*/summary.json"))
    print("| Block | Figure | Median | Range | Spread | Runs |")
    print("|---|---|---|---|---|---|")
    for name in names:
        summary = folder / name / "summary.json"
        if not summary.exists():
            print(f"| {name} | (no report) | | | | |")
            continue
        for figure, values in json.loads(summary.read_text()).items():
            median = statistics.median(values)
            deviation = max(abs(value - median) for value in values)
            spread = f"±{deviation / abs(median) * 100:.0f}%" if median else "—"
            print(f"| {name} | {figure} | {median:.1f} | {min(values):.1f} – {max(values):.1f} | {spread} | {len(values)} |")
    if blocks:
        print()
        print("| Block | Start | End | Seconds | Recordings |")
        print("|---|---|---|---|---|")
        for block in blocks:
            print(f"| {block[0]} | {block[1]} | {block[2]} | {block[3]} | {block[4]} of {block[5]} |")
        print(f"\nRecording time on the device: {sum(int(block[3]) for block in blocks) / 60:.1f} min")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--session":
        report_session(Path(sys.argv[2]))
        return
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
        footprint = folder / f"footprint-{run_index(trace)}.json"
        if footprint.exists():
            report_footprint(footprint)
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
