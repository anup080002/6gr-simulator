"""Browser rank must come from executed trials, never capability or CSI RI."""
from unittest.mock import patch
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


def payload(dl, ul=()):
    def load(_artifacts, paths, **_kwargs):
        if paths[0] == "air_interface/csv/dl_pdsch_trials.csv":
            return [{"Slot": 41, "UEID": 1, **row} for row in dl]
        if paths[0] == "air_interface/csv/ul_pusch_trials.csv":
            return [{"Slot": 41, "UEID": 1, **row} for row in ul]
        return []
    with patch.object(dash, "load_first_available_csv_rows", side_effect=load):
        return dash.build_metric_explorer_payload([], {})


def test_executed_rank_and_allocation_are_visible():
    result = payload([dict(EffectiveLayers=2, Layers=2, EffectiveRank=2,
                          ConfiguredRank=4, RankIndicator=1, Goodput_Mbps=3.104,
                          AllocatedPRBCount=2, SymbolStart=2, NumSymbols=12)],
                     [dict(Layers=1)])
    row = result["rows"][0]
    assert row["dl_rank"] == 2 and row["dl_rank_display"] == "2"
    assert row["ul_rank"] == 1
    assert row["dl_prbs"] == 2 and row["dl_symbol_end"] == 13
    assert {"dl_rank", "ul_rank"} <= {m["id"] for m in result["available_metrics"]}


def test_no_capability_or_recommended_rank_substitution():
    for trial in [dict(ConfiguredRank=4, RankIndicator=2, RankEstimate=2, Rank=2),
                  dict(Layers=2, EffectiveLayers=1), dict(Layers=1.5),
                  dict(Layers=0), dict(Layers="NaN")]:
        row = payload([trial])["rows"][0]
        assert row["dl_rank"] is None
        assert row["dl_rank_display"] == "unavailable"


def test_multiple_trials_do_not_create_fractional_rank():
    row = payload([dict(Layers=1), dict(Layers=2)])["rows"][0]
    assert row["dl_rank"] is None
    assert row["dl_rank_display"] == "1 / 2 (multiple trials)"
    row = payload([dict(Layers=2), dict(ConfiguredRank=2)])["rows"][0]
    assert row["dl_rank"] is None
    assert row["dl_rank_display"] == "2 (partial evidence)"


def test_traffic_table_renders_rank_and_allocation():
    with patch.object(dash, "list_scenarios", return_value=["rank_display_test.yaml"]):
        source = dash.build_product_frontend_page(
            "realtime", "rank_display_test.yaml",
            user_profile={"username": "test", "role": "Administrator"},
        ).decode("utf-8")
    assert "'MCS','Rank / Layers','PRBs','Symbols'" in source
    assert "row.dl_rank_display" in source and "row.ul_rank_display" in source
