"""Generate documentation indexes, never simulation output or acceptance.

Reads installed declarations without importing the dashboard/server. Optional
run inspection reads only bounded CSV headers and one record; it is not an
arithmetic, population, hash-lineage or final-publication audit.
"""
from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[3]
GUIDE = Path(__file__).resolve().parent
LIMIT = 256 * 1024


def literals(node, env):
    if isinstance(node, ast.Name):
        return env[node.id]
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, (ast.List, ast.Tuple)):
        return [literals(v, env) for v in node.elts]
    if isinstance(node, ast.Dict):
        return {literals(k, env): literals(v, env) for k, v in zip(node.keys, node.values)}
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return literals(node.left, env) + literals(node.right, env)
    raise ValueError("Not a literal declaration")


def declarations(text):
    tree, env = ast.parse(text), {}
    for node in tree.body:
        name = (node.target.id if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name)
                else node.targets[0].id if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)
                else None)
        if name:
            try:
                env[name] = literals(node.value, env)
            except (KeyError, ValueError, TypeError):
                pass
    for node in ast.walk(tree):
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "procedure_preview_paths":
            env[node.target.id] = literals(node.value, env)
    return env


def module(relative):
    spec = importlib.util.spec_from_file_location(Path(relative).stem, ROOT / relative)
    obj = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(ROOT / "apps"))
    try:
        spec.loader.exec_module(obj)
    finally:
        sys.path.pop(0)
    return obj


def entry(kind, name, title, paths=(), fields=(), details=None, source=""):
    return dict(kind=kind, id=name, title=title, paths_json=json.dumps(paths),
                fields_json=json.dumps(fields), details_json=json.dumps(details or {}),
                source=source)


def installed_entries():
    dashboard = "apps/lls_web_dashboard.py"
    text = (ROOT / dashboard).read_text(encoding="utf-8")
    env = declarations(text)
    rows = []
    owners = env["CANONICAL_RUNTIME_ARTIFACT_OWNERS"]
    for key, spec in owners.items():
        fields = (env["CONTROL_TRIAL_PREVIEW_COLUMNS"].get(key)
                  or env["DATA_TRIAL_PREVIEW_COLUMNS"].get(key) or [])
        if key in env["DATA_TRIAL_PREVIEW_COLUMNS"]:
            fields = fields + env["RX_RF_MEASUREMENT_PREVIEW_COLUMNS"]
        rows.append(entry("runtime_csv", key, key.replace("_", " "),
                          [spec["canonical_path"]], fields, spec, dashboard))
    for key, paths in env["procedure_preview_paths"].items():
        rows.append(entry("procedure_csv", key, key.replace("_", " "), paths,
                          env["PROCEDURE_PREVIEW_COLUMNS"].get(key, []),
                          {"path_order": "canonical then documented aliases; not interchangeable populations"},
                          dashboard))
    # Actual UI table titles and visible column order, not inferred raw columns.
    for match in re.finditer(r"\{id:'([^']+)', title:'([^']+)', columns:(\[[^\n]+?\]), rows:", text):
        columns = ast.literal_eval(match.group(3))
        rows.append(entry("dashboard_panel", match.group(1), match.group(2), fields=columns,
                          details={"schema_role": "display labels; raw mappings in runtime/procedure entries"},
                          source=dashboard))
    contract = module("apps/lls_output_contract.py")
    aliases = module("apps/lls_contract_aliases.py")
    for kind in ("reports", "analytics"):
        for spec in contract.iter_table_specs(kind):
            rows.append(entry("declared_table", f'{kind}:{spec["table_name"]}', spec["table_name"],
                              [spec["logical_path"]], spec["required_columns"], spec,
                              "apps/lls_output_contract.py"))
        for spec in contract.iter_chart_specs(kind):
            slug = re.sub(r"[^a-z0-9]+", "-", spec["chart_name"].lower()).strip("-")
            path = f'{kind}/csv/contract__{spec["section_slug"]}__{slug}.csv'
            info = dict(spec, aliases=aliases.CONTRACT_CHART_ALIAS_PATHS.get(spec["chart_name"], []))
            rows.append(entry("declared_chart", f'{kind}:{spec["section_slug"]}:{slug}',
                              spec["chart_name"], [path], details=info,
                              source="apps/lls_output_contract.py"))
    radio = module("apps/lls_radio_measurement_plots.py")
    for name in radio.CHARTS:
        stem = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        rows.append(entry("live_chart", name, name, radio.CHART_SOURCES[name],
                          details={"plotted_csv": f"csv/{stem}.csv", "png": f"image/{stem}.png",
                                   "base": "reports/live_measurements/<snapshot>/",
                                   "publication": "conditional on measured source rows; partial, not terminal qualification"},
                          source="scripts/publish_lls_live_csv_plots.py"))
    # The other five live charts have specialized materializers; source choice
    # is resolved there and must not be guessed from a chart name here.
    pub = (ROOT / "scripts/publish_lls_live_csv_plots.py").read_text(encoding="utf-8")
    extra = ast.literal_eval(re.search(r"CHARTS = radio.CHARTS \+ (\([\s\S]+?\))\n", pub).group(1))
    for name in extra:
        stem = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        rows.append(entry("live_chart", name, name, details={
            "plotted_csv": f"csv/{stem}.csv", "png": f"image/{stem}.png",
            "base": "reports/live_measurements/<snapshot>/",
            "source_resolution": "specialized materializer; inspect source_table_logical_path and snapshot manifest",
            "publication": "conditional; never substitute a different receiver plane"},
            source="apps/lls_contract_materializer.py"))
    visual = "simulator/configs/schema/visual_artifact_contract.json"
    for spec in json.loads((ROOT / visual).read_text())["contracts"]:
        rows.append(entry("visual_contract", spec["plot_id"], spec["plot_id"],
                          [spec["source_csv"], spec["file_path"]], spec["required_columns"], spec, visual))
    return rows


def inspect_header(path):
    before = path.stat()
    with path.open("rb") as stream:
        payload = stream.read(LIMIT)
    text = payload.decode("utf-8-sig", errors="strict")
    # A bounded read ending mid-record must not be called a complete record.
    complete = before.st_size <= LIMIT
    if not complete:
        text = text[:text.rfind("\n") + 1]
    parsed = csv.reader(io.StringIO(text), strict=True)
    header = next(parsed, [])
    first = next(parsed, None)
    after = path.stat()
    return header, {"size_bytes": before.st_size,
                    "first_record_seen": first is not None,
                    "first_record_matches_header_width": first is not None and len(first) == len(header),
                    "changed_during_read": (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns),
                    "inspection": "bounded header/first-record presence only; values, populations and lineage not audited"}


def observed_entries(run_root):
    rows = []
    for base, dirs, files in os.walk(run_root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not (Path(base) / d).is_symlink())
        for name in sorted(files):
            path = Path(base) / name
            if path.suffix.lower() not in (".csv", ".png") or path.is_symlink():
                continue
            logical = path.relative_to(run_root).as_posix()
            details, fields = {"inspection": "file presence only; no pixel or lineage audit"}, []
            try:
                if path.suffix.lower() == ".csv":
                    fields, details = inspect_header(path)
                else:
                    details["size_bytes"] = path.stat().st_size
            except (OSError, UnicodeError, csv.Error) as exc:
                details = {"inspection": "inspection_error_not_acceptance", "error": str(exc)}
            rows.append(entry("observed_file", logical, logical, [logical], fields, details))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-folder", type=Path)
    args = parser.parse_args()
    rows = installed_entries()
    if args.run_folder:
        run_root = args.run_folder.resolve(strict=True)
        rows += observed_entries(run_root)
    sources = ["apps/lls_web_dashboard.py", "apps/lls_output_contract.py",
               "apps/lls_contract_aliases.py", "apps/lls_radio_measurement_plots.py",
               "apps/lls_contract_materializer.py", "scripts/publish_lls_live_csv_plots.py",
               "simulator/configs/schema/visual_artifact_contract.json"]
    meta = dict(scope="documentation_inventory_not_measurement_or_acceptance",
                created_utc=datetime.now(timezone.utc).isoformat(),
                run_folder=str(args.run_folder) if args.run_folder else None,
                source_sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources})
    rows.insert(0, entry("inventory", "scope", "Documentation inventory", details=meta))
    # Generated documentation only: fixed output location, never a run folder.
    with (GUIDE / "evidence-catalog.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({"documentation_entries": len(rows), "scope": meta["scope"],
                      "counts": {k: sum(r["kind"] == k for r in rows) for k in sorted({r["kind"] for r in rows})}}))


if __name__ == "__main__":
    main()
