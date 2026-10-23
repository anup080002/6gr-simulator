"""Bridge an explicitly retained native DFT PHY component to the real publisher.

Set SIXGR_NATIVE_DFT_ARTIFACT_ROOT to the new directory returned by
testPUSCHRXConsistencyConvention(artifactRoot). Without an actual artifact
these checks SKIP, not pass using declared rows or another waveform run.
"""
import csv
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import publish_lls_live_csv_plots as live

CAPTURE = "air_interface/csv/ul_constellation_samples.csv"
RECEIPT = "native_dft_component.json"
MAT = "native_dft_component.mat"
CHART = "post-equalization constellation"
DOMAIN = "pre_transform_qam_positions"
ORDER_DOMAIN = "native_pre_transform_allocation_position_key"
SCOPE = "direct_no_noise_PUSCH_PHY_component_not_shared_runtime_or_scenario"


def _sha(path):
    return live.file_digest(path)


def _rows(path):
    with live.io_path(path).open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def _energies(rows, real, imag, reference_real, reference_imag):
    pairs = [(float(r[real]), float(r[imag]), float(r[reference_real]), float(r[reference_imag]))
             for r in rows]
    assert all(math.isfinite(v) for pair in pairs for v in pair)
    return (math.fsum((x-a)**2 + (y-b)**2 for x, y, a, b in pairs),
            math.fsum(a*a + b*b for _, _, a, b in pairs))


def _native(root):
    receipt = json.loads(live.io_path(root / RECEIPT).read_text(encoding="utf-8-sig"))
    assert receipt["Version"] == "native_dft_constellation_component/v1"
    assert receipt["Status"] == "actual_native_DFT_case_assertions_passed"
    assert receipt["Producer"] == "testPUSCHRXConsistencyConvention"
    assert receipt["Case"] == "dft_s_ofdm_noncodebook"
    assert receipt["EvidenceScope"] == SCOPE
    assert receipt["TerminalQualification"] is False
    assert receipt["PopulationScopeComplete"] is False
    assert receipt["SharedReceiverClockEvidenceAvailable"] is False
    assert receipt["AdditionalPHYExecutionsForPersistence"] == 0
    assert receipt["ReceiverConfigurationSource"] == "supplied_native_TX_allocation_TBS_RV_and_coding_layout"
    assert receipt["ReceiverSkipTimingEstimate"] is True
    assert receipt["AppliedChannel"] == "TX_waveform_passed_directly_to_RX_without_added_noise"
    assert receipt["ConfiguredSNRRole"] == "configuration_only_not_applied_or_measured_noise"
    assert receipt["SuppliedDecoderNoiseVariance"] == 1e-9
    assert receipt["SuppliedDecoderNoiseVarianceDomain"] == "grid"
    assert receipt["SuppliedDecoderNoiseVarianceRole"] == "receiver_parameter_not_injected_noise_measurement"
    assert receipt["RNGProvenance"] == "exact_rng_state_immediately_before_this_TX_retained_in_MAT"
    assert receipt["CRCPass"] is True and receipt["BitErrors"] == receipt["SymbolErrors"] == 0
    assert receipt["SourceCSV"] == CAPTURE and receipt["MATFile"] == MAT
    for path, key in ((CAPTURE, "SourceCSVSHA256"), (MAT, "MATFileSHA256")):
        assert re.fullmatch(r"[0-9a-f]{64}", receipt[key])
        assert _sha(root / path) == receipt[key], "Native artifact hash mismatch: " + path
    sources = receipt["ProducerSources"]
    assert len(sources) == len({r["Function"] for r in sources}) == 6
    assert all(re.fullmatch(r"[0-9a-f]{64}", r["SHA256"]) for r in sources)
    rows = _rows(root / CAPTURE)
    count = receipt["SourceRows"]
    assert count > 0 and len(rows) == count == receipt["QAMSymbolCount"] == receipt["UniqueNativePositions"]
    assert receipt["SymbolCoordinateDomain"] == DOMAIN
    assert receipt["SymbolOrderLinearIndexDomain"] == ORDER_DOMAIN
    assert receipt["CaptureScope"] == "full_allocation_paired_symbols"
    native_positions = []
    for index, row in enumerate(rows, 1):
        assert row["Direction"] == "UL"
        assert row["SymbolCoordinateDomain"] == DOMAIN
        assert row["SymbolOrderLinearIndexDomain"] == ORDER_DOMAIN
        assert row["CaptureScope"] == receipt["CaptureScope"]
        assert float(row["SampleIndex"]) == index
        assert float(row["ObservationSymbolCount"]) == float(row["CapturedSymbolCount"]) == count
        assert math.isnan(float(row["SubcarrierIndex"]))
        assert float(row["SNR_dB"]) == receipt["ConfiguredSNR_dB"]
        for field in ("SymbolOrderLinearIndex", "OFDMSymbolIndex", "LayerIndex"):
            value = float(row[field])
            assert math.isfinite(value) and value >= 1 and value.is_integer()
        native_positions.append(row["SymbolOrderLinearIndex"])
    assert len(set(native_positions)) == count
    error, reference = _energies(rows, "RawEqualizedReal", "RawEqualizedImag",
                                 "ReferenceSymbolReal", "ReferenceSymbolImag")
    assert math.isclose(error, receipt["RawErrorEnergy"], rel_tol=1e-12, abs_tol=1e-24)
    assert math.isclose(reference, receipt["ReferenceEnergy"], rel_tol=1e-12, abs_tol=1e-24)
    return receipt, rows


@pytest.fixture(scope="module")
def native():
    path = os.environ.get("SIXGR_NATIVE_DFT_ARTIFACT_ROOT")
    if not path:
        pytest.skip("No actual retained DFT artifact requested; native publication is not exercised")
    root = Path(path).resolve()
    assert root.is_dir(), "Explicit native DFT artifact root does not exist"
    receipt, rows = _native(root)
    return root, receipt, rows


@pytest.mark.parametrize("file_payload", [False, True])
def test_native_dft_capture_through_publication(native, tmp_path, monkeypatch, file_payload):
    source, receipt, original = native
    before = {str(p.relative_to(source)): _sha(p) for p in source.rglob("*") if p.is_file()}
    if file_payload:
        monkeypatch.setattr(live.materializer, "CSV_MEMORY_LIMIT_BYTES", 1024)
    result = live.publish(tmp_path, source_run_folder=source)
    manifest_path = live.io_path(Path(result["Manifest"]))
    manifest = json.loads(manifest_path.read_text())
    assert manifest["terminal_qualification"] is False
    assert manifest["status"] == "post_run_diagnostic_preview"
    assert manifest["source_sha256"][CAPTURE] == receipt["SourceCSVSHA256"]
    assert (manifest_path.parent / "sources" / CAPTURE).read_bytes() == (source / CAPTURE).read_bytes()
    chart = next(c for c in manifest["charts"] if c["name"] == CHART)
    assert chart["status"] == "measured_checkpoint" and chart["source_paths"] == CAPTURE
    plotted = _rows(manifest_path.parent / chart["csv"])
    assert len(plotted) == chart["source_row_count"] == receipt["SourceRows"]
    exact = {
        "symbol_coordinate_domain": "SymbolCoordinateDomain",
        "symbol_order_linear_index_domain": "SymbolOrderLinearIndexDomain",
        "symbol_order_linear_index": "SymbolOrderLinearIndex",
        "ofdm_symbol_index": "OFDMSymbolIndex", "subcarrier_index": "SubcarrierIndex",
        "layer_index": "LayerIndex", "codeword_index": "CodewordIndex",
        "sample_index": "SampleIndex", "capture_scope": "CaptureScope",
        "observation_symbol_count": "ObservationSymbolCount", "captured_symbol_count": "CapturedSymbolCount",
    }
    optional = {"input_run_id": "RunID", "execution_id": "ExecutionID", "config_hash": "ConfigHash",
                "source_run_id": "SourceRunID", "sweep_point_index": "SweepPointIndex",
                "seed": "Seed", "random_seed": "RandomSeed", "channel_seed": "ChannelSeed",
                "ue_index": "UEIndex", "frame": "Frame", "slot": "Slot",
                "observation_id": "ObservationID", "receiver_window_id": "ReceiverWindowID",
                "receiver_clock_domain": "ReceiverClockDomain", "receiver_clock_epoch": "ReceiverClockEpoch"}
    for index, (got, raw) in enumerate(zip(plotted, original), 1):
        assert int(got["source_row_index"]) == index
        assert got["source_table_logical_path"] == CAPTURE
        assert all(got[a] == raw[b] for a, b in exact.items())
        assert all(got[a] == raw.get(b, "") for a, b in optional.items())
        assert got["snr_source_field"] == "SNR_dB"
        assert got["snr_value_role"] == "unspecified_source_column"
        assert float(got["snr_source_value_db"]) == float(raw["SNR_dB"])
        assert got["configured_snr_db"] == ""  # Sidecar authority was not injected into CSV rows.
        for actual, expected in (("x_value", "RawEqualizedReal"), ("y_value", "RawEqualizedImag"),
                                 ("reference_x", "ReferenceSymbolReal"), ("reference_y", "ReferenceSymbolImag")):
            assert float(got[actual]) == float(raw[expected])
    assert _energies(plotted, "x_value", "y_value", "reference_x", "reference_y") == _energies(
        original, "RawEqualizedReal", "RawEqualizedImag", "ReferenceSymbolReal", "ReferenceSymbolImag")
    with Image.open(manifest_path.parent / chart["png"]) as image:
        assert image.format == "PNG"
        caption = image.info["sixgr_visual_semantics"]
        assert "POST-RUN PREVIEW" in caption and "not final qualification" in caption
        assert DOMAIN in caption and ORDER_DOMAIN in "".join(caption.split())
        compact_caption = "".join(caption.split())
        assert "SourceSNR_dB=45.0dB(rolenotretained)" in compact_caption
        assert "SNR=45.0" not in caption and "Configured SNR=45.0" not in caption
        assert "not an applied/measured noise claim" in caption
        assert "CSV: all retained samples" in caption and "Preview: up to 450 samples/panel" in caption
        image.verify()
    # The bare native component has no UE/frame/slot owner. Do not fabricate
    # these to turn a scatter bridge into a runtime full-profile claim.
    evm = next(c for c in manifest["charts"] if c["name"] == "PUSCH EVM per symbol")
    assert evm["status"] == "unavailable_at_checkpoint"
    assert live.publish(tmp_path, source_run_folder=source)["Status"] == "unchanged_verified_snapshot"
    sys.path.insert(0, str(ROOT / "tools"))
    import audit_lls_visual_artifacts as audit
    audit_rows, seen = audit.audit_component_plot_lineages(audit.windows_extended_path(tmp_path), set())
    assert len(audit_rows) == len(seen) == manifest["png_count"]
    assert all(not row.failure_code for row in audit_rows)
    assert before == {str(p.relative_to(source)): _sha(p) for p in source.rglob("*") if p.is_file()}


@pytest.mark.parametrize("path", [CAPTURE, MAT])
def test_native_artifact_corruption_rejected(native, tmp_path, path):
    source, _, _ = native
    for relative in (CAPTURE, MAT, RECEIPT):
        destination = tmp_path / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, destination)
    with (tmp_path / path).open("ab") as stream:
        stream.write(b"tampered-negative-probe")
    with pytest.raises(AssertionError, match="Native artifact hash mismatch"):
        _native(tmp_path)


@pytest.mark.parametrize("field,value,reason", [
    ("RawEqualizedReal", "NaN", "nonfinite or missing"),
    ("SubcarrierIndex", "1", "native position key/domain"),
    ("SymbolCoordinateDomain", "layer_resource_elements", "native position key/domain"),
    ("SymbolOrderLinearIndex", "", "native position key/domain"),
])
def test_tampered_native_rows_cannot_be_repaired_into_a_cloud(native, field, value, reason):
    # Mutations of an original measured row are rejection probes only.
    row = dict(native[2][0])
    row[field] = value
    payload = io.StringIO(newline="")
    writer = csv.DictWriter(payload, fieldnames=list(row))
    writer.writeheader()
    writer.writerow(row)
    with pytest.raises(ValueError, match=reason):
        live.materializer._specialized_chart_materialization(
            CHART, {CAPTURE: {"artifact_id": 1}}, lambda _: payload.getvalue().encode(), "negative_probe")


def test_dft_native_positions_do_not_become_subcarrier_evm(native):
    source, _, _ = native
    result = live.materializer._specialized_chart_materialization(
        "EVM per subcarrier", {CAPTURE: {"artifact_id": 1}}, lambda _: (source / CAPTURE).read_bytes(),
        "native_DFT_component")
    assert result["csv_status"] == "unavailable_exact_reason"
    assert result["source_row_count"] == 0
