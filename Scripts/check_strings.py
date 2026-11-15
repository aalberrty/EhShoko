#!/usr/bin/env python3
"""Checks the app's localized strings against each other and against Strings.swift.

  python3 Scripts/check_strings.py          # check, exit 1 on any problem
  python3 Scripts/check_strings.py --write  # also regenerate the Localizable
                                                         # part of App/Generated/Strings.swift

Checks, for App/Resources/*.lproj/Localizable.strings:
  - every file has the same key set (reports keys missing from a file, or extra in it);
  - no key appears twice in one file;
  - every key has the same format specifiers (type and position) in every language;
  - App/Generated/Strings.swift's `enum Localizable` is exactly what SwiftGen's
    `structured-swift5` template produces from en.lproj (swiftgen.yml). SwiftGen is not
    required: this script reproduces that template, so a later `swiftgen` run gives no diff.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "App/Resources"
SWIFT = ROOT / "App/Generated/Strings.swift"
TABLE = "Localizable"

ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
# A printf conversion as SwiftGen reads it: optional position, flags, width, precision,
# length, conversion. `%%` is a literal percent sign.
SPEC = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGcCsSaAp%])")


def parse(path):
    """Returns ([(key, value, comment)], [problems]) for one .strings file.

    As in SwiftGen, a block comment belongs to the next entry; line comments are ignored."""
    entries, problems = [], []
    text = path.read_text(encoding="utf-8")
    comments = {}

    def hold(match):
        line = text.count("\n", 0, match.start()) + 1
        comments[line] = match.group(1).strip()
        return "\n" * match.group(0).count("\n")

    text = re.sub(r"/\*(.*?)\*/", hold, text, flags=re.S)
    pending = None
    for number, line in enumerate(text.split("\n"), 1):
        if number in comments:
            pending = comments[number]
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        match = ENTRY.match(line)
        if not match:
            problems.append(f"{path.relative_to(ROOT)}:{number}: unparsable line: {stripped[:80]}")
            continue
        entries.append((match.group(1), match.group(2), pending))
        pending = None
    return entries, problems


def unescape(value):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), value)


def specifiers(value):
    """Format arguments as {position: type}, positions counted as printf does."""
    result, implicit = {}, 0
    for match in SPEC.finditer(value):
        position, length, conversion = match.groups()
        if conversion == "%":
            continue
        if position:
            index = int(position)
        else:
            implicit += 1
            index = implicit
        result[index] = (length or "") + conversion
    return result


COMMENTS = {}


def check():
    problems = []
    files = sorted(RESOURCES.glob("*.lproj/Localizable.strings"))
    tables = {}
    for path in files:
        entries, parse_problems = parse(path)
        problems += parse_problems
        language = path.parent.name.removesuffix(".lproj")
        seen = {}
        for key, value, comment in entries:
            if key in seen:
                problems.append(f"{language}: duplicate key {key}")
            seen[key] = value
            if language == "en":
                COMMENTS[key] = comment
        tables[language] = seen
    reference = tables["en"]
    for language, table in tables.items():
        for key in sorted(reference.keys() - table.keys()):
            problems.append(f"{language}: missing {key}")
        for key in sorted(table.keys() - reference.keys()):
            problems.append(f"{language}: not in en: {key}")
        for key in sorted(reference.keys() & table.keys()):
            expected, actual = specifiers(reference[key]), specifiers(table[key])
            if expected != actual:
                problems.append(f"{language}: {key}: format {actual} differs from en {expected}")
    return tables, files, problems


# --- SwiftGen structured-swift5, Localizable table ------------------------------------------

RESERVED = set("""associatedtype class deinit enum extension fileprivate func import init inout
internal let open operator private protocol public static struct subscript typealias var break
case continue default defer do else fallthrough for guard if in repeat return switch where while
as Any catch false is nil rethrows super self Self throw throws true try _ associativity
convenience dynamic didSet final get infix indirect lazy left mutating none nonmutating optional
override postfix precedence prefix Protocol required right set Type unowned weak willSet""".split())


def upper_first(text):
    return text[:1].upper() + text[1:]


def pretty_identifier(name):
    # SwiftIdentifier.identifier(replaceWithUnderscores:), then snakeToCamelCase(stripLeading:)
    # and an underscore before a leading digit.
    parts = re.split(r"[^A-Za-z0-9_]", name)
    identifier = "_".join(upper_first(part) for part in parts)
    if any(c.islower() for c in identifier):
        camel = "".join(upper_first(part) for part in identifier.split("_"))
    else:
        camel = "".join(part.capitalize() for part in identifier.lower().split("_"))
    if camel[:1].isdigit():
        camel = "_" + camel
    return camel


def lower_first_word(text):
    index = 0
    while index < len(text) and text[index].isupper():
        index += 1
    if 1 < index < len(text) and text[index].islower():
        index -= 1
    return text[:index].lower() + text[index:]


def escape_reserved(name):
    return f"`{name}`" if name in RESERVED else name


SWIFT_TYPES = {"@": "Any", "d": "Int", "i": "Int", "u": "Int", "ld": "Int", "lld": "Int",
               "f": "Float", "lf": "Float", "c": "CChar", "s": "UnsafePointer<CChar>",
               "p": "UnsafeRawPointer", "x": "Int", "X": "Int", "o": "Int"}


def swift_types(value):
    found = specifiers(unescape(value))
    if not found:
        return []
    return [SWIFT_TYPES.get(found.get(i, "@"), "Any") for i in range(1, max(found) + 1)]


def render(tables):
    tree = {"strings": [], "children": {}}
    for key, value in tables["en"].items():
        node = tree
        *path, leaf = key.split(".")
        for component in path:
            node = node["children"].setdefault(component, {"strings": [], "children": {}})
        node["strings"].append((leaf, key, value))
    lines = ["  internal enum Localizable {"]

    def block(node, indent):
        pad = " " * indent
        for leaf, key, value in sorted(node["strings"], key=lambda s: s[1].lower()):
            translation = unescape(value)
            for line in (COMMENTS.get(key) or translation).split("\n"):
                lines.append(f"{pad}/// {line}")
            literal = (translation.replace('"', '\\"').replace("\t", "\\t")
                       .replace("\n", "\\n"))
            name = escape_reserved(lower_first_word(pretty_identifier(leaf)))
            types = swift_types(value)
            if types:
                params = ", ".join(f"_ p{i}: {t}" for i, t in enumerate(types, 1))
                args = ", ".join(f"String(describing: p{i})" if t == "Any" else f"p{i}"
                                 for i, t in enumerate(types, 1))
                lines.append(f"{pad}internal static func {name}({params}) -> String {{")
                lines.append(f'{pad}  return L10n.tr("{TABLE}", "{key}", {args}, fallback: "{literal}")')
                lines.append(f"{pad}}}")
            else:
                lines.append(f'{pad}internal static let {name} = L10n.tr("{TABLE}", "{key}", fallback: "{literal}")')
        for child in sorted(node["children"], key=str.lower):
            lines.append(f"{pad}internal enum {escape_reserved(pretty_identifier(child))} {{")
            block(node["children"][child], indent + 2)
            lines.append(f"{pad}}}")

    block(tree, 4)
    lines.append("  }")
    return "\n".join(lines)


def swift_problems(tables, write):
    source = SWIFT.read_text(encoding="utf-8")
    start = source.index("  internal enum Localizable {\n")
    end = source.index("\n  }\n", start) + len("\n  }")
    expected = render(tables)
    if source[start:end] == expected:
        return []
    if write:
        SWIFT.write_text(source[:start] + expected + source[end:], encoding="utf-8")
        return []
    current = source[start:end].split("\n")
    wanted = expected.split("\n")
    for number, (have, want) in enumerate(zip(current, wanted), 1):
        if have != want:
            return [f"Strings.swift differs from SwiftGen's output at line {number} of enum "
                    f"Localizable:\n  have: {have.strip()}\n  want: {want.strip()}\n"
                    f"  (run with --write to regenerate)"]
    return [f"Strings.swift's enum Localizable has {len(current)} lines, SwiftGen's {len(wanted)}"]


def main():
    write = "--write" in sys.argv
    tables, files, problems = check()
    problems += swift_problems(tables, write)
    for problem in problems:
        print(problem)
    keys = len(tables["en"])
    if problems:
        print(f"{len(problems)} problem(s) in {len(files)} files ({keys} keys in en).")
        return 1
    print(f"OK: {len(files)} languages, {keys} keys each, formats agree, Strings.swift matches"
          f"{' (rewritten)' if write else ''}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
