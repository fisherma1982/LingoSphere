#!/usr/bin/env python3
"""Build LingoSphere's lazy-load English dictionary shards from CC-CEDICT.

Output: <output>/NNN.tsv (word<TAB>gloss, bucketed by the first code point
modulo --buckets) plus metadata.json. The app reads the shards from
SharedSupport/candidate_translator/dictionary.

CC-CEDICT stores one record per reading, and proper-noun readings (capitalised
pinyin: place names, countries, surnames) usually come first. All records of
a headword are therefore merged before ordering, so that everyday meanings are
shown ahead of proper nouns and cross-reference notes.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ENTRY_PATTERN = re.compile(r"^(\S+)\s+(\S+)\s+\[([^]]*)]\s+/(.*)/$")
PINYIN_PATTERN = re.compile(r"\[[^]]*]")
# 比如縣|比如县 → 比如县 (keep the simplified form of a cross-reference)
TRAD_SIMP_PATTERN = re.compile(r"[^\s|/;,()\[\]]+\|([^\s|/;,()\[\]]+)")
CLASSIFIER_PATTERN = re.compile(r"\s*\(?CL:[^)]*\)?")
# "(Taiwan pr. [zhao1])" and similar pronunciation remarks inside a sense
PRONUNCIATION_REMARK_PATTERN = re.compile(r"\s*\((?:Taiwan|also) pr\.[^)]*\)")
# "unofficial variant of", "Japanese variant of", "erroneous variant of", …
VARIANT_PATTERN = re.compile(r"^(?:[\w-]+ )*variant of ")

# Notes that describe a character instead of translating it. They are kept
# only when a headword has nothing better.
LOW_VALUE_PREFIXES = (
    "see ",
    "see also ",
    "same as ",
    "variant of ",
    "old variant of ",
    "archaic variant of ",
    "euphemistic variant of ",
    "erhua variant of ",
    "erhua form of ",
    "japanese variant of ",
    "abbr. for ",
    "abbr. of ",
    "surname ",
    "used in ",
    "taiwan pr.",
    "also pr.",
    "also written ",
    "classifier for ",
    "cl:",
)

# Ranks: everyday senses, then proper-noun senses, then notes.
RANK_COMMON = 0
RANK_PROPER = 1
RANK_NOTE = 2


@dataclass
class Sense:
    text: str
    rank: int
    order: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--overrides", type=Path)
    parser.add_argument("--buckets", type=int, default=128)
    parser.add_argument("--max-senses", type=int, default=3)
    parser.add_argument("--max-gloss-chars", type=int, default=72)
    return parser.parse_args()


def open_text(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8-sig", errors="replace")
    return path.open("r", encoding="utf-8-sig", errors="replace")


def clean_sense(value: str) -> str:
    value = value.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    value = CLASSIFIER_PATTERN.sub("", value)
    value = PRONUNCIATION_REMARK_PATTERN.sub("", value)
    value = TRAD_SIMP_PATTERN.sub(r"\1", value)
    value = PINYIN_PATTERN.sub("", value)
    # "(Taiwan pr. in some compounds …)" style remarks left empty by the above
    value = re.sub(r"\(\s*\)", "", value)
    value = re.sub(r"\s+([,;)])", r"\1", value)
    value = re.sub(r"\s+", " ", value).strip(" ;,")
    return value


def is_note(value: str) -> bool:
    lowered = value.lower().lstrip("(")
    return bool(VARIANT_PATTERN.match(lowered)) or any(
        lowered.startswith(prefix) for prefix in LOW_VALUE_PREFIXES
    )


def is_proper_reading(pinyin: str) -> bool:
    return any(syllable[:1].isupper() for syllable in pinyin.split())


def read_cedict(path: Path) -> tuple[dict[str, list[Sense]], int, int]:
    entries: dict[str, list[Sense]] = {}
    parsed = 0
    skipped = 0
    order = 0
    with open_text(path) as source:
        for raw_line in source:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            match = ENTRY_PATTERN.match(line)
            if not match:
                skipped += 1
                continue
            traditional, simplified, pinyin, definitions = match.groups()
            reading_rank = RANK_PROPER if is_proper_reading(pinyin) else RANK_COMMON
            senses = []
            for item in definitions.split("/"):
                text = clean_sense(item)
                if not text:
                    continue
                rank = RANK_NOTE if is_note(text) else reading_rank
                senses.append(Sense(text, rank, order))
                order += 1
            for word in {simplified, traditional}:
                entries.setdefault(word, []).extend(senses)
            parsed += 1
    return entries, parsed, skipped


def ordered_senses(senses: list[Sense]) -> list[str]:
    best_rank = min(sense.rank for sense in senses)
    # Notes are only useful when nothing else describes the word.
    usable = [s for s in senses if s.rank != RANK_NOTE or best_rank == RANK_NOTE]
    usable.sort(key=lambda s: (s.rank, s.order))
    result: list[str] = []
    for sense in usable:
        if sense.text not in result:
            result.append(sense.text)
    return result


def read_overrides(path: Path | None) -> dict[str, str]:
    if not path:
        return {}
    overrides: dict[str, str] = {}
    with path.open("r", encoding="utf-8") as source:
        for line_number, raw_line in enumerate(source, start=1):
            line = raw_line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            if "\t" not in line:
                raise ValueError(f"Invalid override at {path}:{line_number}")
            word, gloss = line.split("\t", 1)
            overrides[word] = clean_sense(gloss)
    return overrides


def compact_gloss(senses: list[str], max_senses: int, max_chars: int) -> str:
    selected: list[str] = []
    for sense in senses:
        if len(selected) >= max_senses:
            break
        proposed = "; ".join([*selected, sense])
        if len(proposed) <= max_chars:
            selected.append(sense)
        elif not selected:
            selected.append(sense[: max(1, max_chars - 1)].rstrip() + "…")
            break
    return "; ".join(selected)


def source_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build(args: argparse.Namespace) -> dict[str, object]:
    if args.buckets <= 0 or args.buckets > 999:
        raise ValueError("--buckets must be between 1 and 999")

    entries, parsed, skipped = read_cedict(args.input)
    overrides = read_overrides(args.overrides)
    compacted: dict[str, str] = {}
    for word, senses in entries.items():
        gloss = compact_gloss(ordered_senses(senses), args.max_senses, args.max_gloss_chars)
        if gloss:
            compacted[word] = gloss
    compacted.update(overrides)

    output = args.output
    staging = output.with_name(output.name + ".staging")
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    buckets: list[list[tuple[str, str]]] = [[] for _ in range(args.buckets)]
    for word, gloss in compacted.items():
        buckets[ord(word[0]) % args.buckets].append((word, gloss))

    for index, bucket in enumerate(buckets):
        bucket.sort(key=lambda item: item[0])
        destination = staging / f"{index:03d}.tsv"
        with destination.open("w", encoding="utf-8", newline="\n") as target:
            for word, gloss in bucket:
                target.write(f"{word}\t{gloss}\n")

    metadata: dict[str, object] = {
        "format": 2,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "CC-CEDICT",
        "source_url": "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz",
        "source_sha256": source_sha256(args.input),
        "license": "CC BY-SA 4.0",
        "parsed_source_entries": parsed,
        "skipped_source_lines": skipped,
        "output_headwords": len(compacted),
        "override_headwords": len(overrides),
        "bucket_count": args.buckets,
    }
    (staging / "metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if output.exists():
        shutil.rmtree(output)
    staging.rename(output)
    return metadata


def main() -> None:
    print(json.dumps(build(parse_args()), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
