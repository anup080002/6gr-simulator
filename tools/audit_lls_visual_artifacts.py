#!/usr/bin/env python3
"""Post-run LLS visual artifact truth audit.

This tool is intentionally stdlib-only so CI can run it without MATLAB.
It audits rendered visual artifacts after a run has completed and writes:

  reports/csv/visual_artifact_audit.csv
  reports/visual_artifact_audit.md

Exit code is non-zero when strict visual truth rules fail.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


# HTML files are reports, not raster visual artifacts.  Auditing them as
# unmanifested plots creates false visual-gate failures even though the
# strict visual contract applies only to PNG/JPEG (and rejects legacy SVG).
VISUAL_EXTENSIONS = {".png", ".jpg", ".jpeg", ".svg"}
SUPPRESSED_STATUSES = {
    "suppressed",
    "source_csv_missing",
    "not_rendered",
    "invalid_stale_artifact",
}
FORBIDDEN_TRUTH_TOKENS = (
    "proxy",
    "fallback",
    "synthetic",
    "fast_proxy",
    "lut",
    "logistic",
    "configured_sinr",
    "reference_sinr",
    "anchor_sinr",
    "configured_cqi",
    "reference_cqi",
    "unavailable",
    "placeholder",
)
STRONG_FORBIDDEN_TRUTH_TOKENS = tuple(
    token for token in FORBIDDEN_TRUTH_TOKENS if token != "unavailable"
)
PLOT_SCOPED_STATUS_SUFFIXES = (
    "status",
    "valuestatus",
    "truthstatus",
    "availability",
    "available",
    "source",
    "valuesource",
    "role",
    "valuerole",
    "nareason",
    "reason",
)
CURVE_COLUMNS = (
    "CurveConstruction",
    "curve_construction",
    "CurveConstructionMode",
    "curve_construction_mode",
    "CurveConstructionSource",
    "curve_construction_source",
    "ChartConstruction",
    "chart_construction",
    "AggregationMethod",
    "aggregation_method",
    "SourceCurveConstruction",
    "source_curve_construction",
    "SeriesConstruction",
    "series_construction",
)
TRUTH_COLUMNS = (
    "VisualTruthStatus",
    "TruthStatus",
    "RuntimeEvidenceStatus",
    "RuntimeMaterializationStatus",
    "truth_status",
    "runtime_evidence_status",
    "Source",
    "SourceType",
    "SourceKind",
    "ValueRole",
    "SINRValueRole",
    "ReceiverHestSINRValueRole",
    "ApproximationMode",
    "approximation_mode",
    "ExecutionBackend",
    "execution_backend",
    "E2EAirModel",
    "Notes",
    "notes",
)
UNIT_COLUMNS = (
    "unit",
    "units",
    "Unit",
    "Units",
    "x_unit",
    "y_unit",
    "z_unit",
    "value_unit",
    "MetricUnit",
    "metric_unit",
)
SOURCE_MAPPING_COLUMNS = ("source_mapping_status", "SourceMappingStatus")
CHART_MODE_COLUMNS = ("chart_mode", "ChartMode", "mode", "Mode")
UNSAFE_GENERIC_FAMILIES = ("heatmap", "map", "timeline")
LOW_INFORMATION_VISUAL_MARKERS = (
    "visual_gate=",
    "would not support a defensible",
    "requires two independent axes",
    "every heatmap cell is zero",
)
UNAVAILABLE_VISUAL_SUFFIXES = ("_unavailable.png", "_unavailable.svg")


def is_unavailable_visual_path(path: str) -> bool:
    return str(path or "").strip().lower().endswith(UNAVAILABLE_VISUAL_SUFFIXES)


@dataclass
class FileInfo:
    rel_path: str
    exists: bool = False
    extension: str = ""
    declared_mime_type: str = ""
    actual_mime_type: str = "missing"
    sha256: str = ""
    byte_count: int = 0
    signature_status: str = "missing_file"
    signature_ok: bool = False
    contains_low_information_explanation: bool = False


@dataclass
class SourceStats:
    source_exists: bool = False
    row_count: int = 0
    unique_x_count: int = 0
    unique_y_count: int = 0
    non_nan_y_count: int = 0
    nan_only_y: bool = False
    mixed_units: bool = False
    units: list[str] = field(default_factory=list)
    curve_construction: list[str] = field(default_factory=list)
    truth_tokens: list[str] = field(default_factory=list)
    plot_truth_tokens: list[str] = field(default_factory=list)
    source_mapping_status: list[str] = field(default_factory=list)
    chart_modes: list[str] = field(default_factory=list)
    chart_names: list[str] = field(default_factory=list)
    x_missing: bool = False
    y_missing: bool = False
    low_information_reason: str = ""
    low_information_details: list[str] = field(default_factory=list)


@dataclass
class AuditRow:
    plot_id: str
    artifact_path: str
    artifact_kind: str
    is_manifest_row: bool
    manifest_status: str
    visual_validity: str
    source_csv: str
    x_column: str
    y_column: str
    plot_kind: str
    row_count: int | str
    unique_x_count: int | str
    unique_y_count: int | str
    non_nan_y_count: int | str
    nan_only_y: bool
    mixed_units: bool
    source_mapping_status: str
    curve_construction: str
    truth_status_tokens: str
    actual_mime_type: str
    declared_mime_type: str
    extension: str
    sha256: str
    byte_count: int
    audit_ok: bool
    failure_code: str
    failure_reason: str


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit LLS visual artifacts for truth/lineage defects.")
    parser.add_argument("run_folder", help="Completed LLS run folder")
    parser.add_argument("--non-strict", action="store_true", help="Always exit zero after writing audit artifacts")
    args = parser.parse_args(argv)

    run_folder = windows_extended_path(Path(args.run_folder).resolve())
    rows = audit_run_folder(run_folder)
    write_outputs(run_folder, rows)
    has_failures = any(not r.audit_ok for r in rows)
    return 0 if args.non_strict or not has_failures else 1


def windows_extended_path(path: Path) -> Path:
    """Use Win32 extended-length syntax for deeply nested result trees."""

    if os.name != "nt":
        return path
    text = str(path)
    if text.startswith("\\\\?\\"):
        return path
    if text.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + text.lstrip("\\"))
    return Path("\\\\?\\" + text)


def audit_run_folder(run_folder: Path) -> list[AuditRow]:
    rows: list[AuditRow] = []
    manifest_path = run_folder / "reports" / "csv" / "plot_manifest.csv"
    manifest_rows = read_csv_dicts(manifest_path)
    seen_visuals: set[str] = set()

    if not manifest_path.exists():
        rows.append(
            make_row(
                run_folder,
                plot_id="plot_manifest",
                artifact_path="reports/csv/plot_manifest.csv",
                artifact_kind="manifest",
                failure_code="plot_manifest_missing",
                failure_reason="plot_manifest.csv is required for post-run visual truth audit.",
            )
        )

    for manifest_row in manifest_rows:
        row = audit_manifest_row(run_folder, manifest_row)
        rows.append(row)
        if row.artifact_path:
            seen_visuals.add(normalize_rel_path(row.artifact_path))
        rows.extend(audit_stale_normal_siblings(run_folder, manifest_row))

    component_rows, component_visuals = audit_component_plot_lineages(
        run_folder, seen_visuals
    )
    rows.extend(component_rows)
    seen_visuals.update(component_visuals)

    mirror_rows, mirror_visuals = audit_component_image_mirrors(
        run_folder, seen_visuals
    )
    rows.extend(mirror_rows)
    seen_visuals.update(mirror_visuals)

    for visual_path in inventory_visual_files(run_folder):
        rel = relative_path(run_folder, visual_path)
        if normalize_rel_path(rel) in seen_visuals:
            continue
        rows.append(audit_unmanifested_visual(run_folder, rel))

    rows.extend(audit_contract_source_csvs(run_folder, manifest_rows))
    return rows


def audit_component_image_mirrors(
    run_folder: Path, lineaged_visuals: set[str]
) -> tuple[list[AuditRow], set[str]]:
    """Admit only byte-identical mirrors of an already-lineaged image.

    Component publication is a filesystem convenience view.  It does not
    create a second scientific plot and therefore must inherit the source
    CSV semantics of its canonical image.  The inheritance is valid only
    when the canonical image is already accepted by plot lineage and the
    publication manifest, canonical bytes, and mirror bytes all agree.
    """

    manifest_path = (
        run_folder
        / "reports"
        / "csv"
        / "component_artifact_publication_manifest.csv"
    )
    publication_rows = read_csv_dicts(manifest_path)
    rows: list[AuditRow] = []
    seen: set[str] = set()
    for index, publication in enumerate(publication_rows, start=1):
        if lower_token(get_field(publication, "ArtifactType")) != "image":
            continue
        canonical_rel = normalize_rel_path(
            get_field(publication, "CanonicalRelativePath")
        )
        published_rel = normalize_rel_path(
            get_field(publication, "PublishedRelativePath")
        )
        if not published_rel or published_rel in lineaged_visuals or published_rel in seen:
            continue

        failures: list[tuple[str, str]] = []
        if not safe_run_relative_path(canonical_rel) or not safe_run_relative_path(
            published_rel
        ):
            failures.append(
                (
                    "component_mirror_path_invalid",
                    "component publication paths must remain relative to the run folder",
                )
            )

        canonical_info = inspect_file(run_folder, canonical_rel)
        published_info = inspect_file(run_folder, published_rel)
        expected_canonical = lower_token(
            get_field(publication, "CanonicalSHA256")
        )
        expected_published = lower_token(
            get_field(publication, "PublishedSHA256")
        )
        publish_status = get_field(publication, "PublishStatus")

        if canonical_rel not in lineaged_visuals:
            failures.append(
                (
                    "component_mirror_source_not_lineaged",
                    "canonical image behind the component mirror has no accepted plot lineage",
                )
            )
        if not canonical_info.exists:
            failures.append(
                (
                    "component_mirror_source_missing",
                    "canonical image behind the component mirror is missing",
                )
            )
        if not published_info.exists:
            failures.append(
                ("visual_file_missing", "component mirror image file is missing")
            )
        elif not published_info.signature_ok:
            failures.append(
                (
                    published_info.signature_status or "visual_signature_invalid",
                    "component mirror extension and byte signature do not match",
                )
            )
        if published_info.extension == ".svg" or published_info.actual_mime_type == "image/svg+xml":
            failures.append(
                (
                    "vector_visual_format_forbidden",
                    "persisted component visuals must use PNG or JPEG",
                )
            )
        hashes_are_exact = (
            len(expected_canonical) == 64
            and len(expected_published) == 64
            and canonical_info.sha256.lower() == expected_canonical
            and published_info.sha256.lower() == expected_published
            and canonical_info.sha256.lower() == published_info.sha256.lower()
        )
        if (
            publish_status != "PUBLISHED_HASH_VERIFIED"
            or not parse_bool(get_field(publication, "MirrorOnly"))
            or not hashes_are_exact
        ):
            failures.append(
                (
                    "component_mirror_hash_mismatch",
                    "component mirror bytes do not exactly match the lineaged canonical image and publisher hashes",
                )
            )

        rows.append(
            make_row(
                run_folder,
                plot_id=f"component_mirror__{index}",
                artifact_path=published_rel,
                artifact_kind="component_mirror_plot",
                is_manifest_row=True,
                manifest_status=publish_status,
                visual_validity="byte_identical_lineaged_component_mirror",
                file_info=published_info,
                failures=failures,
            )
        )
        seen.add(published_rel)
    return rows, seen


def audit_component_plot_lineages(
    run_folder: Path, already_seen: set[str]
) -> tuple[list[AuditRow], set[str]]:
    """Audit component-owned raster lineage without treating it as run-root relative."""

    rows: list[AuditRow] = []
    seen: set[str] = set()
    for lineage_path in sorted(run_folder.rglob("*plot_lineage.csv")):
        for lineage_row in read_csv_dicts(lineage_path):
            image_spec = get_field(
                lineage_row, "ImagePath", "PlotFile", "ArtifactPath"
            )
            if not image_spec:
                continue
            image_path = resolve_owned_lineage_path(
                run_folder, lineage_path, image_spec
            )
            if image_path is None:
                image_rel = normalize_rel_path(image_spec)
            else:
                image_rel = relative_path(run_folder, image_path)
            normalized_image = normalize_rel_path(image_rel)
            if normalized_image in already_seen or normalized_image in seen:
                continue

            plot_id = get_field(lineage_row, "PlotId", "plot_id") or lineage_path.stem
            status = lower_token(
                get_field(lineage_row, "Status", "LineageStatus")
                or "not_evaluated"
            )
            explicitly_not_rendered = status in {
                "incomplete",
                "not_evaluated",
                "not_rendered",
                "suppressed",
            }
            file_info = inspect_file(run_folder, image_rel)
            source_spec = get_field(lineage_row, "SourceCSV", "source_csv")
            resolved_source_spec, source_exists, source_hash = (
                resolve_component_source_spec(
                    run_folder, lineage_path, source_spec
                )
            )
            source_stats = (
                inspect_source_csv(run_folder, resolved_source_spec, "", "")
                if resolved_source_spec
                else SourceStats()
            )
            failures: list[tuple[str, str]] = []

            if explicitly_not_rendered:
                if file_info.byte_count > 0:
                    failures.append(
                        (
                            "stale_suppressed_normal_artifact",
                            "component lineage says the plot was not rendered but image bytes exist",
                        )
                    )
            else:
                if not file_info.exists:
                    failures.append(
                        ("visual_file_missing", "component lineage image file is missing")
                    )
                elif not file_info.signature_ok:
                    failures.append(
                        (
                            file_info.signature_status or "visual_signature_invalid",
                            "component lineage image extension and byte signature do not match",
                        )
                    )
                if file_info.extension == ".svg" or file_info.actual_mime_type == "image/svg+xml":
                    failures.append(
                        (
                            "vector_visual_format_forbidden",
                            "persisted component visuals must use PNG or JPEG",
                        )
                    )
                if not source_spec:
                    failures.append(
                        (
                            "manifest_source_csv_missing",
                            "component plot lineage does not identify a source CSV",
                        )
                    )
                elif not source_exists:
                    failures.append(
                        (
                            "source_csv_missing",
                            "one or more component plot source CSV files are missing",
                        )
                    )
                expected_source_hash = lower_token(
                    get_field(lineage_row, "SourceCSV_SHA256")
                )
                if (
                    expected_source_hash
                    and source_exists
                    and source_hash.lower() != expected_source_hash
                ):
                    failures.append(
                        (
                            "component_plot_source_hash_mismatch",
                            "component source CSV bytes do not match the lineage hash",
                        )
                    )
                expected_image_hash = lower_token(
                    get_field(lineage_row, "ImageSHA256", "PNG_SHA256")
                )
                if (
                    expected_image_hash
                    and file_info.sha256.lower() != expected_image_hash
                ):
                    failures.append(
                        (
                            "component_plot_hash_mismatch",
                            "component image bytes do not match the lineage hash",
                        )
                    )
                if status not in {"pass", "complete", "rendered", "rendered_component_plot"}:
                    failures.append(
                        (
                            "component_plot_lineage_failed",
                            f"component plot lineage status is not successful: {status}",
                        )
                    )

            rows.append(
                make_row(
                    run_folder,
                    plot_id=plot_id,
                    artifact_path=image_rel,
                    artifact_kind="component_lineage_plot",
                    is_manifest_row=True,
                    manifest_status=("not_rendered" if explicitly_not_rendered else status),
                    visual_validity="component_runtime_evidence",
                    source_csv=resolved_source_spec or source_spec,
                    file_info=file_info,
                    source_stats=source_stats,
                    failures=failures,
                )
            )
            seen.add(normalized_image)
    return rows, seen


def resolve_component_source_spec(
    run_folder: Path, lineage_path: Path, source_spec: str
) -> tuple[str, bool, str]:
    members = [part.strip() for part in str(source_spec).split("|") if part.strip()]
    if not members:
        return "", False, ""
    resolved_rel: list[str] = []
    hashes: list[str] = []
    all_exist = True
    for member in members:
        resolved = resolve_owned_lineage_path(run_folder, lineage_path, member)
        if resolved is None or not resolved.is_file():
            all_exist = False
            resolved_rel.append(normalize_rel_path(member))
            hashes.append("")
            continue
        resolved_rel.append(relative_path(run_folder, resolved))
        hashes.append(hashlib.sha256(resolved.read_bytes()).hexdigest())
    return "|".join(resolved_rel), all_exist, "|".join(hashes)


def resolve_owned_lineage_path(
    run_folder: Path, lineage_path: Path, path_spec: str
) -> Path | None:
    """Resolve a lineage path beneath its owning component, never outside the run."""

    run_root = run_folder.resolve()
    candidate_spec = Path(str(path_spec).replace("\\", "/"))
    if any(part == ".." for part in candidate_spec.parts):
        return None
    if candidate_spec.is_absolute():
        candidate = candidate_spec.resolve()
        try:
            candidate.relative_to(run_root)
        except ValueError:
            return None
        return candidate if candidate.exists() else None

    cursor = lineage_path.resolve().parent
    while cursor == run_root or run_root in cursor.parents:
        candidate = (cursor / candidate_spec).resolve()
        try:
            candidate.relative_to(run_root)
        except ValueError:
            return None
        if candidate.exists():
            return candidate
        if cursor == run_root:
            break
        cursor = cursor.parent
    return None


def audit_manifest_row(run_folder: Path, manifest_row: dict[str, str]) -> AuditRow:
    plot_id = get_field(manifest_row, "PlotId", "plot_id")
    image_path = get_field(manifest_row, "ImagePath", "file_path", "ArtifactPath")
    source_csv = get_field(manifest_row, "SourceCSV", "source_csv")
    x_col = get_field(manifest_row, "XVariable", "x_column", "x")
    y_col = get_field(manifest_row, "YVariables", "YVariable", "y_column", "y")
    plot_kind = lower_token(get_field(manifest_row, "PlotType", "plot_kind", "PlotKind"))
    manifest_status = lower_token(get_field(manifest_row, "PlotRenderStatus", "render_status"))
    visual_validity = lower_token(get_field(manifest_row, "VisualValidity", "visual_validity"))
    is_unavailable_card = parse_bool(get_field(manifest_row, "IsUnavailableCard", "is_unavailable_card"))
    unavailable_card_visual = (
        is_unavailable_card
        or manifest_status == "rendered_unavailable_card"
        or is_unavailable_visual_path(image_path)
    )
    source_semantics_required = is_rendered_status(manifest_status) and not unavailable_card_visual and visual_validity != "unavailable"
    normal_rendered = (
        source_semantics_required
        and not is_unavailable_card
        and visual_validity != "unavailable"
        and not is_unavailable_visual_path(image_path)
    )
    file_info = inspect_file(run_folder, image_path)
    source_stats = inspect_source_csv(run_folder, source_csv, x_col, y_col)
    # A measured empirical CDF remains meaningful when several observations
    # are tied: it is a single step whose mass is determined by the sample
    # count.  Do not confuse that legitimate distribution with a fabricated
    # constant line or one-cell heatmap.
    if plot_kind == "cdf" and source_stats.non_nan_y_count >= 2:
        source_stats.low_information_reason = ""
        source_stats.low_information_details = []

    failures: list[tuple[str, str]] = []
    if file_info.extension == ".svg" or file_info.actual_mime_type == "image/svg+xml":
        failures.append(("vector_visual_format_forbidden", "persisted visual artifacts must use PNG or JPEG; SVG is read-only legacy input"))
    if file_info.exists and not file_info.signature_ok:
        failures.append((file_info.signature_status, "visual artifact file extension does not match its byte signature"))
    if file_info.extension == ".svg" and file_info.actual_mime_type == "image/png":
        failures.append(("png_bytes_in_svg", ".svg artifact contains PNG bytes"))
    if is_suppressed_status(manifest_status) and file_info.exists and not is_unavailable_visual_path(image_path):
        failures.append(("stale_suppressed_normal_artifact", "normal plot file exists but manifest says suppressed/not rendered"))
    if unavailable_card_visual and not image_path.endswith("_unavailable.png"):
        failures.append(("unavailable_card_bad_name", "new unavailable visual artifacts must end with _unavailable.png"))
    if unavailable_card_visual and image_path and not file_info.exists:
        failures.append(("unavailable_card_missing", "manifest declares an unavailable visual card but the card file is missing"))

    if not source_semantics_required:
        return make_row(
            run_folder,
            plot_id=plot_id,
            artifact_path=image_path,
            artifact_kind="manifest_plot",
            is_manifest_row=True,
            manifest_status=manifest_status,
            visual_validity=visual_validity,
            source_csv=source_csv,
            x_column=x_col,
            y_column=y_col,
            plot_kind=plot_kind,
            file_info=file_info,
            source_stats=source_stats,
            failures=failures,
        )

    if normal_rendered and not source_stats.source_exists:
        failures.append(("rendered_plot_source_csv_missing", "rendered plot cannot be traced to its source CSV"))
    if source_stats.x_missing and x_col:
        failures.append(("plot_source_x_column_missing", f"source CSV is missing x column '{x_col}'"))
    if source_stats.y_missing and y_col:
        failures.append(("plot_source_y_column_missing", f"source CSV is missing y column '{y_col}'"))
    if source_stats.nan_only_y and normal_rendered:
        failures.append(("nan_only_chart", "rendered chart y-series is NaN/blank-only"))
    if normal_rendered and source_stats.low_information_reason and not file_info.contains_low_information_explanation:
        failures.append(
            (
                "low_information_visual_without_explanation",
                "rendered chart source has insufficient independent variation but the visual does not disclose the low-information gate",
            )
        )
    if normal_rendered and plot_kind == "line" and source_stats.source_exists and source_stats.unique_x_count < 3:
        failures.append(("line_plot_insufficient_unique_x", "line plot uses fewer than 3 unique x values"))
    if plot_kind == "heatmap" and source_stats.mixed_units:
        failures.append(("heatmap_mixed_units", "heatmap source mixes unrelated units"))
    if source_has_bad_mapping(source_csv, source_stats):
        failures.append(("chart_source_mapping_not_exact", "chart source has no exact source mapping"))
    if is_generic_materializer_output(plot_id, image_path, source_csv, source_stats):
        failures.append(("generic_chart_materializer_output", "generic chart materializer output is not allowed in strict audit"))
    if is_mislabeled_snr_sweep(plot_id, image_path, source_stats):
        failures.append(("snr_sweep_from_measured_quality_bins", "SNR plot uses measured SINR/quality binning instead of controlled SNR sweep"))
    if source_uses_forbidden_truth(source_stats):
        failures.append(("plot_source_forbidden_truth_status", "plot source uses proxy/fallback/unavailable truth status"))

    return make_row(
        run_folder,
        plot_id=plot_id,
        artifact_path=image_path,
        artifact_kind="manifest_plot",
        is_manifest_row=True,
        manifest_status=manifest_status,
        visual_validity=visual_validity,
        source_csv=source_csv,
        x_column=x_col,
        y_column=y_col,
        plot_kind=plot_kind,
        file_info=file_info,
        source_stats=source_stats,
        failures=failures,
    )


def audit_stale_normal_siblings(run_folder: Path, manifest_row: dict[str, str]) -> list[AuditRow]:
    image_path = get_field(manifest_row, "ImagePath", "file_path", "ArtifactPath")
    manifest_status = lower_token(get_field(manifest_row, "PlotRenderStatus", "render_status"))
    is_unavailable_card = parse_bool(get_field(manifest_row, "IsUnavailableCard", "is_unavailable_card"))
    if not (is_unavailable_card or is_unavailable_visual_path(image_path) or is_suppressed_status(manifest_status)):
        return []
    image_rel = Path(image_path.replace("\\", "/"))
    stem = image_rel.stem
    if stem.endswith("_unavailable"):
        stem = stem[: -len("_unavailable")]
    folder = run_folder / image_rel.parent
    rows: list[AuditRow] = []
    for ext in (".png", ".jpg", ".jpeg", ".svg"):
        sibling = folder / f"{stem}{ext}"
        if not sibling.exists():
            continue
        rel = relative_path(run_folder, sibling)
        rows.append(
            make_row(
                run_folder,
                plot_id=get_field(manifest_row, "PlotId", "plot_id"),
                artifact_path=rel,
                artifact_kind="stale_normal_sibling",
                is_manifest_row=False,
                manifest_status=manifest_status,
                visual_validity="invalid_stale",
                file_info=inspect_file(run_folder, rel),
                failures=[("stale_suppressed_normal_artifact", "suppressed/unavailable plot left a normal visual artifact sibling")],
            )
        )
    return rows


def audit_unmanifested_visual(run_folder: Path, rel_path: str) -> AuditRow:
    info = inspect_file(run_folder, rel_path)
    source_csv = companion_contract_csv_path(rel_path)
    source_stats = inspect_source_csv(run_folder, source_csv, "", "") if source_csv else SourceStats()
    failures: list[tuple[str, str]] = []
    failures.append(
        (
            "unmanifested_visual_artifact",
            "every persisted PNG or JPEG must have a plot_manifest.csv row with source lineage",
        )
    )
    if info.extension == ".svg" or info.actual_mime_type == "image/svg+xml":
        failures.append(("vector_visual_format_forbidden", "persisted visual artifacts must use PNG or JPEG; SVG is read-only legacy input"))
    if not info.signature_ok:
        failures.append((info.signature_status, "unmanifested visual artifact has invalid byte signature"))
    if info.extension == ".svg" and info.actual_mime_type == "image/png":
        failures.append(("png_bytes_in_svg", ".svg artifact contains PNG bytes"))
    if source_stats.low_information_reason and not info.contains_low_information_explanation:
        failures.append(
            (
                "low_information_visual_without_explanation",
                "contract visual source has insufficient independent variation, but the image does not disclose that gate",
            )
        )
    return make_row(
        run_folder,
        plot_id="",
        artifact_path=rel_path,
        artifact_kind="unmanifested_visual_file",
        is_manifest_row=False,
        file_info=info,
        source_csv=source_csv,
        source_stats=source_stats,
        failures=failures,
    )


def audit_contract_source_csvs(run_folder: Path, manifest_rows: list[dict[str, str]]) -> list[AuditRow]:
    referenced = {normalize_rel_path(get_field(r, "SourceCSV", "source_csv")) for r in manifest_rows}
    rows: list[AuditRow] = []
    for csv_path in list((run_folder / "analytics" / "csv").glob("contract__*.csv")) + list((run_folder / "reports" / "csv").glob("contract__*.csv")):
        rel = normalize_rel_path(relative_path(run_folder, csv_path))
        if rel in referenced:
            continue
        stats = inspect_source_csv(run_folder, rel, "", "")
        failures: list[tuple[str, str]] = []
        if source_has_bad_mapping(rel, stats):
            failures.append(("chart_source_mapping_not_exact", "contract chart CSV has no exact source mapping"))
        if is_generic_materializer_output("", "", rel, stats):
            failures.append(("generic_chart_materializer_output", "contract chart CSV looks like generic materializer output"))
        rows.append(
            make_row(
                run_folder,
                plot_id=Path(rel).stem,
                artifact_path=rel,
                artifact_kind="contract_source_csv",
                source_csv=rel,
                source_stats=stats,
                failures=failures,
            )
        )
    return rows


def inspect_source_csv(run_folder: Path, source_csv: str, x_col: str, y_col: str) -> SourceStats:
    stats = SourceStats()
    if not source_csv:
        return stats
    # A visual may be sourced from a canonical DL/UL union.  At least one
    # existing member is sufficient for a direction-specific run; each
    # existing member is inspected and contributes to the combined stats.
    source_members = [
        member.strip()
        for member in source_csv.replace("\\", "/").split("|")
        if member.strip()
    ]
    x_values: set[str] = set()
    y_values: set[str] = set()
    unit_values: set[str] = set()
    curve_values: set[str] = set()
    truth_values: set[str] = set()
    plot_truth_values: set[str] = set()
    mapping_values: set[str] = set()
    chart_modes: set[str] = set()
    chart_names: set[str] = set()
    saw_y_column = not y_col
    saw_x_column = not x_col
    axis_columns_available = False

    for member in source_members:
        path = run_folder / member
        if not path.exists() or not path.is_file():
            continue
        stats.source_exists = True
        try:
            with path.open("r", encoding="utf-8-sig", newline="") as handle:
                reader = csv.DictReader(handle)
                fieldnames = list(reader.fieldnames or [])
                member_x_col, member_y_col = infer_chart_source_columns(
                    fieldnames, x_col, y_col
                )
                axis_columns_available = axis_columns_available or bool(
                    member_x_col and member_y_col
                )
                plot_truth_columns = plot_scoped_truth_columns(
                    fieldnames, split_plot_columns(member_x_col, member_y_col)
                )
                saw_x_column = saw_x_column or member_x_col in fieldnames
                saw_y_column = saw_y_column or member_y_col in fieldnames
                for row in reader:
                    stats.row_count += 1
                    if member_x_col and member_x_col in row:
                        value = normalize_cell(row.get(member_x_col, ""))
                        if value and not is_nan_token(value):
                            x_values.add(value)
                    if member_y_col and member_y_col in row:
                        value = normalize_cell(row.get(member_y_col, ""))
                        if value and not is_nan_token(value):
                            stats.non_nan_y_count += 1
                            y_values.add(value)
                    collect_values(row, UNIT_COLUMNS, unit_values)
                    collect_values(row, CURVE_COLUMNS, curve_values)
                    collect_values(row, TRUTH_COLUMNS, truth_values)
                    collect_values(row, plot_truth_columns, plot_truth_values)
                    collect_values(row, SOURCE_MAPPING_COLUMNS, mapping_values)
                    collect_values(row, CHART_MODE_COLUMNS, chart_modes)
                    collect_values(row, ("chart_name", "ChartName"), chart_names)
        except UnicodeDecodeError:
            # Fail closed if an existing source member cannot be decoded.
            stats.source_exists = False
            return stats

    if not stats.source_exists:
        return stats

    stats.unique_x_count = len(x_values)
    stats.unique_y_count = len(y_values)
    stats.nan_only_y = bool(y_col and saw_y_column and stats.row_count > 0 and stats.non_nan_y_count == 0)
    stats.units = sorted(unit_values)
    stats.mixed_units = len(unit_values) > 1
    stats.curve_construction = sorted(curve_values)
    stats.truth_tokens = sorted(truth_values)
    stats.plot_truth_tokens = sorted(plot_truth_values)
    stats.source_mapping_status = sorted(mapping_values)
    stats.chart_modes = sorted(chart_modes)
    stats.chart_names = sorted(chart_names)
    stats.x_missing = bool(x_col and not saw_x_column)
    stats.y_missing = bool(y_col and not saw_y_column)
    if axis_columns_available:
        stats.low_information_reason, stats.low_information_details = source_low_information_reason(stats)
    return stats


def infer_chart_source_columns(fieldnames: list[str], x_col: str, y_col: str) -> tuple[str, str]:
    lower_to_original = {str(name).strip().lower(): str(name) for name in fieldnames}
    if not x_col:
        for candidate in ("x_value", "snr_db", "slot", "frame", "beam_gap_value", "metric_value"):
            if candidate in lower_to_original:
                x_col = lower_to_original[candidate]
                break
    if not y_col:
        for candidate in ("y_value", "z_value", "metric_value", "bler", "ber", "throughput_mbps", "goodput_mbps", "beam_gap_value"):
            if candidate in lower_to_original:
                y_col = lower_to_original[candidate]
                break
    if not x_col and y_col:
        x_col = y_col
    if not y_col and x_col:
        y_col = x_col
    return x_col, y_col


def source_low_information_reason(stats: SourceStats) -> tuple[str, list[str]]:
    if not stats.source_exists or stats.row_count <= 0:
        return "", []
    mode = next((lower_token(value) for value in stats.chart_modes if value), "")
    details = [
        f"row_count={stats.row_count}",
        f"unique_x={stats.unique_x_count}",
        f"unique_y={stats.unique_y_count}",
        f"non_nan_y={stats.non_nan_y_count}",
        f"chart_mode={mode or 'unknown'}",
    ]
    if stats.non_nan_y_count == 0:
        return "no_finite_y_values", details
    if stats.row_count > 1 and stats.unique_x_count == 1 and stats.unique_y_count == 1:
        return "constant_chart_source", details
    if mode in {"line", "cdf"}:
        if stats.row_count < 3:
            return "insufficient_rows_for_trend", details
        if stats.unique_x_count < 3:
            return "insufficient_unique_x_for_trend", details
        if mode == "line" and stats.unique_y_count < 2:
            return "constant_y_for_trend", details
    elif mode in {"scatter", "relation", "vs"}:
        if stats.row_count < 2:
            return "insufficient_rows_for_relation", details
        if stats.unique_x_count < 2:
            return "constant_x_for_relation", details
        if stats.unique_y_count < 2:
            return "constant_y_for_relation", details
    elif mode in {"bar", "histogram", "distribution"}:
        if stats.unique_x_count < 2:
            return "single_bucket_distribution", details
    elif mode == "heatmap":
        if stats.unique_x_count < 2 or stats.unique_y_count < 2:
            return "insufficient_heatmap_axes", details
    elif stats.row_count == 1 and stats.unique_x_count <= 1 and stats.unique_y_count <= 1:
        return "single_value_chart_source", details
    return "", details


def inspect_file(run_folder: Path, rel_path: str) -> FileInfo:
    rel_path = normalize_rel_path(rel_path)
    path = run_folder / rel_path
    ext = path.suffix.lower()
    info = FileInfo(
        rel_path=rel_path,
        exists=path.exists(),
        extension=ext,
        declared_mime_type=declared_mime(ext),
    )
    if not path.exists() or not path.is_file():
        return info
    data = path.read_bytes()
    info.byte_count = len(data)
    info.sha256 = hashlib.sha256(data).hexdigest()
    info.actual_mime_type = detect_mime(data)
    expected = expected_extension(info.actual_mime_type)
    info.signature_ok = bool(
        expected
        and (
            ext == expected
            or (info.actual_mime_type == "text/html" and ext == ".htm")
            or (info.actual_mime_type == "image/jpeg" and ext == ".jpeg")
        )
    )
    if info.signature_ok:
        info.signature_status = "ok"
    elif info.actual_mime_type == "unknown":
        info.signature_status = "unknown_signature"
    else:
        info.signature_status = "extension_mime_mismatch"
    text_payload = data[:65536].decode("utf-8", errors="ignore").lower()
    info.contains_low_information_explanation = any(marker in text_payload for marker in LOW_INFORMATION_VISUAL_MARKERS)
    return info


def companion_contract_csv_path(rel_path: str) -> str:
    rel = normalize_rel_path(rel_path)
    if "/contract__" not in rel or not rel.endswith((".png", ".svg")):
        return ""
    if "/image/" not in rel:
        return ""
    return rel.replace("/image/", "/csv/").rsplit(".", 1)[0] + ".csv"


def inventory_visual_files(run_folder: Path) -> Iterable[Path]:
    for path in run_folder.rglob("*"):
        if path.is_file() and path.suffix.lower() in VISUAL_EXTENSIONS:
            yield path


def write_outputs(run_folder: Path, rows: list[AuditRow]) -> None:
    csv_dir = run_folder / "reports" / "csv"
    report_dir = run_folder / "reports"
    csv_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)

    fieldnames = list(AuditRow.__dataclass_fields__.keys())
    with (csv_dir / "visual_artifact_audit.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({name: getattr(row, name) for name in fieldnames})

    failures = [r for r in rows if not r.audit_ok]
    with (report_dir / "visual_artifact_audit.md").open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Visual Artifact Audit\n\n")
        handle.write(f"- Run folder: `{run_folder}`\n")
        handle.write(f"- Audited rows: {len(rows)}\n")
        handle.write(f"- Strict failures: {len(failures)}\n\n")
        if failures:
            handle.write("| Plot | Artifact | Failure | Reason |\n")
            handle.write("|---|---|---|---|\n")
            for row in failures:
                handle.write(
                    f"| {md_escape(row.plot_id)} | {md_escape(row.artifact_path)} | "
                    f"{md_escape(row.failure_code)} | {md_escape(row.failure_reason)} |\n"
                )
        else:
            handle.write("No strict visual artifact audit failures were found.\n")


def make_row(
    run_folder: Path,
    *,
    plot_id: str = "",
    artifact_path: str = "",
    artifact_kind: str = "",
    is_manifest_row: bool = False,
    manifest_status: str = "",
    visual_validity: str = "",
    source_csv: str = "",
    x_column: str = "",
    y_column: str = "",
    plot_kind: str = "",
    file_info: FileInfo | None = None,
    source_stats: SourceStats | None = None,
    failures: list[tuple[str, str]] | None = None,
    failure_code: str = "",
    failure_reason: str = "",
) -> AuditRow:
    if file_info is None:
        file_info = inspect_file(run_folder, artifact_path) if artifact_path else FileInfo(rel_path="")
    if source_stats is None:
        source_stats = SourceStats()
    all_failures = list(failures or [])
    if failure_code:
        all_failures.append((failure_code, failure_reason))
    audit_ok = len(all_failures) == 0
    codes = "|".join(dict.fromkeys(code for code, _ in all_failures if code))
    reasons = "|".join(dict.fromkeys(reason for _, reason in all_failures if reason))
    return AuditRow(
        plot_id=str(plot_id),
        artifact_path=normalize_rel_path(artifact_path or file_info.rel_path),
        artifact_kind=str(artifact_kind),
        is_manifest_row=bool(is_manifest_row),
        manifest_status=str(manifest_status),
        visual_validity=str(visual_validity),
        source_csv=normalize_rel_path(source_csv),
        x_column=str(x_column),
        y_column=str(y_column),
        plot_kind=str(plot_kind),
        row_count=source_stats.row_count if source_stats.source_exists else "",
        unique_x_count=source_stats.unique_x_count if source_stats.source_exists else "",
        unique_y_count=source_stats.unique_y_count if source_stats.source_exists else "",
        non_nan_y_count=source_stats.non_nan_y_count if source_stats.source_exists else "",
        nan_only_y=source_stats.nan_only_y,
        mixed_units=source_stats.mixed_units,
        source_mapping_status="|".join(source_stats.source_mapping_status),
        curve_construction="|".join(source_stats.curve_construction),
        truth_status_tokens="|".join(source_stats.truth_tokens),
        actual_mime_type=file_info.actual_mime_type,
        declared_mime_type=file_info.declared_mime_type,
        extension=file_info.extension,
        sha256=file_info.sha256,
        byte_count=file_info.byte_count,
        audit_ok=audit_ok,
        failure_code=codes,
        failure_reason=reasons,
    )


def read_csv_dicts(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def collect_values(row: dict[str, str], columns: Iterable[str], target: set[str]) -> None:
    for column in columns:
        if column not in row:
            continue
        value = lower_token(row.get(column, ""))
        if value and value not in {"nan", "<missing>", "not_applicable"}:
            target.add(value)


def split_plot_columns(x_col: str, y_col: str) -> list[str]:
    values: list[str] = []
    for raw in (x_col, y_col):
        text = str(raw or "")
        for part in text.replace(";", "|").replace(",", "|").split("|"):
            part = part.strip()
            if part:
                values.append(part)
    return values


def plot_scoped_truth_columns(fieldnames: list[str], plot_columns: list[str]) -> list[str]:
    metric_bases = {metric_base_name(name) for name in plot_columns}
    metric_bases.discard("")
    if not metric_bases:
        return []
    scoped: list[str] = []
    for fieldname in fieldnames:
        normalized = normalize_field_name(fieldname)
        for base in metric_bases:
            if normalized.startswith(base) and any(normalized.endswith(suffix) for suffix in PLOT_SCOPED_STATUS_SUFFIXES):
                scoped.append(fieldname)
                break
    return scoped


def metric_base_name(name: str) -> str:
    normalized = normalize_field_name(name)
    for suffix in (
        "dbm",
        "db",
        "khz",
        "mhz",
        "ghz",
        "hz",
        "ms",
        "us",
        "ns",
        "s",
        "bits",
        "bytes",
        "mbps",
        "gbps",
        "samples",
        "slots",
    ):
        if normalized.endswith(suffix) and len(normalized) > len(suffix):
            return normalized[: -len(suffix)]
    return normalized


def normalize_field_name(name: str) -> str:
    return "".join(ch for ch in str(name).lower() if ch.isalnum())


def get_field(row: dict[str, str], *names: str) -> str:
    lower_map = {k.lower(): k for k in row}
    for name in names:
        if name in row:
            return normalize_cell(row.get(name, ""))
        key = lower_map.get(name.lower())
        if key is not None:
            return normalize_cell(row.get(key, ""))
    return ""


def parse_bool(value: str) -> bool:
    return lower_token(value) in {"1", "true", "yes", "y"}


def normalize_cell(value: object) -> str:
    if value is None:
        return ""
    return str(value).strip()


def lower_token(value: object) -> str:
    return normalize_cell(value).lower()


def normalize_rel_path(path: str) -> str:
    return str(path or "").replace("\\", "/").lstrip("/")


def safe_run_relative_path(path: str) -> bool:
    text = str(path or "").replace("\\", "/")
    candidate = Path(text)
    return bool(
        text
        and not text.startswith("/")
        and not candidate.is_absolute()
        and ":" not in text
        and ".." not in candidate.parts
    )


def relative_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def is_nan_token(value: str) -> bool:
    text = lower_token(value)
    if text in {"", "nan", "<missing>", "missing", "none"}:
        return True
    try:
        return math.isnan(float(text))
    except ValueError:
        return False


def is_suppressed_status(status: str) -> bool:
    status = lower_token(status)
    return status in SUPPRESSED_STATUSES or "suppressed" in status


def is_rendered_status(status: str) -> bool:
    return "rendered" in lower_token(status)


def declared_mime(ext: str) -> str:
    return {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".svg": "image/svg+xml",
        ".html": "text/html",
        ".htm": "text/html",
    }.get(ext.lower(), "application/octet-stream")


def expected_extension(mime: str) -> str:
    return {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/svg+xml": ".svg",
        "text/html": ".html",
    }.get(mime.lower(), "")


def detect_mime(data: bytes) -> str:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    prefix = data[:4096].decode("utf-8", errors="ignore").lstrip("\ufeff").strip().lower()
    if prefix.startswith("<svg") or (prefix.startswith("<?xml") and "<svg" in prefix):
        return "image/svg+xml"
    if prefix.startswith("<!doctype html") or prefix.startswith("<html") or "<html" in prefix[:256]:
        return "text/html"
    return "unknown"


def source_has_bad_mapping(source_csv: str, stats: SourceStats) -> bool:
    if not stats.source_exists:
        return False
    mapping = {lower_token(v) for v in stats.source_mapping_status if v}
    is_contract = "contract__" in lower_token(source_csv)
    if mapping:
        return any(value != "exact" for value in mapping)
    return is_contract


def is_generic_materializer_output(plot_id: str, image_path: str, source_csv: str, stats: SourceStats) -> bool:
    if not stats.source_exists:
        return False
    identity = " ".join([plot_id, image_path, source_csv, " ".join(stats.chart_names)]).lower()
    modes = {lower_token(v) for v in stats.chart_modes}
    unsafe_family = any(token in identity for token in UNSAFE_GENERIC_FAMILIES)
    provenance_tokens = " ".join(stats.truth_tokens + stats.curve_construction)
    if unsafe_family and ("generic" in provenance_tokens or source_has_bad_mapping(source_csv, stats)):
        return True
    if "contract__" in lower_token(source_csv) and source_has_bad_mapping(source_csv, stats):
        return True
    return False


def is_mislabeled_snr_sweep(plot_id: str, image_path: str, stats: SourceStats) -> bool:
    identity = f"{plot_id} {image_path}".lower()
    if "_vs_snr" not in identity and "vs_snr" not in identity:
        return False
    tokens = " ".join(stats.curve_construction + stats.truth_tokens).lower()
    return "measured_quality_binning" in tokens or "measured_sinr_bin" in tokens or "measured_bin" in tokens


def source_uses_forbidden_truth(stats: SourceStats) -> bool:
    if semantic_tokens_contain(stats.truth_tokens, STRONG_FORBIDDEN_TRUTH_TOKENS):
        return True
    if semantic_tokens_contain(stats.plot_truth_tokens, FORBIDDEN_TRUTH_TOKENS):
        return True
    return False


def semantic_tokens_contain(values: Iterable[str], forbidden: Iterable[str]) -> bool:
    """Match provenance identifiers, not letter sequences inside prose."""
    for forbidden_value in forbidden:
        parts = [re.escape(part) for part in str(forbidden_value).lower().split("_")]
        pattern = r"(?:^|[^a-z0-9])" + r"[_ -]+".join(parts) + r"(?:[^a-z0-9]|$)"
        for value in values:
            if re.search(pattern, str(value).lower()):
                return True
    return False


def md_escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


if __name__ == "__main__":
    sys.exit(main())
