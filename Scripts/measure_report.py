#!/usr/bin/env python3
"""Prints the numbers of a measure.sh run from its traces and the harness's result files.

    measure_report.py <run folder>

Reads, when present: hitches-<n>.trace (Animation Hitches with os_signpost), result-<n>.json
(the list harness's own result), time.trace (Time Profiler), alloc.trace (Allocations) and
signposts.trace (os_signpost). Only the standard library is used.
"""

import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SUBSYSTEM = "app.ehgaro"


def export(trace, xpath):
    """The XML of one xctrace export query, or None when the trace has no such table."""
    result = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", xpath],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or "<row" not in result.stdout:
        return None
    return ElementTree.fromstring(result.stdout)


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


def report_hitches(trace, result_file, index):
    print(f"  Run {index}")
    if trace.exists():
        report_instruments_hitches(trace)
    if result_file.exists():
        result = json.loads(result_file.read_text())
        print(f"    Harness: {result['frames']} frames in {result['duration']:.1f} s, "
              f"hitch time ratio {result['hitchRatioMsPerS']:.1f} ms/s, "
              f"worst {result['worstHitchMs']:.0f} ms, "
              f"{result['longHitchesAfterFirstScreen']} frames of 3+ durations after the first screen, "
              f"{'reached the end' if result['reachedEnd'] else 'did NOT reach the end'}")
        print(f"    Footprint at the end: {result['footprintMB']:.0f} MB (peak {result['peakFootprintMB']:.0f} MB), "
              f"{result['coversServed']} covers served")
    else:
        print("    Harness: no result file")


def report_instruments_hitches(trace):
    intervals = signpost_intervals(trace)
    window = scroll_window(intervals)
    rows = table_rows(trace, "hitches-summary")
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
        print(f"    Instruments: scroll {seconds:.1f} s, {len(hitches)} hitches, "
              f"hitch time ratio {total / seconds:.1f} ms/s, worst hitch {worst:.0f} ms")
    elif rows:
        print("    Instruments: no HarnessScroll interval in the trace; hitches not bounded to the run")
    else:
        print("    Instruments: no hitches table (Animation Hitches recorded nothing here)")


APP_BINARIES = ("EhGaro", "EhGaro.debug.dylib")


def report_time_profile(trace):
    """The main thread's busy time during the scroll, the leaf functions it spent it in, and
    the app's own functions nearest the leaf (where list and cell code shows up)."""
    window = scroll_window(signpost_intervals(trace))
    rows, resolve = table_rows(trace, "time-profile", with_resolver=True)
    if not rows:
        print(f"  {trace.name}: no time-profile table")
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
    for interval in intervals:
        detail = " ".join(part for part in (interval["begin"], interval["end"]) if part)
        print(f"    {interval['name']:<13} {interval['duration'] / 1e6:8.1f} ms  {detail}")
        end = interval["start"] + interval["duration"]
        for event in events:
            if event["name"] == interval["name"] and interval["start"] <= event["time"] <= end:
                offset = (event["time"] - interval["start"]) / 1e6
                print(f"      event {event['message']} at {offset:.1f} ms, {(end - event['time']) / 1e6:.1f} ms before the end")


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
    for index in indices:
        report_hitches(folder / f"hitches-{index}.trace", folder / f"result-{index}.json", index)
    if (folder / "time.trace").exists():
        report_time_profile(folder / "time.trace")
    if (folder / "alloc.trace").exists():
        report_allocations(folder / "alloc.trace")
    if (folder / "signposts.trace").exists():
        report_signposts(folder / "signposts.trace")


if __name__ == "__main__":
    main()
