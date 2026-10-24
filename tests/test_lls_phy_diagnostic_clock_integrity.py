"""Declared publication fixtures; no waveform/performance qualification."""
import csv
import hashlib
import io
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m

PATH = "reports/csv/phy_signal_diagnostic_source.csv"
EXISTING = {PATH: {"artifact_id": 1}}


def fixture(**updates):
    row = dict(SnapshotID="declared_clock_fixture", Direction="DL", Frame=777,
        Slot=1, UEIndex=1, RNTI=4660, TBId="declared_tb", CellID=1,
        Status="available", truth_status="real_lls_evidence",
        CurveConstruction="runtime_same_trial_phy_signal_snapshot",
        SourceArtifact="runtime_phy_arrays_same_trial", SFN=0, CarrierNFrame=0,
        CarrierNSlot=0, SCS_kHz=30, SlotsPerFrame=20, AbsoluteSlot=0,
        RuntimeAbsoluteSlotIndex0=0, SFNSource="executed_nrCarrierConfig_NFrame_mod1024",
        AbsoluteSlotSource="executed_runtime_absolute_slot_index0",
        AbsoluteSlotConvention="zero_based_absolute_slot", SlotConvention="one_based_absolute_slot",
        Panel="time_domain", Series="tx", SampleIndex=1, XValue=0, IValue=0.25, QValue=-0.5,
        Notes='quoted, "metadata"\nnot another record')
    row.update(updates)
    return row


def payload(rows):
    return m._encode_dict_rows(list(dict.fromkeys(k for r in rows for k in r)), rows)


def chart(rows):
    data = payload(rows)
    before = hashlib.sha256(data).hexdigest()
    result = m._runtime_phy_signal_diagnostic_chart("Tx waveform", EXISTING, lambda _: data, 3)
    assert hashlib.sha256(data).hexdigest() == before
    return result, list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))


@pytest.mark.parametrize("absolute", [0, 20479, 20480])
def test_native_clock_wrap_and_trial_ordinal_are_independent(absolute):
    row = fixture(SFN=(absolute // 20) % 1024, CarrierNFrame=(absolute // 20) % 1024,
                  CarrierNSlot=absolute % 20, AbsoluteSlot=absolute,
                  RuntimeAbsoluteSlotIndex0=absolute, Slot=absolute+1)
    _, plotted = chart([row])
    assert plotted[0]["radio_clock_status"] == "consistent"
    assert plotted[0]["absolute_slot"] == str(absolute)
    assert plotted[0]["sfn"] == str(row["SFN"])
    assert row["Frame"] == 777


def test_native_nslot_may_exceed_frame_without_inventing_epoch():
    _, plotted = chart([fixture(SCS_kHz=15, SlotsPerFrame=10, CarrierNSlot=15,
        AbsoluteSlot=5, RuntimeAbsoluteSlotIndex0=5, Slot=6)])
    assert plotted[0]["radio_clock_status"] == "consistent"


@pytest.mark.parametrize("updates,status", [
    ({"AbsoluteSlotSource": "unknown"}, "unavailable"),
    ({"SFN": 1}, "conflict"),
    ({"SFN": "bad"}, "invalid"),
    ({"AbsoluteSlot": "9007199254740993"}, "invalid"),
    ({"SlotsPerFrame": "", "CarrierNSlot": 1}, "conflict"),
    ({"SFN": "", "CarrierNFrame": 1}, "conflict"),
    ({"AbsoluteSlotConvention": "one_based_absolute_slot"}, "invalid"),
])
def test_clock_defect_does_not_fabricate_or_discard_capture_samples(updates, status):
    source = fixture(**updates)
    _, plotted = chart([source])
    assert plotted[0]["radio_clock_status"] == status
    assert float(plotted[0]["i_value"]) == .25 and float(plotted[0]["q_value"]) == -.5
    assert plotted[0]["sfn"] == str(source["SFN"])
    assert plotted[0]["absolute_slot"] == str(source["AbsoluteSlot"])


def test_legacy_sample_evidence_is_not_a_radio_clock_certificate():
    source = fixture(SFN=1, AbsoluteSlot=16, SCS_kHz=15, SlotsPerFrame=10)
    for k in ("CarrierNFrame", "CarrierNSlot", "RuntimeAbsoluteSlotIndex0", *m._DIAGNOSTIC_CLOCK_TEXT):
        source.pop(k)
    _, plotted = chart([source])
    assert plotted[0]["radio_clock_status"] == "unavailable"
    assert plotted[0]["sfn"] == "1" and plotted[0]["absolute_slot"] == "16"
    assert "not_PHY_qualification" in plotted[0]["radio_clock_scope"]


@pytest.mark.parametrize("field,value", [
    ("truth_status", "proxy"), ("CurveConstruction", "synthetic"),
    ("SourceArtifact", "fallback"), ("Status", "unavailable"),
    ("Direction", "SIDEWAYS"), ("SnapshotID", ""), ("TBId", "different"),
])
def test_final_unselected_row_corruption_rejected_after_8192(tmp_path, field, value):
    path = tmp_path / "source.csv"
    rows = [fixture(SampleIndex=k+1, XValue=k/122880000) for k in range(9007)]
    rows[-1].update(Panel="channel_estimate", **{field: value})
    path.write_bytes(payload(rows))
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    def fetch(_):
        raise AssertionError("Streaming opener required")
    fetch.open_artifact_binary = lambda _: path.open("rb")
    with pytest.raises(ValueError, match="PHY diagnostic"):
        m._runtime_phy_signal_diagnostic_chart("Tx waveform", EXISTING, fetch, 3)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == before


def test_complementary_partial_clock_claims_cannot_hide_conflict():
    first = fixture(AbsoluteSlot="", RuntimeAbsoluteSlotIndex0="", SlotConvention="independent_trial_index")
    second = fixture(SFN="", CarrierNFrame="", AbsoluteSlot=20,
                     RuntimeAbsoluteSlotIndex0=20, SlotConvention="independent_trial_index")
    assert m._diagnostic_clock_claim(first)[2] == "unavailable"
    assert m._diagnostic_clock_claim(second)[2] == "unavailable"
    _, plotted = chart([first, second])
    assert {r["radio_clock_status"] for r in plotted} == {"conflict"}


def test_multiple_directions_same_snapshot_are_not_merged_in_heatmap():
    rows = []
    for direction in ("DL", "UL"):
        row = fixture(Direction=direction, Panel="channel_estimate_grid", Series="receiver_hest_exact_tensor",
            RxPortIndex0Based=0, TxPortIndex0Based=0, SubcarrierIndex=0, OFDMSymbolIndex=0,
            Magnitude_dB=-3, Phase_deg=0, GridSHA256="declared_grid")
        rows.append(row)
    result = m._runtime_phy_signal_diagnostic_chart("channel magnitude heatmap", EXISTING, lambda _: payload(rows), 3)
    plotted = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(plotted) == 1 and plotted[0]["direction"] == "DL"
    assert plotted[0]["radio_clock_status"] == "consistent"


def test_spectrum_keeps_capture_identity_without_claiming_unknown_radio_clock():
    rows = [fixture(Panel="spectrum", XValue=k*15000, YValue=-20+k, AbsoluteSlotSource="legacy")
            for k in range(4)]
    result = m._runtime_spectral_chart("PSD", EXISTING, lambda _: payload(rows), 3)
    plotted = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(plotted)==4 and {r["radio_clock_status"] for r in plotted} == {"unavailable"}
    assert {r["snapshot_id"] for r in plotted} == {"declared_clock_fixture"}
    assert [float(r["relative_spectral_level_db"]) for r in plotted] == [-20,-19,-18,-17]
