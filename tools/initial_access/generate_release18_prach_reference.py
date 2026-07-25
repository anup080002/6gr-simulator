#!/usr/bin/env python3
"""Extract TS 38.211 V18.8.0 FR1 PRACH tables from official DOCX markdown.

The input markdown must be produced from the official 38211-i80.docx with:
  pandoc 38211-i80.docx -t gfm --wrap=none -o 38211-i80.md

This generator is intentionally independent of MATLAB and 5G Toolbox.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import pandas as pd


SPEC = "3GPP TS 38.211 V18.8.0"
ARCHIVE_SHA256 = "e58b15d46f41f33913aefe3730f0d7dfe2d6a390a57a4bb2cdd214de3d023f09"
DOCUMENT_SHA256 = "74f598d09da32ead4a139269f4b7857a99736e0f516f315e4cb3dbd0afd9b3e2"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def number_set(value: object) -> str:
    text = str(value).strip()
    if text.endswith(".0"):
        text = text[:-2]
    # pandas converts the official HTML cell
    # "0,1,2,3,4,5,6,7,8,9" to integer 123456789 and thereby discards its
    # leading zero.  TS 38.211 has no "1..9 only" cell in these two tables,
    # so restore the exact source set before serializing the catalog.
    if text == "123456789":
        return "0|1|2|3|4|5|6|7|8|9"
    digits = [character for character in text if character.isdigit()]
    return "|".join(digits)


def scalar_or_nan(value: object) -> float:
    text = str(value).strip()
    if text in {"-", "nan", "NaN"}:
        return float("nan")
    return float(text)


def convert(table: pd.DataFrame, source_table: str, duplex: str) -> pd.DataFrame:
    table = table.copy()
    table.columns = [
        "ConfigurationIndex",
        "PreambleFormat",
        "x",
        "y",
        "FrameOrSlotNumbers",
        "StartingSymbol",
        "PRACHSlotsPerReferenceUnit",
        "NumTimeOccasions",
        "PRACHDuration",
    ]
    rows = []
    for raw in table.to_dict("records"):
        rows.append(
            {
                "SourceTable": source_table,
                "DuplexContext": duplex,
                "ConfigurationIndex": int(raw["ConfigurationIndex"]),
                "PreambleFormat": str(raw["PreambleFormat"]),
                "x": int(raw["x"]),
                "y": int(raw["y"]),
                "FrameOrSlotNumbers": number_set(raw["FrameOrSlotNumbers"]),
                "StartingSymbol": int(raw["StartingSymbol"]),
                "PRACHSlotsPerReferenceUnit": scalar_or_nan(
                    raw["PRACHSlotsPerReferenceUnit"]
                ),
                "NumTimeOccasions": scalar_or_nan(raw["NumTimeOccasions"]),
                "PRACHDuration": int(raw["PRACHDuration"]),
                "Reserved": str(raw["PreambleFormat"]).strip() == "-",
                "SpecRelease": SPEC,
                "SourceArchiveSHA256": ARCHIVE_SHA256,
                "SourceDocumentSHA256": DOCUMENT_SHA256,
            }
        )
    return pd.DataFrame(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("markdown", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if digest(args.markdown) == "":
        raise RuntimeError("unreachable empty digest")
    tables = pd.read_html(args.markdown)
    paired = convert(
        tables[13],
        "TS_38_211_Table_6_3_3_2_2",
        "FR1_PAIRED_SUL",
    )
    unpaired = convert(
        tables[14],
        "TS_38_211_Table_6_3_3_2_3",
        "FR1_UNPAIRED",
    )
    if list(paired["ConfigurationIndex"]) != list(range(256)):
        raise RuntimeError("paired/SUL table is not exactly index 0..255")
    if list(unpaired["ConfigurationIndex"]) != list(range(263)):
        raise RuntimeError("unpaired table is not exactly index 0..262")
    output = pd.concat([paired, unpaired], ignore_index=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output, index=False, lineterminator="\n")
    print(
        f"wrote {len(output)} rows to {args.output}; "
        f"sha256={digest(args.output)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
