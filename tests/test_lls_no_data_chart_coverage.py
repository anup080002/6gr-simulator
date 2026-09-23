"""Publisher fixtures, not physical-link or statistical qualification."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def evidence():
    return {
        "reports/csv/run_state.csv": b"CanonicalSlotsPerSweepPoint,CurrentCanonicalSlot,DLGrantRows,ULGrantRows\n2,2,0,0\n",
        "reports/csv/slot_trace.csv": b"CanonicalSlot,SweepPointIndex,DLGrantCount,ULGrantCount,DLExecutedGrantCount,ULExecutedGrantCount,DLTrialRows,ULTrialRows\n1,1,0,0,0,0,0,0\n2,1,0,0,0,0,0,0\n",
        "air_interface/csv/pbch_trials.csv": b"CRCPass,Crash,SSBIdentityVerified,SelectedBeamFlag\n0,0,0,0\n",
        "air_interface/csv/dl_pdsch_trials.csv": b"Slot,CRCPass\n",
        "air_interface/csv/ul_pusch_trials.csv": b"Slot,CRCPass\n",
    }


def coverage(monkeypatch, sources):
    names = {"post-equalization constellation", "PDSCH BLER vs measured SINR",
             "Tx waveform", "PUCCH BLER vs measured SINR"}
    specs = [spec for spec in m._chart_specs() if spec["chart_name"] in names]
    assert len(specs) == 4
    monkeypatch.setattr(m, "_chart_specs", lambda: specs)
    monkeypatch.setattr(m, "_table_specs", lambda: [])
    payloads = dict(enumerate(sources.values(), 1))
    artifacts = [dict(logical_path=path, artifact_id=index)
                 for index, path in enumerate(sources, 1)]
    return m.coverage_summary(artifacts, {"constellation_capture_enabled": True,
                                         "raw_iq_capture_enabled": True, "pucch_enabled": True},
                              fetch_artifact_bytes=payloads.__getitem__)


def test_no_attempt_charts_are_unavailable_not_generated_or_policy_disabled(monkeypatch):
    result = coverage(monkeypatch, evidence())
    assert result["charts_unavailable"] == 2
    assert result["charts_available"] == result["charts_policy_disabled"] == 0
    assert set(result["missing_chart_names"]) == {"Tx waveform", "PUCCH BLER vs measured SINR"}
    assert set(result["unavailable_chart_names"]) == {"post-equalization constellation", "PDSCH BLER vs measured SINR"}
    assert result["charts_total"] == (result["charts_available"] + result["charts_policy_disabled"]
                                      + result["charts_unavailable"] + len(result["missing_chart_names"]))
    assert len(result["unavailable_chart_source_paths"]) == 5


@pytest.mark.parametrize("path,replacement", [
    ("air_interface/csv/dl_pdsch_trials.csv", None),
    ("air_interface/csv/ul_pusch_trials.csv", b""),
    ("air_interface/csv/ul_pusch_trials.csv", b"Slot\n"),
    ("air_interface/csv/dl_pdsch_trials.csv", b"Slot,CRCPass\n1,0\n"),
    ("air_interface/csv/pbch_trials.csv", b"CRCPass,Crash,SSBIdentityVerified,SelectedBeamFlag\n0,1,0,0\n"),
    ("air_interface/csv/pbch_trials.csv", b"CRCPass,Crash,SSBIdentityVerified,SelectedBeamFlag\n1,0,1,1\n"),
    ("reports/csv/run_state.csv", b"CanonicalSlotsPerSweepPoint,CurrentCanonicalSlot,DLGrantRows,ULGrantRows\n2,1,0,0\n"),
    ("reports/csv/run_state.csv", b"CanonicalSlotsPerSweepPoint,CurrentCanonicalSlot,DLGrantRows,ULGrantRows\n2,2,1,0\n"),
    ("reports/csv/slot_trace.csv", None),
])
def test_missing_or_contradictory_evidence_keeps_all_chart_requirements(monkeypatch, path, replacement):
    sources = evidence()
    if replacement is None:
        sources.pop(path)
    else:
        sources[path] = replacement
    result = coverage(monkeypatch, sources)
    assert result["charts_unavailable"] == 0
    assert len(result["missing_chart_names"]) == 4


def test_no_reader_cannot_turn_absence_into_unavailability():
    result = m.coverage_summary([dict(logical_path=path, artifact_id=index)
                                 for index, path in enumerate(evidence(), 1)])
    assert result["charts_unavailable"] == 0


def test_existing_chart_from_nonexistent_attempts_is_not_accepted(monkeypatch):
    spec = next(spec for spec in m._chart_specs()
                if spec["chart_name"] == "post-equalization constellation")
    sources = evidence()
    sources[m.chart_contract_csv_path(spec)] = b"Real,Imag\n1,1\n"
    sources[m.chart_contract_image_path(spec)] = b"unverified stale image"
    result = coverage(monkeypatch, sources)
    assert "post-equalization constellation" in result["missing_chart_names"]
    assert "post-equalization constellation" not in result["unavailable_chart_names"]
    assert result["charts_available"] == 0


def test_contradictory_constellation_rows_are_not_hidden(monkeypatch):
    sources = evidence()
    sources["air_interface/csv/dl_constellation_samples.csv"] = b"Real,Imag\n1,1\n"
    result = coverage(monkeypatch, sources)
    assert result["charts_unavailable"] == 0
    assert len(result["missing_chart_names"]) == 4


def test_filesystem_materialization_records_absence_without_numeric_rows_or_png(monkeypatch, tmp_path):
    names = {"post-equalization constellation", "PDSCH BLER vs measured SINR"}
    specs = [spec for spec in m._chart_specs() if spec["chart_name"] in names]
    monkeypatch.setattr(m, "_chart_specs", lambda: specs)
    monkeypatch.setattr(m, "_table_specs", lambda: [])
    artifacts = []
    for index, (path, payload) in enumerate(evidence().items(), 1):
        target = tmp_path / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        artifacts.append(dict(logical_path=path, filesystem_path=str(target),
                              artifact_id=index, artifact_kind="table_csv", byte_size=len(payload),
                              metadata_json="{}"))
    before = {path: (tmp_path / path).read_bytes() for path in evidence()}
    policy = {"constellation_capture_enabled": True}
    result = m.materialize_filesystem_run_contract_artifacts(
        dict(run_id=1, run_folder=str(tmp_path), status_text="failed"), artifacts,
        feature_policy=policy)
    assert result["coverage"]["charts_unavailable"] == 2
    assert result["coverage"]["charts_available"] == 0
    assert not result["coverage"]["missing_chart_names"]
    assert not list(tmp_path.rglob("*.png"))
    for spec in specs:
        assert not (tmp_path / m.chart_contract_csv_path(spec)).exists()
    assert before == {path: (tmp_path / path).read_bytes() for path in before}
    _, rows = m._decode_csv_dicts((tmp_path / m.coverage_logical_path()).read_bytes())
    assert rows[0]["charts_unavailable"] == "2" and rows[0]["charts_available"] == "0"
    assert b"unavailable_no_data_attempts" in (tmp_path / m.manifest_logical_path()).read_bytes()
    assert m.coverage_summary(artifacts, policy)["charts_unavailable"] == 2
