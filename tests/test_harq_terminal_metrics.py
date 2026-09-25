"""Declared event fixtures; do not qualify waveform receiver performance."""
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from lls_harq_terminal_metrics import reconcile


def events(crcs, terminal=True, ack=False, tb="tb", point=1):
    tx, rx = [], []
    for index, crc in enumerate(crcs, 1):
        common = dict(Direction="DL", SweepPointIndex=point, RNTI=321, TBId=tb)
        tx.append(dict(**common, ConfiguredSNR_dB=-10, Codeword=0, HARQProcessId=0,
            AttemptIndex=index, AttemptSlot=index*4, TransmitterTerminal=terminal and index==len(crcs),
            FeedbackAck=ack))
        rx.append(dict(**common, Slot=index*4, CurrentDecodeOK=crc, CombinedDecodeOK=crc))
    return tx, rx


@pytest.mark.parametrize("ack", [False, True])
def test_terminal_false_ack_is_not_receiver_delivery(ack):
    packets, summary = reconcile(*events([False, False], ack=ack))
    assert not packets[0]["ReceiverDelivered"]
    assert summary[0]["ResidualBLER"] == 1
    assert summary[0]["TransmittedTBCount"] == 1


def test_receiver_success_survives_false_nack_and_retry_limit_release():
    packets, summary = reconcile(*events([True, False, False], ack=False))
    assert packets[0]["ReceiverDelivered"]
    assert summary[0]["ResidualBLER"] == 0
    assert summary[0]["InitialBLER"] == 0


def test_first_attempt_and_residual_populations_are_distinct():
    _, summary = reconcile(*events([False, True]))
    assert summary[0]["InitialBLER"] == 1
    assert summary[0]["ResidualBLER"] == 0


def test_pending_is_not_terminal_failure():
    packets, summary = reconcile(*events([False], terminal=False))
    assert packets[0]["RightCensored"]
    assert math.isnan(summary[0]["ResidualBLER"])
    assert summary[0]["ResidualBLERLowerBound"] == 0
    assert summary[0]["ResidualBLERUpperBound"] == 1


def test_terminal_missing_receiver_is_unknown_not_success_or_failure():
    tx, _ = events([False], ack=True)
    packets, summary = reconcile(tx, [])
    assert packets[0]["ReceiverOutcomeMissing"]
    assert not packets[0]["TerminalReceiverFailure"]
    assert math.isnan(summary[0]["ResidualBLER"])
    assert math.isnan(summary[0]["InitialBLER"])


def test_four_dropped_and_three_pending_blocks_have_bounds_not_fabricated_rate():
    tx, rx = [], []
    for number in range(7):
        a, b = events([False]*4 if number<4 else [False], terminal=number<4, tb=str(number))
        tx.extend(a); rx.extend(b)
    _, summary = reconcile(tx, rx)
    s = summary[0]
    assert s["TransmittedTBCount"] == 7 and s["RightCensoredTBCount"] == 3
    assert math.isnan(s["ResidualBLER"]) and s["ResidualBLERLowerBound"] == 4/7
    assert s["ResidualBLERUpperBound"] == 1


def test_same_tb_identity_is_separate_across_sweep_points():
    a, b = events([False], point=1)
    c, d = events([True], point=2)
    _, summaries = reconcile(a+c, b+d)
    assert [row["ResidualBLER"] for row in summaries] == [1, 0]


@pytest.mark.parametrize("mutation", ["duplicate_tx", "duplicate_rx", "orphan_rx", "gap", "after_terminal", "codeword"])
def test_contradictory_or_incomplete_identity_is_rejected(mutation):
    tx, rx = events([False, True])
    if mutation=="duplicate_tx": tx.append(dict(tx[0]))
    if mutation=="duplicate_rx": rx.append(dict(rx[0]))
    if mutation=="orphan_rx": rx[0]["TBId"]="other"
    if mutation=="gap": tx[1]["AttemptIndex"]=3
    if mutation=="after_terminal": tx[0]["TransmitterTerminal"]=True
    if mutation=="codeword": tx[1]["Codeword"]=1
    with pytest.raises(ValueError): reconcile(tx, rx)
