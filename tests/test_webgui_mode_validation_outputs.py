from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_contract_aliases as aliases  # noqa: E402
import lls_output_contract as output_contract  # noqa: E402
import lls_web_dashboard as dash  # noqa: E402


def test_mode_validation_aliases_are_registered() -> None:
    assert aliases.CONTRACT_TABLE_ALIAS_PATHS["fixed_snr_sweep_audit"] == ["reports/csv/fixed_snr_sweep_audit.csv"]
    assert aliases.CONTRACT_TABLE_ALIAS_PATHS["trajectory_geometry"] == ["geometry/csv/trajectory_geometry.csv"]
    assert aliases.CONTRACT_TABLE_ALIAS_PATHS["all_image_artifact_audit"] == ["reports/csv/all_image_artifact_audit.csv"]

    assert "reports/image/dl_bler_vs_snr.png" in aliases.CONTRACT_CHART_ALIAS_PATHS["dl_bler_vs_snr"]
    assert "geometry/image/topology_map.png" in aliases.CONTRACT_CHART_ALIAS_PATHS["topology_map"]
    assert "reports/image/measured_sinr_vs_slot.png" in aliases.CONTRACT_CHART_ALIAS_PATHS["measured_sinr_vs_slot"]


def test_output_contract_surfaces_mode_sections() -> None:
    sections = output_contract.product_sections_payload("reports")
    section_by_slug = {section["slug"]: section for section in sections}

    assert "fixed-snr-sinr-sweep-validation" in section_by_slug
    assert "geometry-mobility-validation" in section_by_slug
    assert "artifact-audit-validation" in section_by_slug

    fixed_tables = {row["table_name"] for row in section_by_slug["fixed-snr-sinr-sweep-validation"]["tables"]}
    geometry_tables = {row["table_name"] for row in section_by_slug["geometry-mobility-validation"]["tables"]}
    audit_tables = {row["table_name"] for row in section_by_slug["artifact-audit-validation"]["tables"]}

    assert {"fixed_snr_sweep_audit", "fixed_snr_sweep_curve_summary", "dl_fixed_snr_bler_curve", "ul_fixed_snr_bler_curve"} <= fixed_tables
    assert {"geometry_runtime_audit", "trajectory_geometry", "doppler_reconciliation"} <= geometry_tables
    assert {"all_csv_artifact_audit", "all_image_artifact_audit"} <= audit_tables


def test_webgui_bucket_classifiers_cover_mode_outputs() -> None:
    assert dash.infer_plot_bucket("reports/image/dl_bler_vs_snr.png") == "fixed_snr_sweep"
    assert dash.infer_plot_bucket("geometry/image/topology_map.png") == "geometry_mobility"
    assert dash.infer_plot_bucket("reports/csv/fixed_snr_sweep_audit.csv") == "artifact_audit"

    assert dash.infer_table_bucket("reports/csv/dl_fixed_snr_bler_curve.csv") == "fixed_snr_sweep"
    assert dash.infer_table_bucket("geometry/csv/trajectory_geometry.csv") == "geometry_mobility"
    assert dash.infer_table_bucket("reports/csv/two_mode_acceptance_gates.csv") == "artifact_audit"


def test_reference_plot_gallery_has_mode_specific_aliases() -> None:
    spec_ids = {spec["id"] for spec in dash.REFERENCE_PLOT_GALLERY_SPECS}
    assert {"dl_bler_vs_snr", "ul_bler_vs_snr", "dl_ber_vs_snr", "ul_ber_vs_snr"} <= spec_ids
    assert {"topology_map", "ue_trajectory_xy", "doppler_vs_slot", "measured_sinr_vs_slot"} <= spec_ids
