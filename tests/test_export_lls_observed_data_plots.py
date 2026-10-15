"""CSV publication fixtures; these tests are not physical CSI qualification."""
import hashlib
import json
from pathlib import Path
import sys

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import export_lls_observed_data_plots as review


def test_component_review_preserves_explicit_source_and_does_not_claim_scenario_pass(tmp_path, monkeypatch):
    run, output = tmp_path / "component", tmp_path / "review"
    run.mkdir()
    payload = (b"Direction,SourceSlot,DeliveredSlot,DeliveryStatus,CRI,RI,SourceSignal,CSIUCIDecodeOk\n"
               b"DL,9,19,delivered,0,2,received_CSI_UCI,1\n")
    source = run / "received.csv"
    source.write_bytes(payload)
    monkeypatch.setattr(review, "CHARTS", ("CSI CRI timeline", "CSI RI timeline", "PDSCH EVM per symbol"))
    role = "air_interface/csv/received_csi_reports.csv"
    scope = "declared CSV fixture; no waveform execution"
    manifest = review.export_observed_plots(run, output,
        source_map={"evidence_scope": scope, "sources": {role: "received.csv"}})
    assert manifest["source_files"] == {role: "received.csv"}
    assert manifest["source_sha256"][role] == hashlib.sha256(payload).hexdigest()
    assert manifest["evidence_scope"] == scope and manifest["terminal_qualification"] is False
    assert source.read_bytes() == payload and len(list(run.iterdir())) == 1
    assert (output / "source_snapshot/received.csv").read_bytes() == payload
    for stem in ("csi_cri_timeline", "csi_ri_timeline"):
        with Image.open(output / f"{stem}.png") as png:
            assert "not full scenario acceptance" in png.info["sixgr_visual_semantics"]
            png.verify()
        assert (output / f"{stem}.csv").is_file()
    absent = next(row for row in manifest["outputs"] if row["chart_name"] == "PDSCH EVM per symbol")
    assert absent["status"] == "unavailable_exact_reason" and absent["artifacts"] == {}
    assert not (output / "pdsch_evm_per_symbol.png").exists()
    source.write_bytes(b"later component update")
    assert (output / "source_snapshot/received.csv").read_bytes() == payload
    saved = json.loads((output / "provenance.json").read_text(encoding="utf-8"))
    assert saved == manifest


@pytest.mark.parametrize("mapping,error", [
    ({"sources": {"air_interface/csv/received_csi_reports.csv": "received.csv"}}, ValueError),
    ({"evidence_scope": "fixture", "sources": {"unknown_role": "received.csv"}}, ValueError),
    ({"evidence_scope": "fixture", "sources": {"air_interface/csv/received_csi_reports.csv": "../outside.csv"}}, ValueError),
    ({"evidence_scope": "fixture", "sources": {"air_interface/csv/received_csi_reports.csv": "missing.csv"}}, FileNotFoundError),
])
def test_invalid_or_missing_explicit_sources_do_not_create_review(tmp_path, mapping, error):
    run, output = tmp_path / "run", tmp_path / "review"
    run.mkdir()
    with pytest.raises(error):
        review.export_observed_plots(run, output, source_map=mapping)
    assert not output.exists()
