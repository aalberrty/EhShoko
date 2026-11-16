#!/usr/bin/env python3
"""Turns a run_walks.sh result bundle into screenshots by walk and a table of results.

    walk_report.py <run folder> [--destination <name>] [--append <table.md>]

Reads <run folder>/walks.xcresult. Each walk's attachments are named "<walk>__<name>" by the
UI tests (UITests/Walk/WalkRunner.swift); they are exported to <run folder>/<walk>/<name>.png
(or .txt, .json). The table has one row per walk: the walk, the destination, passed or the
step that failed with its reason, and the time. It is written to results.md and results.json
and printed; --append also adds its rows to a shared Markdown table. Only the standard library
is used.
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ATTACHMENT_NAME = re.compile(r"^(?P<name>.*)_\d+_[0-9A-Fa-f-]{36}$")
HEADER = "| Walk | What | Destination | Result | Time |\n|---|---|---|---|---|\n"


def xcresulttool(*arguments):
    return subprocess.run(["xcrun", "xcresulttool", *arguments], check=True, capture_output=True, text=True).stdout


def walk_of_test(name):
    """test_preset_shelf() → preset-shelf (walk ids have dashes, test names underscores)."""
    return name.removesuffix("()").removeprefix("test_").replace("_", "-")


def test_cases(nodes):
    for node in nodes:
        if node.get("nodeType") == "Test Case":
            yield node
        yield from test_cases(node.get("children", []))


def failure_messages(node):
    for child in node.get("children", []):
        if child.get("nodeType") == "Failure Message":
            yield child.get("name", "")
        yield from failure_messages(child)


def export_attachments(bundle, run):
    """Copies every attachment to <run>/<walk>/<name>; returns the walk records by walk."""
    records = {}
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        xcresulttool("export", "attachments", "--path", str(bundle), "--output-path", str(folder))
        manifest = json.loads((folder / "manifest.json").read_text())
        for test in manifest:
            for attachment in test.get("attachments", []):
                suggested = Path(attachment["suggestedHumanReadableName"])
                match = ATTACHMENT_NAME.match(suggested.stem)
                name = match.group("name") if match else suggested.stem
                walk, _, rest = name.partition("__")
                if not rest:
                    # XCTest's own (a recording, UI snapshots) of a failed test.
                    walk, rest = walk_of_test(test["testIdentifier"].split("/")[-1]), "xctest/" + name
                target = run / walk / (rest + suggested.suffix)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(folder / attachment["exportedFileName"], target)
                if rest == "walk-result":
                    records[walk] = json.loads(target.read_text())
    return records


def main():
    arguments = sys.argv[1:]
    if not arguments:
        sys.exit(__doc__)
    run = Path(arguments.pop(0)).resolve()
    destination = append = None
    while arguments:
        option = arguments.pop(0)
        if option == "--destination":
            destination = arguments.pop(0)
        elif option == "--append":
            append = Path(arguments.pop(0))
        else:
            sys.exit(f"walk_report.py: unknown option {option}")

    bundle = run / "walks.xcresult"
    results = json.loads(xcresulttool("get", "test-results", "tests", "--path", str(bundle)))
    devices = results.get("devices", [])
    device = devices[0] if devices else {}
    where = f'{device.get("modelName", destination or "?")} ({device.get("platform", "")} {device.get("osVersion", "")})'.strip()
    records = export_attachments(bundle, run)

    rows = []
    for case in test_cases(results.get("testNodes", [])):
        walk = walk_of_test(case["name"])
        record = records.get(walk, {})
        passed = case.get("result") == "Passed"
        if passed:
            outcome = "passed"
        elif record.get("failedStep"):
            outcome = f'failed at “{record["failedStep"]}”: {record.get("reason", "")}'
        else:
            messages = list(failure_messages(case))
            outcome = "failed: " + ("; ".join(messages) if messages else case.get("result", "?"))
        seconds = record.get("seconds") or case.get("durationInSeconds") or 0
        rows.append({
            "walk": walk, "title": record.get("title", ""), "destination": where, "passed": passed,
            "result": outcome, "seconds": round(seconds, 1), "notes": record.get("notes", []),
            "steps": record.get("steps", []),
        })

    def line(row):
        result = row["result"].replace("|", "\\|").replace("\n", " ")
        title = row["title"].replace("|", "\\|")
        minutes, seconds = divmod(int(row["seconds"]), 60)
        return f'| {row["walk"]} | {title} | {row["destination"]} | {result} | {minutes}:{seconds:02d} |\n'

    table = HEADER + "".join(line(row) for row in rows)
    passed = sum(row["passed"] for row in rows)
    summary = f"{passed} of {len(rows)} walks passed on {where}.\n"
    (run / "results.md").write_text(f"# Walks\n\n{summary}\n{table}")
    (run / "results.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
    if append:
        if not append.exists():
            append.write_text("# Walks\n\n" + HEADER)
        with append.open("a") as file:
            file.writelines(line(row) for row in rows)
    print(table + "\n" + summary, end="")
    print(f"Screenshots: {run}/<walk>/")


if __name__ == "__main__":
    main()
