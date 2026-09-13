import csv
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lls_csv_semantics import DL_PROTOCOL_DECISIONS, _audit_dl_protocol_decisions


def fixture():
    row = dict(ContractVersion="received_dl_retained_ack/v1", UEId="1", RNTI="1", HARQProcess="2",
               NDI="1", ControlAbsoluteSlot="52", DataAbsoluteSlot="52", ReceivedAssignmentDigest="c" * 64,
               PriorAcknowledgedAssignmentDigest="b" * 64, PriorAcknowledgedDataAbsoluteSlot="42",
               InitialAssignmentDigest="a" * 64, RetainedTBSBits="1064", ACK="1", DecodeAttempted="0",
               DeliverTransportBlock="0", FeedbackTransmissionQualified="0",
               Source="received_dci_and_ue_retained_decoded_tb", ControlAvailableAtSample="52000",
               DecisionAvailableAtSample="53000", SampleRateHz="1000000", HARQFeedbackAbsoluteSlot="53",
               PUCCHResourceIndicator="0")
    first = dict(UEIndex="1", RNTI="1", HARQProcess="2", NDI="1", TBSize_bits="1064", Slot="33",
                 CRCPass="0", ReceivedAssignmentDigest="a" * 64, DataDecodeAvailableAtSample="33000")
    prior = dict(first, Slot="43", CRCPass="1", ReceivedAssignmentDigest="b" * 64,
                 DataDecodeAvailableAtSample="43000")
    return row, {"DL": [first, prior]}


def audit(root, rows, links):
    path = root / DL_PROTOCOL_DECISIONS
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    return _audit_dl_protocol_decisions(root, links)


def test_actual_decode_lineage_and_protocol_chain(tmp_path):
    row, links = fixture()
    second = dict(row, ReceivedAssignmentDigest="d" * 64, PriorAcknowledgedAssignmentDigest="c" * 64,
                  PriorAcknowledgedDataAbsoluteSlot="52", ControlAbsoluteSlot="62", DataAbsoluteSlot="62",
                  ControlAvailableAtSample="62000", DecisionAvailableAtSample="63000", HARQFeedbackAbsoluteSlot="63")
    assert all(c.passed for c in audit(tmp_path, [row, second], links))


@pytest.mark.parametrize("field,value", [("ACK", "0"), ("DecodeAttempted", "1"),
    ("DeliverTransportBlock", "1"), ("FeedbackTransmissionQualified", "1"), ("UEId", "2"),
    ("RetainedTBSBits", "1065"), ("ControlAvailableAtSample", "54000"), ("SampleRateHz", "0"),
    ("PriorAcknowledgedAssignmentDigest", "f" * 64), ("InitialAssignmentDigest", "f" * 64),
    ("ReceivedAssignmentDigest", "z" * 64), ("CRCPass", "1")])
def test_bad_protocol_or_identity_is_rejected(tmp_path, field, value):
    row, links = fixture()
    row[field] = value
    assert any(not c.passed for c in audit(tmp_path, [row], links))


def test_prior_NACK_cannot_support_ACK(tmp_path):
    row, links = fixture()
    links["DL"][1]["CRCPass"] = "0"
    assert any(not c.passed for c in audit(tmp_path, [row], links))


def test_protocol_cannot_also_be_a_decode_row(tmp_path):
    row, links = fixture()
    links["DL"].append(dict(links["DL"][1], ReceivedAssignmentDigest=row["ReceivedAssignmentDigest"]))
    assert any(not c.passed for c in audit(tmp_path, [row], links))


def test_missing_table_not_required_without_events(tmp_path):
    assert _audit_dl_protocol_decisions(tmp_path, {"DL": []}) == []
