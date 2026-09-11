import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lls_beam_summary_audit import reconcile_beam_summary


def fixture():
    source = [dict(UEIndex="1", Slot="1", SSBIndex=str(i), BeamIndex=str(i+1),
                   SS_RSRP_dBm=str(p), ConfiguredSNR_dB="12", SNR_dB="35.7766",
                   PostEqSINR_dB=str(q), PostEqSINRValueRole="estimated_post_equalization")
              for i, p, q in [(0, -70, 51), (1, -80, 38)]]
    summary = dict(TraceSource="pbch.csv", UEIndex="1", Slot="1", SNR_dB="12",
                   SNR_dBValueRole="configured_operating_point_metadata",
                   Metric="P1SelectedSSBBeamIndex", MeanValue="0", QualityAxis="PostEqSINR_dB",
                   QualityMean_dB="51", QualitySampleCount="1",
                   QualityValueRole="estimated_post_equalization",
                   SelectionEvidenceRole="posthoc_measured_candidate_comparison_not_receiver_decision")
    return summary, {"pbch.csv": source}


def test_exact_observation_and_mutations():
    row, sources = fixture()
    assert not reconcile_beam_summary([row], sources)
    for field, value, signature in [
        ("MeanValue", "1", "incorrect_P1SelectedSSBBeamIndex"),
        ("UEIndex", "", "omitted_scope_UEIndex"),
        ("Slot", "21", "no_exact_source_scope"),
        ("QualityMean_dB", "12", "receiver_quality_distribution_mismatch"),
        ("QualityValueRole", "measured", "receiver_quality_role_relabelled"),
        ("SNR_dB", "36", "no_exact_source_scope"),
        ("SelectionEvidenceRole", "receiver_decision", "selection_authority_not_disclosed"),
    ]:
        bad = dict(row, **{field: value})
        assert any(signature in f for f in reconcile_beam_summary([bad], sources))


def test_unavailable_quality_is_not_source_snr():
    row, sources = fixture()
    for source in sources["pbch.csv"]:
        del source["PostEqSINR_dB"]
    row.update(QualityMean_dB="", QualitySampleCount="0")
    assert not reconcile_beam_summary([row], sources)
    row.update(QualityMean_dB="35.7766")
    assert any("invented_receiver_quality" in f for f in reconcile_beam_summary([row], sources))


def test_power_summary_and_producer_source():
    row, sources = fixture()
    row.update(Metric="P1SS_RSRP_dBm", MeanValue="-75", SampleCount="2",
               QualityMean_dB="44.5", QualitySampleCount="2", QualitySource="received_dmrs")
    for source in sources["pbch.csv"]:
        source["PostEqSINRSource"] = "received_dmrs"
    assert not reconcile_beam_summary([row], sources)
    row["MeanValue"] = "-5"
    assert any("observed_rsrp_summary_mismatch" in f for f in reconcile_beam_summary([row], sources))
    row["MeanValue"] = "-75"
    row["QualitySource"] = "configured_snr"
    assert any("receiver_quality_source_relabelled" in f for f in reconcile_beam_summary([row], sources))
