"""Independent scalar-TB vector arithmetic, not a waveform qualification."""
import csv
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parent / "vectors" / "pucch"


def read_rows(name):
    with (ROOT / name).open(newline="", encoding="utf-8-sig") as stream:
        return list(csv.DictReader(stream))


CASES = [row for row in read_rows("pucch_harq_codebook_test_vectors.csv")
         if row["CodebookType"] == "TYPE2_DYNAMIC"]
EXPECTED = {row["CaseID"]: row for row in read_rows("expected_pucch_harq_codebook.csv")}


def independent_layout(events):
    # This legacy vector contract uses EventIndex as chronological pair ordinal.
    events = sorted(events, key=lambda event: event["EventIndex"])
    assert len({event["Priority"] for event in events}) <= 1
    tokens, owners, cursor = [], [], 0
    for event in events:
        assert type(event["DAI"]) is int and 1 <= event["DAI"] <= 4
        delta = (event["DAI"] - cursor % 4 - 1) % 4 + 1
        tokens.extend("0" * (delta - 1))
        owners.extend([""] * (delta - 1))
        tokens.append({"ACK": "1", "NACK": "0", "DTX": "D"}[event["State"]])
        owners.append(event["PDSCHID"])
        cursor += delta
    return "".join(tokens), "|".join(owners)


@pytest.mark.parametrize("row", CASES, ids=lambda row: row["CaseID"])
def test_independent_type2_vector(row):
    events = json.loads(row["EventsJSON"])
    tokens, owners = independent_layout(events)
    expected = EXPECTED[row["CaseID"]]
    assert tokens == expected["ExpectedBitTokens"]
    assert len(tokens) == int(expected["ExpectedBitCount"])
    assert owners == expected["ExpectedEventOrder"]
    assert tokens.count("D") == int(expected["DTXCount"])
    assert independent_layout(list(reversed(events))) == (tokens, owners)


def test_literal_leading_gap_and_wrap():
    events = [dict(EventIndex=1, DAI=1, State="DTX", PDSCHID="B", Priority=0),
              dict(EventIndex=0, DAI=3, State="ACK", PDSCHID="A", Priority=0)]
    assert independent_layout(events) == ("0010D", "||A||B")


def test_mixed_priority_rejected():
    events = json.loads(CASES[1]["EventsJSON"])
    events[1]["Priority"] = 1
    with pytest.raises(AssertionError):
        independent_layout(events)
