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


def normalized_fixture():
    row, sources = fixture()
    plane = "normalized_fixed_esn0_unit_occupied_re_es"
    axis = "SS_RSRP_dB_re_UnitOccupiedRE_Es"
    row.update(PowerReferencePlane=plane, ScoreAxis=axis)
    for source, power in zip(sources["pbch.csv"], [-6, -9]):
        source.update(PowerReferencePlane=plane, SS_RSRP_dBm="NaN")
        source[axis] = str(power)
    return row, sources


def test_normalized_winner_requires_its_exact_power_domain_and_score():
    row, sources = normalized_fixture()
    assert not reconcile_beam_summary([row], sources)
    row.update(Metric="P1SelectedSSBBeamScore", MeanValue="-6")
    assert not reconcile_beam_summary([row], sources)
    for field, value, signature in [
        ("MeanValue", "-9", "incorrect_P1SelectedSSBBeamScore"),
        ("ScoreAxis", "SS_RSRP_dBm", "score_axis_power_domain_mismatch"),
        ("PowerReferencePlane", "", "omitted_scope_PowerReferencePlane"),
    ]:
        assert any(signature in f for f in reconcile_beam_summary([dict(row, **{field: value})], sources))
    # Absolute powers may not rescue missing normalized receiver samples.
    for source in sources["pbch.csv"]:
        source["SS_RSRP_dBm"] = "100"
        source["SS_RSRP_dB_re_UnitOccupiedRE_Es"] = "NaN"
    assert any("winner_without_scored_physical_ssb" in f for f in reconcile_beam_summary([row], sources))


def test_power_planes_do_not_compete_for_the_same_winner():
    row, sources = normalized_fixture()
    absolute = dict(sources["pbch.csv"][0], PowerReferencePlane="receiver_antenna_connector_no_composite_front_end",
                    SS_RSRP_dBm="10", SS_RSRP_dB_re_UnitOccupiedRE_Es="100", SSBIndex="7")
    sources["pbch.csv"].append(absolute)
    assert not reconcile_beam_summary([row], sources)


def test_normalized_power_mean_is_recomputed_not_relabelled():
    row, sources = normalized_fixture()
    row.update(Metric="P1SS_RSRP_dB_re_UnitOccupiedRE_Es", MeanValue="-7.5",
               SampleCount="2", QualityMean_dB="44.5", QualitySampleCount="2")
    assert not reconcile_beam_summary([row], sources)
    row["MeanValue"] = "-75"
    assert any("observed_rsrp_summary_mismatch" in f for f in reconcile_beam_summary([row], sources))
    row.update(Metric="P1SS_RSRP_dBm", MeanValue="-7.5")
    assert any("rsrp_metric_power_domain_mismatch" in f for f in reconcile_beam_summary([row], sources))
