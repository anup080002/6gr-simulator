"""Exact metadata lookup equivalence; no fabricated PHY measurements."""
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as materializer


def reference(row, *names):
    """Uncached pre-optimization algorithm, including blank precedence."""
    blank_exact = None
    for name in names:
        if name in row:
            value = row.get(name)
            if materializer._nonblank_text(value):
                return value
            if blank_exact is None:
                blank_exact = value
    wanted = set(materializer._row_candidate_keys(*names))
    if not wanted:
        return blank_exact
    blank_alias = None
    for key, value in row.items():
        if materializer._normalized_row_key(key) in wanted:
            if materializer._nonblank_text(value):
                return value
            if blank_alias is None:
                blank_alias = value
    return blank_exact if blank_exact is not None else blank_alias


def test_randomized_exact_lookup_equivalence():
    rng = random.Random(20260922)
    fields = ["signal_family", "SignalFamily", "signal-family", "channel",
              "CellID", "cell_id", "BaseStationID", "slot", "SlotIndex",
              "RI", "Rank", "layers", "DMRSPort", "DMRS_Port", "unknown"]
    values = [None, "", " ", "nan", "NaN", "<missing>", "0", "1", "x", 0, False]
    for _ in range(500):
        rng.shuffle(fields)
        row = {key: rng.choice(values) for key in fields[:rng.randrange(16)]}
        for names in [(), ("signal_family",), ("cell_id", "CellID", "BaseStationID"),
                      ("RI", "Rank"), ("missing",), ("slot",)]:
            assert materializer._row_value(row, *names) == reference(row, *names)


def test_cache_does_not_retain_values_or_override_column_order():
    row = {"SLOT_INDEX": "4", "slot-index": "9"}
    assert materializer._row_value(row, "slot") == "4"
    row["SLOT_INDEX"] = "7"
    assert materializer._row_value(row, "slot") == "7"
    row["SLOT_INDEX"] = ""
    assert materializer._row_value(row, "slot") == "9"
    row["SLOT_INDEX"] = "7"
    row = dict(reversed(list(row.items())))
    assert materializer._row_value(row, "slot") == "9"
    del row["slot-index"]
    assert materializer._row_value(row, "slot") == "7"
    row["slot"] = "12"
    assert materializer._row_value(row, "slot") == "12"


def test_alias_changes_invalidate_the_lookup_key(monkeypatch):
    row = {"new_alias": "actual_row_value"}
    assert materializer._row_value(row, "test_key") is None
    monkeypatch.setitem(materializer._ROW_FIELD_ALIASES, "testkey", ("new_alias",))
    assert materializer._row_value(row, "test_key") == "actual_row_value"


def test_bounded_schema_cache_reuses_no_row_values():
    materializer._row_alias_columns.cache_clear()
    row = {f"column_{i}": str(i) for i in range(400)}
    row["SLOT_INDEX"] = "4"
    for i in range(100):
        row["SLOT_INDEX"] = str(i)
        assert materializer._row_value(row, "slot") == str(i)
        assert materializer._row_value(row, "absent_field") is None
    info = materializer._row_alias_columns.cache_info()
    assert info.misses == 2 and info.hits == 198 and info.maxsize == 256
