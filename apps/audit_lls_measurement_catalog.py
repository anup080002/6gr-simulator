"""Audit requested output coverage, never certify physics from artifact presence.

The output is an audit table, not primary measurement data. Existing files are
read only; no missing measurement is filled, inferred, plotted or marked zero.
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def audit(catalog: Path, mapping: Path, run: Path) -> list[dict]:
    if not run.is_dir():
        raise ValueError(f"Run folder does not exist: {run}")
    with catalog.open(encoding="utf-8-sig", newline="") as stream:
        records = list(csv.DictReader(stream, delimiter="\t"))
    rules = {}
    for group in json.loads(mapping.read_text(encoding="utf-8-sig"))["groups"]:
        for metric in group["metrics"]:
            if metric in rules:
                raise ValueError(f"Duplicate mapping for {metric}")
            rules[metric] = group
    files = {}
    for path in run.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".csv", ".png"}:
            files.setdefault(path.name, []).append(path)
    cache = {}

    def describe(path):
        if path not in cache:
            if not path.is_file():
                cache[path] = {"rows": 0, "columns": [], "state": "missing"}
            else:
                try:
                    with path.open(encoding="utf-8-sig", newline="") as stream:
                        reader = csv.DictReader(stream)
                        columns = reader.fieldnames or []
                        count = sum(1 for _ in reader)
                    cache[path] = {"rows": count, "columns": columns,
                                   "state": "nonempty" if count else "empty"}
                except (UnicodeError, csv.Error) as exc:
                    cache[path] = {"rows": 0, "columns": [], "state": f"unreadable: {exc}"}
        return {"path": path.relative_to(run).as_posix(), **cache[path]}

    rows, seen = [], set()
    for record in records:
        record_id = record["Record ID"]
        if not record_id or record_id in seen:
            raise ValueError(f"Missing/duplicate record identity: {record_id}")
        seen.add(record_id)
        group = rules.get(record["Standard abbreviation or field name"], {})
        candidates = [describe(run / name) for name in group.get("sources", [])]
        named = [describe(p) for p in files.get(record["Supporting CSV file name"], [])]
        pngs = files.get(record["Expected PNG file name"], [])
        required = [f.strip() for f in record["Proposed raw CSV fields - not 3GPP field names"].split(";") if f.strip()]
        for table in named:
            table["missing_proposed_fields"] = sorted(set(required) - set(table["columns"]))
        has_candidate = any(t["rows"] > 0 for t in candidates)
        status = "named_export_present_unverified" if any(t["rows"] > 0 for t in named) else (
            "candidate_evidence_requires_mapping" if has_candidate else "requested_evidence_not_established")
        rows.append({"RecordID": record_id, "Agenda": record["Agenda item"],
            "Measurement": record["Measurement or parameter name in English"],
            "StandardStatusAsSupplied": record["3GPP status and applicability"],
            "DefinitionAsSupplied": record["Definition or calculation"],
            "CoverageStatus": status, "ScientificValidation": "not_verified_by_presence_audit",
            "Applicability": "requires_scenario_and_agenda_review",
            "RequestedCSV": record["Supporting CSV file name"],
            "RequestedPNG": record["Expected PNG file name"],
            "NamedCSVDetailsJSON": json.dumps(named),
            "NamedPNGPathsJSON": json.dumps([p.relative_to(run).as_posix() for p in pngs]),
            "CandidateEvidenceJSON": json.dumps(candidates),
            "ProducerFiles": "|".join(group.get("producers", [])),
            "RequiredCheck": group.get("check", "Bind common metadata to actual run/config/seeds and statistical populations; filename presence is insufficient."),
            "RunFolder": str(run.resolve())})
    return rows


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("output", type=Path, help="New audit CSV outside retained run evidence")
    parser.add_argument("--catalog", type=Path, default=root / "simulator/configs/validation/lls_evaluation_measurements.tsv")
    parser.add_argument("--mapping", type=Path, default=root / "simulator/configs/validation/lls_evaluation_evidence_map.json")
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(args.run.resolve()):
        parser.error("Write the audit outside the retained run; do not modify its evidence.")
    rows = audit(args.catalog, args.mapping, args.run)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({"records": len(rows), "output": str(args.output),
        "scientifically_certified_records": 0, "scope": "coverage audit only"}))


if __name__ == "__main__":
    main()
