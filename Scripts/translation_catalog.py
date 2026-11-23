#!/usr/bin/env python3
"""Builds the page translation model catalog: every file of every model with its size and
SHA-256, so nobody types a checksum.

The files come from one of two places:

  --folder <dir>     a folder laid out like a model store, `<artifact>/<version>/<path>`:
                     each file is read and hashed. A model whose author hosts it may also
                     be given by itself with `--files <artifact>=<dir>`, the author's files
                     at their own relative paths.
  --manifest <file>  a Markdown manifest that already lists paths, sizes and checksums in
                     tables (`| artifact | version | path | size | sha256 | … |` for a store
                     and, under a heading naming the artifact, `| file | size | sha256 | … |`
                     for a model its author hosts).

What is not a checksum is written here, in ARTIFACTS: what each model does, whose it is,
its licence, what was changed, whether a copy may be passed on, how it is loaded, and where
its author offers it. The private store's address is never part of the catalog.

  python3 Scripts/translation_catalog.py --manifest MANIFEST.md --write
  python3 Scripts/translation_catalog.py --folder store/ --files mt-jmt-fast-1=jmt/dl --check
  python3 Scripts/translation_catalog.py --manifest MANIFEST.md --json
  python3 Scripts/translation_catalog.py --folder test-store/ --only det-v4s

`--write` replaces ModelCatalog+Generated.swift, `--check` exits 1 when that file is not what
would be written, `--json` prints the catalog as the app's `ModelCatalog` decodes it.
`--credits <dir>` also compares the credits written here with the CREDITS.md files of a
store folder, so a credit is never one thing in the app and another beside the model. With
none of them the Swift source goes to standard output. A table of every artifact with its
file count and size goes to standard error.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "Packages/EhKit/Sources/EhCore/PageTranslation/Store/ModelCatalog+Generated.swift"

APACHE = "https://www.apache.org/licenses/LICENSE-2.0.txt"
CC_BY_NC_SA = "https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode"
MIT = "https://opensource.org/license/mit"


def hugging_face(repository, commit):
    return f"https://huggingface.co/{repository}/resolve/{commit}"


def model_scope(repository):
    return f"https://www.modelscope.cn/models/{repository}/resolve/master"


# In the order choices fall back: of a kind, an earlier model is preferred when the chosen
# one cannot be had. `listed: False` keeps an artifact out of the catalog until it has been
# measured on the phone; `--include <id>` adds it.
#
# sharing: fromPublisher (downloaded where its author offers it), publicStore (the project
# may pass a copy on), privateOnly (it may not).
#
# A credit says what the CREDITS.md beside the model says, word for word: `--credits` checks
# it. nonCommercial is a licence's own term; a model whose card states no licence at all has
# it False and says so in "licence".
ARTIFACTS = [
    {
        "id": "det-k2xl-768", "version": "1", "role": "detector", "sharing": "privateOnly",
        "loading": {"coreML": "cpuAndNeuralEngine"},
        "credit": {
            "name": "KoharuLayout RF-DETR-Seg-2XL (768 px)", "author": "mayocream",
            "source": "https://huggingface.co/mayocream/koharu-layout-rfdetr-seg-2xl-1152",
            "licence": '"other" (no licence stated for the weights; RF-DETR software Apache-2.0; '
                       "training images under Manga109's academic-use terms)",
            "licenceText": "https://huggingface.co/mayocream/koharu-layout-rfdetr-seg-2xl-1152",
            "changes": "Converted to Core ML with 16-bit floats at 768 x 768 (the author's model is 1152 px); "
                       "one layer rewritten for the conversion.",
            "nonCommercial": False,
        },
    },
    {
        "id": "det-yolo26s", "version": "1", "role": "detector", "sharing": "privateOnly",
        "loading": {"coreML": "cpuAndNeuralEngine"},
        "credit": {
            "name": "Koharu YOLO26s",
            "author": "mayocream (weights); Liiesl (the ONNX export that was converted)",
            "source": "https://huggingface.co/mayocream/koharu-yolo26s",
            "licence": 'Weights: "other" (mayocream\'s card). The ONNX export that was converted: '
                       "AGPL-3.0 (Liiesl's card).",
            "licenceText": "https://huggingface.co/mayocream/koharu-yolo26s",
            "changes": "Converted from Liiesl's ONNX export to Core ML, 16-bit floats.",
            "nonCommercial": False,
        },
    },
    {
        "id": "det-v4s", "version": "1", "role": "detector", "sharing": "publicStore",
        "loading": {"coreML": "cpuOnly"},
        "credit": {
            "name": "comic-text-and-bubble-detector, detector-v4-s", "author": "ogkalu",
            "source": "https://huggingface.co/ogkalu/comic-text-and-bubble-detector",
            "licence": "Apache-2.0", "licenceText": APACHE,
            "changes": "The published 8-bit (int8) detector was rebuilt as floats and converted to Core ML, "
                       "16-bit floats.",
            "nonCommercial": False,
        },
    },
    {
        "id": "det-rtmdet2", "version": "1", "role": "detector", "sharing": "publicStore",
        "loading": {"coreML": "cpuAndNeuralEngine"},
        "credit": {
            "name": "RTMDet manga layout (1024 px)", "author": "fumetodev",
            "source": "https://huggingface.co/fumetodev/rtmdet-manga-layout-onnx",
            "licence": "Apache-2.0 (the card is only the licence header)", "licenceText": APACHE,
            "changes": "Converted from the ONNX file to Core ML, 16-bit floats, with one block rewritten for "
                       "the conversion.",
            "nonCommercial": False,
        },
    },
    {
        "id": "ocr-cpt2", "version": "1", "role": "reader", "sharing": "publicStore",
        "loading": {"coreML": "cpuAndNeuralEngine"},
        "credit": {
            "name": "manga-ocr-base-CPT (v2)", "author": "muscgab",
            "source": "https://huggingface.co/muscgab/manga-ocr-base-CPT",
            "licence": "CC BY-NC-SA 4.0", "licenceText": CC_BY_NC_SA,
            "changes": "Converted to Core ML: an encoder and a one-step decoder, 16-bit floats; the vocabulary "
                       "is supplied as vocab.txt.",
            "nonCommercial": True,
        },
    },
    {
        "id": "ocr-nar-small", "version": "1", "role": "reader", "sharing": "fromPublisher",
        "loading": {"coreML": "cpuAndNeuralEngine"},
        "publisher": [
            hugging_face("muscgab/manga-ocr-nar-small", "81ff4f3313263d1da349946a9dd20d14e0fb0e66"),
            model_scope("muscgab/manga-ocr-nar-small"),
        ],
        "credit": {
            "name": "manga-ocr-nar-small", "author": "muscgab",
            "source": "https://huggingface.co/muscgab/manga-ocr-nar-small",
            "licence": "CC BY-NC-SA 4.0", "licenceText": CC_BY_NC_SA, "changes": None, "nonCommercial": True,
        },
    },
    {
        "id": "mt-jmt-fast-1", "version": "1", "role": "translator", "sharing": "fromPublisher",
        "loading": {"coreML": "cpuAndNeuralEngine"},
        "publisher": [
            hugging_face("muscgab/JMangaTranslator-Fast", "151cebac786f262a9144fc109ac5341a94c3da12"),
            model_scope("muscgab/JMangaTranslator-Fast"),
        ],
        "credit": {
            "name": "JMangaTranslator-Fast v1", "author": "muscgab",
            "source": "https://huggingface.co/muscgab/JMangaTranslator-Fast",
            "licence": "CC BY-NC-SA 4.0", "licenceText": CC_BY_NC_SA, "changes": None, "nonCommercial": True,
        },
    },
    {
        "id": "mt-galtransl-v4-4b", "version": "1", "role": "translator", "sharing": "publicStore",
        "loading": {"languageModel": "galtransl"}, "listed": False,
        "credit": {
            "name": "GalTransl-v4-4B-2601", "author": "SakuraLLM",
            "source": "https://huggingface.co/SakuraLLM/GalTransl-v4-4B-2601",
            "licence": "CC BY-NC-SA 4.0 (SakuraLLM adds that no commercial use of any kind is allowed)",
            "licenceText": CC_BY_NC_SA,
            "changes": "Re-quantized by this project from the author's official 3.31 GB GGUF file to Q4_K_M "
                       "(Galtransl-v4-4B-2601-Q4_K_M-requant.gguf).",
            "nonCommercial": True,
        },
    },
    {
        # The judged file is a third party's quantization whose repository states no
        # licence. We pass nothing on: the app downloads it where the third party offers it,
        # which serves the same bytes (size and SHA-256 compared on 2026-11-22).
        "id": "mt-sakura-1.5b", "version": "1", "role": "translator", "sharing": "fromPublisher",
        "loading": {"languageModel": "sakura"}, "listed": False,
        "publisher": [
            hugging_face("shing3232/Sakura-1.5B-Qwen2.5-v1.0-GGUF-IMX", "6b704808673c735e326dfa25fe6fe62ac6ebc401"),
        ],
        "credit": {
            "name": "Sakura-1.5B-Qwen2.5-v1.0 (Q5_K_S quantization)",
            "author": "SakuraLLM (model); shing3232 (this quantized file)",
            "source": "https://huggingface.co/shing3232/Sakura-1.5B-Qwen2.5-v1.0-GGUF-IMX",
            "licence": "CC BY-NC-SA 4.0 (SakuraLLM's official repository); the third party's repository "
                       "states no licence",
            "licenceText": CC_BY_NC_SA, "changes": None, "nonCommercial": True,
        },
    },
    {
        "id": "mt-hy-mt2-1.8b", "version": "1", "role": "translator", "sharing": "fromPublisher",
        "loading": {"languageModel": "hymt2"}, "listed": False,
        "publisher": [
            hugging_face("tencent/Hy-MT2-1.8B-GGUF", "a0c709d9fac510f2c807aa3af52872340dc37a4a"),
            model_scope("Tencent-Hunyuan/Hy-MT2-1.8B-GGUF"),
        ],
        "credit": {
            "name": "Hy-MT2 1.8B (GGUF)", "author": "Tencent",
            "source": "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF",
            "licence": "Apache-2.0", "licenceText": APACHE, "changes": None, "nonCommercial": False,
        },
    },
    {
        "id": "mt-qwen3.5-4b", "version": "1", "role": "translator", "sharing": "fromPublisher",
        "loading": {"languageModel": "qwen35"}, "listed": False,
        "publisher": [
            hugging_face("unsloth/Qwen3.5-4B-GGUF", "e87f176479d0855a907a41277aca2f8ee7a09523"),
            model_scope("unsloth/Qwen3.5-4B-GGUF"),
        ],
        "credit": {
            "name": "Qwen3.5 4B (IQ4_XS GGUF)", "author": "Alibaba (model); unsloth (quantization)",
            "source": "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF",
            "licence": "Apache-2.0", "licenceText": APACHE, "changes": None, "nonCommercial": False,
        },
    },
    {
        "id": "inp-lama-manga", "version": "1", "role": "repaint", "sharing": "publicStore",
        "loading": {"coreML": "cpuAndGPU"},
        "credit": {
            "name": "lama_large_512px (LaMa fine-tuned on manga and anime)",
            "author": "dreMaz; LaMa by Suvorov et al. (Samsung Research)",
            "source": "https://huggingface.co/dreMaz/AnimeMangaInpainting",
            "licence": "MIT (this fine-tune); Apache-2.0 (LaMa)", "licenceText": MIT,
            "changes": "Converted to Core ML, 16-bit floats, 512 x 512.", "nonCommercial": False,
        },
    },
    {
        "id": "inp-big-lama", "version": "1", "role": "repaint", "sharing": "publicStore",
        "loading": {"coreML": "cpuAndGPU"},
        "credit": {
            "name": "LaMa big-lama",
            "author": "Roman Suvorov, Elizaveta Logacheva, Anton Mashikhin, Anastasia Remizova, Arsenii Ashukha, "
                      "Aleksei Silvestrov, Naejin Kong, Harshith Goka, Kiwoong Park, Victor Lempitsky "
                      "(Samsung Research)",
            "source": "https://github.com/advimman/lama",
            "licence": "Apache-2.0", "licenceText": APACHE,
            "changes": "Converted to Core ML, 32-bit floats, 512 x 512, from the TorchScript export of big-lama "
                       "used by lama-cleaner.",
            "nonCommercial": False,
        },
    },
]

KNOWN = {artifact["id"] for artifact in ARTIFACTS}
SHA = re.compile(r"^[0-9a-f]{64}$")
# Files a folder holds that are not part of a model.
IGNORED = {".DS_Store", ".gitattributes", "README.md"}


def fail(message):
    sys.exit(f"translation_catalog: {message}")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while block := handle.read(1 << 20):
            digest.update(block)
    return digest.hexdigest()


def files_under(folder):
    """Every model file under `folder` as (relative path, size, sha256), sorted by path."""
    found = []
    for path in sorted(folder.rglob("*")):
        if path.is_file() and path.name not in IGNORED and ".git" not in path.relative_to(folder).parts[:-1]:
            found.append((path.relative_to(folder).as_posix(), path.stat().st_size, sha256(path)))
    return found


def read_folder(folder):
    """`<artifact>/<version>/<path>` → {artifact: (version, files)}."""
    found = {}
    for artifact in sorted(p for p in folder.iterdir() if p.is_dir() and p.name in KNOWN):
        versions = sorted(p for p in artifact.iterdir() if p.is_dir())
        if len(versions) != 1:
            fail(f"{artifact} must hold exactly one version folder, found {len(versions)}")
        found[artifact.name] = (versions[0].name, files_under(versions[0]))
    return found


def cells(line):
    return [cell.strip().strip("`") for cell in line.strip().strip("|").split("|")]


def read_manifest(path):
    """The two kinds of table described at the top → {artifact: (version or None, files)}.

    A model its author hosts takes its files from the table under its heading alone: a
    store may still hold a copy, with a LICENSE and a CREDITS.md the author does not have."""
    found = {}
    hosted = {artifact["id"] for artifact in ARTIFACTS if artifact["sharing"] == "fromPublisher"}
    heading = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            name = line.lstrip("#").strip().strip("`")
            heading = name if name in KNOWN else None
            continue
        if not line.startswith("|"):
            continue
        row = cells(line)
        if len(row) >= 5 and row[0] in KNOWN and SHA.match(row[4]):
            if row[0] in hosted:
                continue
            artifact, version, full = row[0], row[1], row[2]
            prefix = f"{artifact}/{version}/"
            if not full.startswith(prefix):
                continue  # a note about the artifact, kept outside its folder
            entry = found.setdefault(artifact, (version, []))
            if entry[0] != version:
                fail(f"{artifact} is listed with two versions")
            entry[1].append((full[len(prefix):], int(row[3].replace(",", "")), row[4]))
        elif heading and len(row) >= 3 and SHA.match(row[2]):
            found.setdefault(heading, (None, []))[1].append((row[0], int(row[1].replace(",", "")), row[2]))
    return found


def ordered(files):
    """Model files in their given order, then the licence and the credits."""
    last = {"LICENSE": 1, "CREDITS.md": 2}
    return sorted(files, key=lambda item: last.get(item[0], 0))


def build(sources, include, only, catalog_version):
    artifacts = []
    for spec in ARTIFACTS:
        if only and spec["id"] not in only:
            continue
        if not spec.get("listed", True) and spec["id"] not in include | only:
            continue
        if spec["id"] not in sources:
            fail(f"no files were given for {spec['id']}")
        version, files = sources[spec["id"]]
        if version not in (None, spec["version"]):
            fail(f"{spec['id']} is version {version} in the files and {spec['version']} here")
        if not files:
            fail(f"{spec['id']} has no files")
        paths = [path for path, _, _ in files]
        if len(set(paths)) != len(paths):
            fail(f"{spec['id']} lists a file twice")
        for path, size, digest in files:
            if size <= 0 or not SHA.match(digest) or path.startswith("/") or ".." in path.split("/"):
                fail(f"{spec['id']}: bad entry {path!r}")
        if spec["sharing"] != "fromPublisher" and not {"LICENSE", "CREDITS.md"} <= set(paths):
            fail(f"{spec['id']} needs a LICENSE and a CREDITS.md beside its files")
        if (spec["sharing"] == "fromPublisher") != bool(spec.get("publisher")):
            fail(f"{spec['id']}: only a model its author hosts has publisher addresses")
        artifacts.append({**spec, "files": ordered(files)})
    return {"version": catalog_version, "artifacts": artifacts}


CREDIT_LINE = re.compile(r"^- \*\*(.+?):\*\*\s*(.*)$")


def read_credits(path):
    """A CREDITS.md: a heading with the model's name, then `- **Key:** value` lines."""
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# ") and "name" not in fields:
            fields["name"] = line[2:].strip()
        elif match := CREDIT_LINE.match(line):
            fields[match.group(1)] = match.group(2).strip()
    return fields


def check_credits(folder, catalog):
    """Compares each credit of the catalog with the CREDITS.md its store folder holds."""
    problems = []
    checked = 0
    for artifact in catalog["artifacts"]:
        path = folder / artifact["id"] / artifact["version"] / "CREDITS.md"
        if not path.exists():
            continue
        checked += 1
        told, credit = read_credits(path), artifact["credit"]
        source = (told.get("Source") or "").split()
        unchanged = (told.get("Changed by this project") or "").lower().startswith("none")
        pairs = [
            ("name", credit["name"], told.get("name")),
            ("author", credit["author"], told.get("Author")),
            ("source", credit["source"], source[0] if source else None),
            ("licence", credit["licence"], told.get("Licence")),
            ("changes", credit["changes"], None if unchanged else told.get("Changed by this project")),
            ("nonCommercial", credit["nonCommercial"],
             (told.get("Non-commercial use only") or "").lower().startswith("yes")),
        ]
        for field, here, there in pairs:
            if here != there:
                problems.append(f"{artifact['id']}: {field} is {here!r} here and {there!r} in CREDITS.md")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        fail(f"{len(problems)} credit(s) differ from the CREDITS.md files in {folder}")
    print(f"the credits of {checked} artifact(s) are what their CREDITS.md say", file=sys.stderr)


def swift_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def swift_loading(loading):
    if "coreML" in loading:
        return f".coreML(.{loading['coreML']})"
    return f".languageModel(promptFamily: {swift_string(loading['languageModel'])})"


def swift(catalog):
    lines = [
        "// Generated by Scripts/translation_catalog.py. Do not edit: run the script again.",
        "",
        "import EhModels",
        "import Foundation",
        "",
        "extension ModelCatalog {",
        "    /// The models this build knows, with the size and SHA-256 of every file.",
        "    public static let generated = ModelCatalog(",
        f"        version: {catalog['version']},",
        "        artifacts: [",
    ]
    for index, artifact in enumerate(catalog["artifacts"]):
        credit = artifact["credit"]
        changes = swift_string(credit["changes"]) if credit["changes"] else "nil"
        lines += [
            "            ModelArtifact(",
            f"                id: ModelArtifactID({swift_string(artifact['id'])}), "
            f"version: {swift_string(artifact['version'])},",
            f"                role: .{artifact['role']}, sharing: .{artifact['sharing']},",
            "                credit: ArtifactCredit(",
            f"                    name: {swift_string(credit['name'])},",
            f"                    author: {swift_string(credit['author'])},",
            f"                    source: .catalog({swift_string(credit['source'])}),",
            f"                    licence: {swift_string(credit['licence'])},",
            f"                    licenceText: .catalog({swift_string(credit['licenceText'])}),",
            f"                    changes: {changes},",
            f"                    nonCommercial: {'true' if credit['nonCommercial'] else 'false'}",
            "                ),",
            f"                loading: {swift_loading(artifact['loading'])},",
        ]
        if artifact.get("publisher"):
            lines.append("                publisherAddresses: [")
            lines += [f"                    .catalog({swift_string(address)})," for address in artifact["publisher"]]
            lines[-1] = lines[-1].rstrip(",")
            lines.append("                ],")
        lines.append("                files: [")
        for path, size, digest in artifact["files"]:
            lines += [
                "                    ModelFile(",
                f"                        {swift_string(path)},",
                f"                        {size:_}, {swift_string(digest)}",
                "                    ),",
            ]
        lines[-1] = lines[-1].rstrip(",")
        lines.append("                ]")
        lines.append("            )" + ("," if index + 1 < len(catalog["artifacts"]) else ""))
    lines += ["        ]", "    )", "}", ""]
    return "\n".join(lines)


def codable(catalog):
    """The catalog as `JSONDecoder` reads the app's `ModelCatalog`."""
    def loading(value):
        if "coreML" in value:
            return {"coreML": {"_0": value["coreML"]}}
        return {"languageModel": {"promptFamily": value["languageModel"]}}

    return {
        "version": catalog["version"],
        "artifacts": [
            {
                "id": artifact["id"], "version": artifact["version"], "role": artifact["role"],
                "sharing": artifact["sharing"],
                "credit": {key: value for key, value in artifact["credit"].items() if value is not None},
                "loading": loading(artifact["loading"]),
                "publisherAddresses": artifact.get("publisher", []),
                "files": [{"path": path, "size": size, "sha256": digest} for path, size, digest in artifact["files"]],
            }
            for artifact in catalog["artifacts"]
        ],
    }


def table(catalog):
    rows = ["artifact                files          bytes  sharing"]
    total = 0
    for artifact in catalog["artifacts"]:
        size = sum(size for _, size, _ in artifact["files"])
        total += size
        rows.append(f"{artifact['id']:<22} {len(artifact['files']):>6} {size:>14,}  {artifact['sharing']}")
    rows.append(f"{'total':<22} {sum(len(a['files']) for a in catalog['artifacts']):>6} {total:>14,}")
    return "\n".join(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--folder", type=Path, help="a folder laid out like a model store")
    parser.add_argument("--files", action="append", default=[], metavar="ARTIFACT=DIR",
                        help="the files of one artifact its author hosts")
    parser.add_argument("--manifest", type=Path, help="a Markdown manifest with sizes and checksums")
    parser.add_argument("--include", action="append", default=[], metavar="ARTIFACT",
                        help="also list an artifact that is not listed yet")
    parser.add_argument("--only", action="append", default=[], metavar="ARTIFACT",
                        help="list these artifacts and no others: a small catalog for trying a store out")
    parser.add_argument("--credits", type=Path, metavar="DIR",
                        help="a folder laid out like a model store: fail when a credit here is not what "
                             "the CREDITS.md there says")
    parser.add_argument("--catalog-version", type=int, default=1)
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--write", action="store_true", help=f"replace {SWIFT.relative_to(ROOT)}")
    output.add_argument("--check", action="store_true", help="exit 1 when that file is out of date")
    output.add_argument("--json", action="store_true", help="print the catalog as JSON")
    arguments = parser.parse_args()

    if not (arguments.folder or arguments.manifest or arguments.files):
        parser.error("give --folder, --files or --manifest")
    for artifact in arguments.include + arguments.only:
        if artifact not in KNOWN:
            fail(f"{artifact}: no such artifact")

    sources = {}
    if arguments.manifest:
        sources.update(read_manifest(arguments.manifest))
    if arguments.folder:
        sources.update(read_folder(arguments.folder))
    for pair in arguments.files:
        artifact, _, folder = pair.partition("=")
        if artifact not in KNOWN or not folder:
            fail(f"--files {pair}: expected <artifact>=<folder>")
        sources[artifact] = (None, files_under(Path(folder)))

    catalog = build(sources, set(arguments.include), set(arguments.only), arguments.catalog_version)
    print(table(catalog), file=sys.stderr)
    if arguments.credits:
        check_credits(arguments.credits, catalog)
    source = swift(catalog)
    if arguments.json:
        print(json.dumps(codable(catalog), indent=2, ensure_ascii=False))
    elif arguments.write:
        SWIFT.write_text(source, encoding="utf-8")
        print(f"wrote {SWIFT.relative_to(ROOT)}", file=sys.stderr)
    elif arguments.check:
        if not SWIFT.exists() or SWIFT.read_text(encoding="utf-8") != source:
            fail(f"{SWIFT.relative_to(ROOT)} is not what these files give; run with --write")
        print("the catalog is up to date", file=sys.stderr)
    else:
        print(source, end="")


if __name__ == "__main__":
    main()
