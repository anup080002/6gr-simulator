from __future__ import annotations

import csv
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_output_contract as contract  # noqa: E402


DOC_TARGETS = {
    "REPORTS_COMPLETE_OUTPUT_SPEC.md": ("reports", "Complete Reports Output Spec"),
    "ANALYTICS_COMPLETE_OUTPUT_SPEC.md": ("analytics", "Complete Analytics Output Spec"),
    "POWER_ENERGY_OUTPUT_SPEC.md": ("power_energy", "Power / Energy Output Spec"),
    "SCHEDULER_MAC_PHY_OUTPUT_SPEC.md": ("scheduler_mac_phy", "Scheduler / MAC / PHY Output Spec"),
    "UE_GNB_AIR_INTERFACE_OUTPUT_SPEC.md": ("ue_gnb_air", "UE / gNB / Air Interface Output Spec"),
}

REFERENCE_SMOKE_RUN_ROOT = REPO_ROOT / "results" / "lls" / "lls_report_bundle" / "smoke"
REFERENCE_SMOKE_DIR = REFERENCE_SMOKE_RUN_ROOT / "reports" / "csv"
REFERENCE_SMOKE_REGISTRY = REFERENCE_SMOKE_DIR / "output_coverage_registry.csv"

DOMAIN_RUNTIME_HINTS = {
    "run_overview": {"ui_sections": ("coverage", "scenario_topology"), "block_modules": ("coverage_registry", "scenario_runtime")},
    "geometry": {"ui_sections": ("scenario_topology",), "block_modules": ("scenario_runtime", "geometry_runtime")},
    "mobility": {"ui_sections": ("timing",), "block_modules": ("system_ue_summary", "timing_runtime", "cross_layer_runtime")},
    "air_interface": {"ui_sections": ("dl", "ul", "timing"), "block_modules": ("air_interface_runtime", "grid_runtime", "timing_runtime", "dl_trials", "ul_trials")},
    "scheduler_mac": {"ui_sections": ("scheduler", "phy_metrics", "latency"), "block_modules": ("system_scheduler", "scheduler_cqi", "packet_latency")},
    "harq": {"ui_sections": ("harq",), "block_modules": ("system_harq",)},
    "control_phy": {"ui_sections": ("control",), "block_modules": ("control_runtime",)},
    "pdsch": {"ui_sections": ("dl",), "block_modules": ("dl_trials", "grid_runtime", "air_interface_runtime")},
    "pusch": {"ui_sections": ("ul",), "block_modules": ("ul_trials", "grid_runtime", "air_interface_runtime")},
    "pucch": {"ui_sections": ("control",), "block_modules": ("control_runtime",)},
    "prach": {"ui_sections": ("control",), "block_modules": ("control_runtime",)},
    "srs": {"ui_sections": ("control",), "block_modules": ("control_runtime", "channel_runtime")},
    "channel": {"ui_sections": ("channel",), "block_modules": ("channel_runtime", "system_interference_detail")},
    "measurement": {"ui_sections": ("phy_metrics", "timing"), "block_modules": ("scheduler_cqi", "timing_runtime")},
    "beam_mimo": {"ui_sections": ("beam",), "block_modules": ("beam_runtime", "system_beam")},
    "ue_state": {"ui_sections": ("latency", "timing"), "block_modules": ("system_ue_summary", "packet_latency", "timing_runtime")},
    "gnb_state": {"ui_sections": ("cell_analytics", "scheduler"), "block_modules": ("system_cell_load", "system_scheduler")},
    "power_energy": {"ui_sections": ("energy", "timing", "latency"), "block_modules": ("rf_energy", "timing_runtime", "packet_latency")},
    "persistence": {"ui_sections": ("coverage", "dashboard"), "block_modules": ("coverage_registry",)},
    "investigator": {"ui_sections": ("root_cause", "coverage", "dashboard"), "block_modules": ("cross_layer_issue_registry", "cross_layer_runtime", "coverage_registry")},
    "waveform": {"ui_sections": (), "block_modules": ("air_interface_runtime", "grid_runtime")},
    "spectrum": {"ui_sections": ("energy",), "block_modules": ("air_interface_runtime", "rf_energy")},
    "constellation": {"ui_sections": (), "block_modules": ("air_interface_runtime",)},
    "resource_grid": {"ui_sections": (), "block_modules": ("grid_runtime",)},
    "control": {"ui_sections": ("control", "plots"), "block_modules": ("control_runtime",)},
    "reliability": {"ui_sections": ("dl", "ul", "harq"), "block_modules": ("dl_trials", "ul_trials", "system_harq")},
    "throughput": {"ui_sections": ("latency", "scheduler"), "block_modules": ("packet_latency", "system_scheduler")},
    "random_access": {"ui_sections": ("control",), "block_modules": ("control_runtime",)},
    "impairments": {"ui_sections": ("channel", "timing"), "block_modules": ("channel_runtime", "timing_runtime")},
    "runtime": {"ui_sections": ("timing", "coverage", "dashboard"), "block_modules": ("timing_runtime", "coverage_registry", "packet_latency")},
    "export_consistency": {"ui_sections": ("coverage", "dashboard"), "block_modules": ("coverage_registry",)},
    "regression": {"ui_sections": ("compare",), "block_modules": ("compare_runtime",)},
    "optional_6g": {"ui_sections": (), "block_modules": ()},
}


def _as_text(value: object) -> str:
    if isinstance(value, (list, tuple)):
        return ";".join(str(item) for item in value)
    if isinstance(value, bool):
        return "true" if value else "false"
    return "" if value is None else str(value)


def _write_csv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: _as_text(row.get(field, "")) for field in fields})


def _read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _trim_join(values: list[str], limit: int = 5) -> str:
    trimmed = [value for value in values if value][:limit]
    return ";".join(trimmed)


def _reference_runtime_rows(domain: str, registry_rows: list[dict[str, str]]) -> list[dict[str, str]]:
    hints = DOMAIN_RUNTIME_HINTS.get(domain, {})
    ui_sections = set(hints.get("ui_sections", ()))
    block_modules = set(hints.get("block_modules", ()))
    matched: list[dict[str, str]] = []
    for row in registry_rows:
        if row.get("ui_section", "") in ui_sections or row.get("block_module", "") in block_modules:
            matched.append(row)
    return matched


def _reference_runtime_summary(domain: str, registry_rows: list[dict[str, str]]) -> dict[str, object]:
    matched = _reference_runtime_rows(domain, registry_rows)
    implemented = [row for row in matched if row.get("current_status", "") == "implemented"]
    partial = [row for row in matched if row.get("current_status", "") == "partial"]
    unavailable = [row for row in matched if row.get("current_status", "") == "unavailable"]
    blocked = [row for row in matched if row.get("current_status", "") == "blocked"]
    if implemented:
        runtime_status = "runtime_evidence_present_noncanonical"
    elif partial:
        runtime_status = "runtime_partial_evidence_present_noncanonical"
    elif unavailable or blocked:
        runtime_status = "runtime_backlog_confirmed_by_reference_smoke"
    else:
        runtime_status = "no_reference_runtime_evidence"
    example_outputs = _trim_join([str(row.get("output_name", "")) for row in implemented or partial or unavailable or blocked])
    example_artifacts = _trim_join([str(row.get("source_artifact_ref", "")) for row in implemented or partial or unavailable or blocked])
    if runtime_status in {"runtime_evidence_present_noncanonical", "runtime_partial_evidence_present_noncanonical"}:
        gap_classification = "canonical_live_table_or_view_missing_but_runtime_evidence_present"
    elif runtime_status == "runtime_backlog_confirmed_by_reference_smoke":
        gap_classification = "schema_backlog_confirmed_by_reference_smoke"
    else:
        gap_classification = "schema_only_backlog"
    return {
        "reference_smoke_match_count": len(matched),
        "reference_smoke_implemented_count": len(implemented),
        "reference_smoke_partial_count": len(partial),
        "reference_smoke_unavailable_count": len(unavailable),
        "reference_smoke_blocked_count": len(blocked),
        "reference_smoke_runtime_status": runtime_status,
        "reference_smoke_output_examples": example_outputs,
        "reference_smoke_artifact_examples": example_artifacts,
        "canonical_gap_classification": gap_classification,
    }


def _canonical_artifact_present(logical_path: str) -> bool:
    logical = str(logical_path or "").strip()
    if not logical:
        return False
    return (REFERENCE_SMOKE_RUN_ROOT / logical).is_file()


def _augment_row_with_reference_runtime(row: dict[str, object], registry_rows: list[dict[str, str]]) -> dict[str, object]:
    logical_path = str(row.get("logical_path", "") or "")
    if _canonical_artifact_present(logical_path):
        return {
            **row,
            "reference_smoke_runtime_status": "canonical_artifact_present",
            "reference_smoke_match_count": 1,
            "reference_smoke_implemented_count": 1,
            "reference_smoke_partial_count": 0,
            "reference_smoke_unavailable_count": 0,
            "reference_smoke_blocked_count": 0,
            "reference_smoke_output_examples": str(row.get("name", "")),
            "reference_smoke_artifact_examples": logical_path,
            "canonical_gap_classification": "canonical_artifact_present_in_reference_smoke",
        }
    domain = str(row.get("domain", ""))
    return {**row, **_reference_runtime_summary(domain, registry_rows)}


def _augment_with_reference_runtime(rows: list[dict[str, object]], registry_rows: list[dict[str, str]]) -> list[dict[str, object]]:
    return [_augment_row_with_reference_runtime(row, registry_rows) for row in rows]


def _gap_rows(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    return [
        row
        for row in rows
        if "unavailable_until" in str(row.get("default_status", ""))
        and str(row.get("reference_smoke_runtime_status", "")) != "canonical_artifact_present"
    ]


def _build_reference_reconciliation(rows: list[dict[str, object]], registry_rows: list[dict[str, str]]) -> list[dict[str, object]]:
    grouped: dict[tuple[str, str], list[dict[str, object]]] = {}
    for row in rows:
        grouped.setdefault((str(row["kind"]), str(row["section_slug"])), []).append(row)
    summary_rows: list[dict[str, object]] = []
    for (kind, section_slug), section_rows in grouped.items():
        first = section_rows[0]
        domain = str(first["domain"])
        runtime = _reference_runtime_summary(domain, registry_rows)
        summary_rows.append({
            "kind": kind,
            "section_slug": section_slug,
            "section_title": first["section_title"],
            "domain": domain,
            "contract_table_count": sum(1 for row in section_rows if row["record_kind"] == "table"),
            "contract_chart_count": sum(1 for row in section_rows if row["record_kind"] == "chart"),
            "contract_gap_row_count": sum(1 for row in section_rows if "unavailable_until" in str(row.get("default_status", ""))),
            **runtime,
        })
    return summary_rows


def table_rows(kind: str) -> list[dict[str, object]]:
    rows = []
    for row in contract.iter_table_specs(kind):
        rows.append({
            **row,
            "record_kind": "table",
            "name": row["table_name"],
            "required_columns": row["required_columns"],
            "mandatory_context_columns": row["mandatory_context_columns"],
            "lineage": "required",
            "chart_lineage": "",
            "formula": "runtime truth fact table" if kind == "reports" else "derived from canonical reports fact tables and artifact manifests",
            "metric_unit": "table_defined",
            "valid_sample_count_required": kind == "analytics",
            "missing_sample_count_required": kind == "analytics",
        })
    for row in contract.iter_chart_specs(kind):
        rows.append({
            **row,
            "record_kind": "chart",
            "name": row["chart_name"],
            "required_columns": "",
            "mandatory_context_columns": "",
            "lineage": "required",
            "chart_lineage": "artifact_id required when generated",
            "formula": "render only from real DB/artifact rows",
            "metric_unit": "source_defined",
            "valid_sample_count_required": kind == "analytics",
            "missing_sample_count_required": kind == "analytics",
            "mysql_view_name": "",
            "logical_path": "",
        })
    return rows


def _section_rows(kind: str) -> list[dict[str, object]]:
    return table_rows(kind)


def _filter(rows: list[dict[str, object]], mode: str) -> list[dict[str, object]]:
    if mode in {"reports", "analytics"}:
        return rows
    if mode == "power_energy":
        return [row for row in rows if "power" in str(row.get("domain", "")).lower() or "energy" in str(row.get("section_title", "")).lower()]
    if mode == "scheduler_mac_phy":
        keys = ("scheduler", "mac", "phy", "pdsch", "pusch", "pucch", "prach", "pdcch", "pbch", "csirs", "srs", "harq", "beam", "mimo")
        return [row for row in rows if any(key in " ".join([str(row.get("domain", "")), str(row.get("section_slug", "")), str(row.get("section_title", "")), str(row.get("name", ""))]).lower() for key in keys)]
    if mode == "ue_gnb_air":
        keys = ("ue", "gnb", "air", "geometry", "topology", "mobility", "channel", "interference", "cell")
        return [row for row in rows if any(key in " ".join([str(row.get("domain", "")), str(row.get("section_slug", "")), str(row.get("section_title", "")), str(row.get("name", ""))]).lower() for key in keys)]
    return rows


def write_docs() -> None:
    docs = REPO_ROOT / "docs"
    all_rows = table_rows("reports") + table_rows("analytics")
    for filename, (mode, title) in DOC_TARGETS.items():
        rows = _filter(table_rows(mode) if mode in {"reports", "analytics"} else all_rows, mode)
        lines = [
            f"# {title}",
            "",
            "This document is additive-only. It does not declare that historical tables, CSVs, artifacts, browser pages, or plots should be deleted.",
            "",
            "Runtime truth lives under `/reports`; derived study views live under `/analytics`. Missing outputs stay unavailable until a canonical DB row or artifact exists.",
            "",
            "All major fact tables require the base context columns and value semantics from `apps/lls_output_contract.py`.",
            "",
            "## Value Semantics",
            "",
            f"- value_role values: {', '.join(contract.VALUE_ROLES)}",
            f"- value_status values: {', '.join(contract.VALUE_STATUSES)}",
            "- configured/resolved/applied/measured/derived values must keep explicit `value_source` and `value_definition` lineage.",
            "- charts are never generated from smoke rows or placeholders by default.",
            "",
            "## Sections",
            "",
        ]
        current = None
        for row in rows:
            if row["section_slug"] != current:
                current = row["section_slug"]
                lines.extend(["", f"### {row['section_title']}", "", f"- Route: `/{row['kind']}/{row['section_slug']}`"])
            if row["record_kind"] == "table":
                lines.append(f"- Table `{row['name']}`: route `{row['route']}`, view `{row['mysql_view_name']}`, default status `{row['default_status']}`.")
            else:
                lines.append(f"- Chart `{row['name']}`: route `{row['route']}`, status `{row['default_status']}`.")
        (docs / filename).write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def write_reports() -> None:
    reports = REPO_ROOT / "reports"
    fields = [
        "kind",
        "section_slug",
        "section_title",
        "domain",
        "record_kind",
        "name",
        "route",
        "mysql_view_name",
        "logical_path",
        "required_columns",
        "mandatory_context_columns",
        "lineage",
        "formula",
        "metric_unit",
        "valid_sample_count_required",
        "missing_sample_count_required",
        "default_status",
        "smoke_visible_default",
        "placeholder_flag_default",
        "fallback_flag_default",
        "reference_smoke_runtime_status",
        "reference_smoke_match_count",
        "reference_smoke_implemented_count",
        "reference_smoke_partial_count",
        "reference_smoke_unavailable_count",
        "reference_smoke_blocked_count",
        "reference_smoke_output_examples",
        "reference_smoke_artifact_examples",
        "canonical_gap_classification",
    ]
    registry_rows = _read_csv(REFERENCE_SMOKE_REGISTRY)
    reports_rows = _augment_with_reference_runtime(table_rows("reports"), registry_rows)
    analytics_rows = _augment_with_reference_runtime(table_rows("analytics"), registry_rows)
    all_rows = reports_rows + analytics_rows
    _write_csv(reports / "60_reports_complete_output_matrix.csv", reports_rows, fields)
    _write_csv(reports / "61_analytics_complete_output_matrix.csv", analytics_rows, fields)
    _write_csv(reports / "62_missing_outputs_gap_list.csv", _gap_rows(all_rows), fields)
    _write_csv(reports / "63_power_energy_gap_list.csv", _gap_rows(_filter(all_rows, "power_energy")), fields)
    _write_csv(reports / "64_scheduler_mac_phy_gap_list.csv", _gap_rows(_filter(all_rows, "scheduler_mac_phy")), fields)
    _write_csv(reports / "65_ue_air_interface_gap_list.csv", _gap_rows(_filter(all_rows, "ue_gnb_air")), fields)
    route_rows = []
    for kind in ("reports", "analytics"):
        for route, page in contract.route_map(kind).items():
            route_rows.append({"route": route, "page": page, "kind": kind, "section_slug": route.split("/", 2)[2] if route.count("/") >= 2 else "", "artifact": "browser_route"})
        for row in contract.iter_table_specs(kind):
            route_rows.append({"route": row["route"], "page": kind, "kind": kind, "section_slug": row["section_slug"], "artifact": row["mysql_view_name"]})
        for row in contract.iter_chart_specs(kind):
            route_rows.append({"route": row["route"], "page": kind, "kind": kind, "section_slug": row["section_slug"], "artifact": row["chart_name"]})
    _write_csv(reports / "66_added_routes_views_tables.csv", route_rows, ["route", "page", "kind", "section_slug", "artifact"])
    reconciliation_fields = [
        "kind",
        "section_slug",
        "section_title",
        "domain",
        "contract_table_count",
        "contract_chart_count",
        "contract_gap_row_count",
        "reference_smoke_runtime_status",
        "reference_smoke_match_count",
        "reference_smoke_implemented_count",
        "reference_smoke_partial_count",
        "reference_smoke_unavailable_count",
        "reference_smoke_blocked_count",
        "reference_smoke_output_examples",
        "reference_smoke_artifact_examples",
        "canonical_gap_classification",
    ]
    _write_csv(reports / "68_contract_runtime_reconciliation.csv", _build_reference_reconciliation(all_rows, registry_rows), reconciliation_fields)


def _sql_quote(value: object) -> str:
    return "'" + str(value).replace("\\", "\\\\").replace("'", "''") + "'"


def write_sql() -> None:
    sql_dir = REPO_ROOT / "sql"
    sql_dir.mkdir(parents=True, exist_ok=True)
    lines = [
        "-- Additive LLS reports/analytics contract registry.",
        "-- This file uses CREATE TABLE IF NOT EXISTS and INSERT IGNORE. It does not drop or truncate historical data.",
        "CREATE TABLE IF NOT EXISTS lls_output_contract_registry (",
        "  contract_pk VARCHAR(255) NOT NULL PRIMARY KEY,",
        "  kind VARCHAR(32) NOT NULL,",
        "  section_slug VARCHAR(255) NOT NULL,",
        "  section_title VARCHAR(255) NOT NULL,",
        "  record_kind VARCHAR(32) NOT NULL,",
        "  output_name VARCHAR(255) NOT NULL,",
        "  route VARCHAR(1024) NOT NULL,",
        "  mysql_view_name VARCHAR(255) NULL,",
        "  logical_path VARCHAR(1024) NULL,",
        "  required_columns_json LONGTEXT NULL,",
        "  default_status VARCHAR(128) NOT NULL,",
        "  lineage_required TINYINT NOT NULL DEFAULT 1,",
        "  placeholder_allowed TINYINT NOT NULL DEFAULT 0,",
        "  smoke_visible_default TINYINT NOT NULL DEFAULT 0",
        ");",
        "",
    ]
    for kind in ("reports", "analytics"):
        for row in contract.iter_table_specs(kind):
            pk = f"{kind}:table:{row['table_name']}"
            values = [
                pk,
                kind,
                row["section_slug"],
                row["section_title"],
                "table",
                row["table_name"],
                row["route"],
                row["mysql_view_name"],
                row["logical_path"],
                json.dumps(row["required_columns"], separators=(",", ":")),
                row["default_status"],
            ]
            lines.append("INSERT IGNORE INTO lls_output_contract_registry (contract_pk, kind, section_slug, section_title, record_kind, output_name, route, mysql_view_name, logical_path, required_columns_json, default_status) VALUES (" + ", ".join(_sql_quote(value) for value in values) + ");")
        for row in contract.iter_chart_specs(kind):
            pk = f"{kind}:chart:{row['section_slug']}:{row['chart_name']}"
            values = [pk, kind, row["section_slug"], row["section_title"], "chart", row["chart_name"], row["route"], "", "", "", row["default_status"]]
            lines.append("INSERT IGNORE INTO lls_output_contract_registry (contract_pk, kind, section_slug, section_title, record_kind, output_name, route, mysql_view_name, logical_path, required_columns_json, default_status) VALUES (" + ", ".join(_sql_quote(value) for value in values) + ");")
        for section in (contract.REPORT_SECTIONS if kind == "reports" else contract.ANALYTICS_SECTIONS):
            view_name = f"{kind}_{section['slug'].replace('-', '_')}_v"
            view_sql = f"CREATE VIEW {view_name} AS SELECT * FROM lls_output_contract_registry WHERE kind={_sql_quote(kind)} AND section_slug={_sql_quote(section['slug'])}"
            lines.extend([
                "",
                f"SET @sixgr_view_name = {_sql_quote(view_name)};",
                f"SET @sixgr_view_sql = {_sql_quote(view_sql)};",
                "SET @sixgr_view_exists = (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = DATABASE() AND table_name = @sixgr_view_name);",
                "SET @sixgr_sql = IF(@sixgr_view_exists = 0, @sixgr_view_sql, CONCAT('SELECT ''preserved existing view ', @sixgr_view_name, ''' AS status'));",
                "PREPARE sixgr_stmt FROM @sixgr_sql;",
                "EXECUTE sixgr_stmt;",
                "DEALLOCATE PREPARE sixgr_stmt;",
            ])
    (sql_dir / "lls_complete_output_contract_views.sql").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    write_docs()
    write_reports()
    write_sql()


if __name__ == "__main__":
    main()
