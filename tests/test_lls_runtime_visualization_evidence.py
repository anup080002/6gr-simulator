import csv
import hashlib
import io
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from lls_runtime_visualization_evidence import verified_runtime_visualizations


def fixture():
    source = "reports/csv/contract__csi__sinr.csv"
    image = "reports/image/contract__csi__sinr.png"
    receipt = "published/browser_publication_receipt.json"
    lineage = "reports/csv/contract_plot_lineage.csv"
    payloads = {source: b"Slot,CSI_SINR_dB\n1,12\n", image: b"test-only-raster-bytes"}
    payloads[receipt] = json.dumps(dict(SchemaName="sixgr.browser_publication_receipt", Status="PASS",
        BrowserMaterialized=True, MissingRequiredTableCount=0, MissingRequiredChartCount=0,
        MaterializerExitCode=0, RunID="fixture-not-production")).encode()
    row = dict(ImagePath=image, SourceCSV=source, ImageSHA256=hashlib.sha256(payloads[image]).hexdigest(),
               SourceCSV_SHA256=hashlib.sha256(payloads[source]).hexdigest(), Status="pass",
               ProducerModule="apps.lls_contract_materializer")
    text = io.StringIO(); writer = csv.DictWriter(text, fieldnames=row)
    writer.writeheader(); writer.writerow(row)
    payloads[lineage] = text.getvalue().encode()
    artifacts = [dict(logical_path=path, artifact_id=index, artifact_kind="test_fixture",
        byte_size=len(payloads[path]), created_utc="2026-09-12T00:00:00Z")
        for index, path in enumerate(payloads, 1)]
    return artifacts, payloads, source, image, receipt


def test_verified_plot_scope_is_not_primary_component_truth():
    artifacts, payloads, *_ = fixture()
    selected = verified_runtime_visualizations(artifacts, lambda a: payloads[a["logical_path"]])
    assert len(selected) == 2
    assert all(a["evidence_scope"] == "verified_runtime_visualization" and a["hash_verified"] for a in selected)
    assert all("evidence_scope" not in a for a in artifacts)


def test_stale_source_or_image_is_not_published():
    for index in [2, 3]:
        artifacts, payloads, source, image, receipt = fixture()
        payloads[[None, None, source, image][index]] += b"changed"
        assert not verified_runtime_visualizations(artifacts, lambda a: payloads[a["logical_path"]])


def test_failed_or_missing_receipt_and_ambiguous_membership_fail_closed():
    artifacts, payloads, source, image, receipt = fixture()
    assert not verified_runtime_visualizations(artifacts + [artifacts[0]], lambda a: payloads[a["logical_path"]])
    assert not verified_runtime_visualizations([a for a in artifacts if a["logical_path"] != receipt], lambda a: payloads[a["logical_path"]])
    r = json.loads(payloads[receipt]); r["Status"] = "FAIL"; payloads[receipt] = json.dumps(r).encode()
    assert not verified_runtime_visualizations(artifacts, lambda a: payloads[a["logical_path"]])


def test_component_cards_show_verified_visualizations_without_promoting_primary():
    import lls_web_dashboard as dashboard
    artifacts, payloads, *_ = fixture()
    verified = verified_runtime_visualizations(artifacts, lambda a: payloads[a["logical_path"]])
    primary = [dict(logical_path="components/pdsch/qualification/csv/pdsch_bler.csv",
        artifact_id=10, artifact_kind="table_csv", byte_size=10, created_utc="2026-09-12T00:00:00Z")]
    cards = dashboard.build_realtime_component_dashboard(primary, "completed", verified)
    csi = next(row for row in cards if row["component_id"] == "csi")
    assert csi["canonical_artifact_count"] == 0
    assert csi["visualization_artifact_count"] == csi["artifact_count"] == 2
    assert csi["csv_count"] == csi["image_count"] == 1
    assert csi["status"] == "evidence_available"  # Not a PHY pass verdict.
    cards = dashboard.build_realtime_component_dashboard(primary, "completed", artifacts)
    assert next(row for row in cards if row["component_id"] == "csi")["artifact_count"] == 0


def test_legacy_selection_does_not_double_count_verified_visualizations():
    import lls_web_dashboard as dashboard
    artifacts, payloads, *_ = fixture()
    verified = verified_runtime_visualizations(artifacts, lambda a: payloads[a["logical_path"]])
    cards = dashboard.build_realtime_component_dashboard(verified, "completed", verified)
    csi = next(row for row in cards if row["component_id"] == "csi")
    assert csi["artifact_count"] == 2 and csi["visualization_artifact_count"] == 0
