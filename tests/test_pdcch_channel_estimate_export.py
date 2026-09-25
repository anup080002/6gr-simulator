import csv
import io
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
import lls_output_contract as contract


def source(rows):
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
    return {"control/csv/pdcch_channel_estimates.csv": {"artifact_id": 1}}, lambda _: buffer.getvalue().encode()


def samples():
    return [dict(HReal=0, HImag=port + 1, Magnitude=port + 1, Phase_rad=math.pi / 2,
                 SubcarrierIndex0=k, SymbolIndex0=0, RxPortIndex0=port, ReferencePortIndex0=0,
                 AbsoluteSlot0=slot, ObservationStartSample=slot * 7680,
                 ObservationEndSampleExclusive=(slot + 1) * 7680, CandidateIndex=1,
                 SNR_dB=20, UEIndex=1, ServingCell=1, GrantDirection="DL", ReceiverAccepted=slot == 10,
                 ChannelEstimateSource="nrChannelEstimate", ChannelEstimateMethod="LS")
            for slot in [10, 11] for port in [0, 1] for k in [1, 5, 9]]


@pytest.mark.parametrize("kind", ["magnitude", "phase"])
def test_complex_samples_and_failed_decode_survive_export(kind, monkeypatch):
    rows = samples()
    existing, fetch = source(rows)
    observed = {}

    def render(title, subtitle, series, summary, **kwargs):
        observed["series"] = series
        return b"<svg/>"

    monkeypatch.setattr(m, "_render_multi_series_svg", render)
    result = m._pdcch_control_chart_materialization(f"PDCCH channel-estimate {kind}", existing, fetch, 1)
    exported = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(exported) == len(rows) == 12
    assert sum(row["preview_selected"] == "True" for row in exported) == 6
    assert len(observed["series"]) == 2
    for series in observed["series"]:
        assert "slot0=11" in series["name"] and "accepted=0" in series["name"]
        expected = math.pi / 2 if kind == "phase" else (1 if "Rx=0" in series["name"] else 2)
        assert series["points"] == [[k, expected] for k in [1, 5, 9]]


@pytest.mark.parametrize("field,value", [("HReal", "nan"), ("Magnitude", 42),
                                        ("RxPortIndex0", 0.5), ("ChannelEstimateSource", "")])
def test_invalid_capture_is_not_replaced(field, value):
    rows = samples()
    rows[0][field] = value
    existing, fetch = source(rows)
    with pytest.raises(ValueError, match="PDCCH channel-estimate"):
        m._pdcch_control_chart_materialization("PDCCH channel-estimate magnitude", existing, fetch, 1)


def test_missing_capture_has_no_aggregate_fallback():
    with pytest.raises(ValueError, match="retain actual receiver Hest"):
        m._pdcch_control_chart_materialization("PDCCH channel-estimate phase", {}, lambda _: b"", 1)


def test_phase_branch_cut_does_not_reject_equivalent_phase():
    rows = samples()
    rows[0].update(HReal=-1, HImag=0, Magnitude=1, Phase_rad=-math.pi)
    existing, fetch = source(rows)
    result = m._pdcch_control_chart_materialization("PDCCH channel-estimate phase", existing, fetch, 1)
    png = m._rasterize_contract_png(result["img_bytes"])
    assert png.startswith(b"\x89PNG\r\n\x1a\n")


def test_browser_contract_registers_both_channels():
    spec = next(s for s in contract.REPORT_SECTIONS if s["slug"] == "dl-control-phy-pdcch")
    assert "PDCCH channel-estimate magnitude" in spec["charts"]
    assert "PDCCH channel-estimate phase" in spec["charts"]
