#!/usr/bin/env python3
"""Inventory existing simulator CSV/PNG outputs before PUSCH remediation."""
from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path

from PIL import Image, ImageStat


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_csv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repository_root", type=Path)
    ap.add_argument("--output-dir", type=Path, required=True)
    args = ap.parse_args()
    root = args.repository_root.resolve()
    out = args.output_dir.resolve()

    csv_rows: list[dict[str, object]] = []
    for path in sorted(root.rglob("*.csv")):
        rel = path.relative_to(root).as_posix()
        status = "PASS"
        error = ""
        nrows = 0
        ncols = 0
        headers = ""
        try:
            with path.open(newline="", encoding="utf-8-sig", errors="strict") as f:
                reader = csv.reader(f)
                header = next(reader, [])
                ncols = len(header)
                headers = "|".join(header)
                for row in reader:
                    if row:
                        nrows += 1
                    if len(row) != ncols:
                        status = "FAIL"
                        error = f"nonrectangular_row_{nrows+1}_columns_{len(row)}_expected_{ncols}"
                        break
        except Exception as exc:
            status = "FAIL"
            error = f"{type(exc).__name__}:{exc}"
        csv_rows.append({
            "RelativePath": rel,
            "FileName": path.name,
            "Bytes": path.stat().st_size,
            "Rows": nrows,
            "Columns": ncols,
            "Header": headers,
            "PUSCHRelatedName": int(any(t in rel.lower() for t in ("pusch", "ulsch", "uplink"))),
            "SHA256": sha256(path),
            "Status": status,
            "Error": error,
        })

    image_rows: list[dict[str, object]] = []
    for path in sorted(root.rglob("*.png")):
        rel = path.relative_to(root).as_posix()
        status = "PASS"
        error = ""
        width = height = bands = 0
        variance = 0.0
        extrema = ""
        nonblank = 0
        try:
            with Image.open(path) as im:
                im.load()
                width, height = im.size
                bands = len(im.getbands())
                stat = ImageStat.Stat(im.convert("RGB"))
                variance = float(sum(stat.var))
                extrema = "|".join(f"{a}:{b}" for a, b in stat.extrema)
                nonblank = int(width > 0 and height > 0 and variance > 1e-8)
                if not nonblank:
                    status = "FAIL"
                    error = "blank_or_constant_image"
        except Exception as exc:
            status = "FAIL"
            error = f"{type(exc).__name__}:{exc}"
        image_rows.append({
            "RelativePath": rel,
            "FileName": path.name,
            "Bytes": path.stat().st_size,
            "Width": width,
            "Height": height,
            "Bands": bands,
            "PixelVarianceSum": variance,
            "Extrema": extrema,
            "PUSCHRelatedName": int(any(t in rel.lower() for t in ("pusch", "ulsch", "uplink"))),
            "StructurallyNonblank": nonblank,
            "SHA256": sha256(path),
            "Status": status,
            "Error": error,
        })

    csv_contract = list(csv.DictReader((out / "desired_pusch_csv_contract.csv").open(newline="", encoding="utf-8")))
    img_contract = list(csv.DictReader((out / "desired_pusch_image_contract.csv").open(newline="", encoding="utf-8")))
    all_files: dict[str, list[Path]] = {}
    for path in root.rglob("*"):
        if path.is_file():
            all_files.setdefault(path.name, []).append(path)
    presence_rows: list[dict[str, object]] = []
    for kind, rows, key in (("CSV", csv_contract, "FileName"), ("PNG", img_contract, "ImageFile")):
        for contract in rows:
            name = contract[key]
            matches = all_files.get(name, [])
            presence_rows.append({
                "ArtifactType": kind,
                "RequiredFile": name,
                "PresentCount": len(matches),
                "Present": int(bool(matches)),
                "MatchingPaths": "|".join(p.relative_to(root).as_posix() for p in matches),
                "Status": "PASS" if matches else "MISSING",
            })

    write_csv(out / "existing_pusch_csv_inventory.csv", csv_rows,
              ["RelativePath", "FileName", "Bytes", "Rows", "Columns", "Header", "PUSCHRelatedName", "SHA256", "Status", "Error"])
    write_csv(out / "existing_pusch_image_integrity_audit.csv", image_rows,
              ["RelativePath", "FileName", "Bytes", "Width", "Height", "Bands", "PixelVarianceSum", "Extrema", "PUSCHRelatedName", "StructurallyNonblank", "SHA256", "Status", "Error"])
    write_csv(out / "existing_pusch_artifact_presence_audit.csv", presence_rows,
              ["ArtifactType", "RequiredFile", "PresentCount", "Present", "MatchingPaths", "Status"])

    print(
        f"csv={len(csv_rows)} csv_fail={sum(r['Status']=='FAIL' for r in csv_rows)} "
        f"png={len(image_rows)} png_fail={sum(r['Status']=='FAIL' for r in image_rows)} "
        f"required={len(presence_rows)} required_present={sum(int(r['Present']) for r in presence_rows)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
