import csv
import hashlib
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from audit_lls_measurement_catalog import audit_packet_conservation


def write(root, name, rows):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return path


def fixture(root, *, count=0, duplicate=False, two_segments=False):
    owner = dict(Direction="DL", UEIndex=1, PacketId="same-local-id", ApplicationPacketId="app")
    packets = [dict(owner, OfferedBits=1000, ScheduledBits=400, RemainingBits=600, DeliveredBits=0,
                    HARQAttemptCount=count)]
    segment = dict(owner, TransportBlockId="TB", SegmentIndex=1, PayloadBits=400,
                   DeliveryEvidenceMode="CRC_CONFIRMED_PACKET_MAPPING")
    segments = [segment]
    if two_segments:
        segments = [dict(segment, PayloadBits=200), dict(segment, SegmentIndex=2, PayloadBits=200)]
    attempts = [dict(Direction="DL", UEIndex=1, TBId="TB", PHYGrantContextId="actual-attempt")]
    if duplicate:
        attempts *= 2
    paths = [write(root, "packet_flow/csv/live_application_packet_delivery_ledger.csv", packets),
             write(root, "packet_flow/csv/live_packet_sdu_delivery_ledger.csv", segments),
             write(root, "harq/csv/runtime_harq_process_timeline.csv", attempts)]
    return paths


def test_detects_unupdated_attempt_counter_without_fabricating_delivery(tmp_path):
    paths = fixture(tmp_path)
    hashes = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
    rows = audit_packet_conservation(tmp_path)
    failed = [row for row in rows if row["CheckStatus"].startswith("FAIL")]
    assert len(failed) == 1 and failed[0]["Metric"] == "HARQAttemptCount_vs_unique_executed_grants"
    assert failed[0]["Actual"] == 0 and failed[0]["Recomputed"] == 1
    assert rows[-1]["Metric"] == "ApplicationDeliveredBits_metadata_only_boundary"
    assert rows[-1]["Actual"] == rows[-1]["Recomputed"] == 0
    assert hashes == [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]


def test_counts_actual_attempt_once_not_once_per_fragment(tmp_path):
    fixture(tmp_path, count=1, two_segments=True)
    assert all(row["CheckStatus"].startswith("PASS") for row in audit_packet_conservation(tmp_path))


@pytest.mark.parametrize("missing", [False, True])
def test_missing_or_duplicate_attempt_evidence_is_not_zero_or_a_pass(tmp_path, missing):
    paths = fixture(tmp_path, duplicate=not missing)
    if missing:
        paths[-1].unlink()
    row = next(row for row in audit_packet_conservation(tmp_path) if row["Metric"].startswith("HARQAttemptCount"))
    assert row["CheckStatus"].startswith("NOT_EVALUATED") and row["Recomputed"] is None


def test_cross_ue_segment_is_not_joined_by_packet_label(tmp_path):
    paths = fixture(tmp_path)
    with paths[1].open(newline="") as stream:
        segments = list(csv.DictReader(stream))
    segments[0]["UEIndex"] = 2
    write(tmp_path, paths[1].relative_to(tmp_path), segments)
    with pytest.raises(ValueError, match="unmatched stable"):
        audit_packet_conservation(tmp_path)


def with_ranges(root):
    paths = fixture(root, count=1, two_segments=True)
    with paths[0].open(newline="") as stream:
        packets = list(csv.DictReader(stream))
    with paths[1].open(newline="") as stream:
        segments = list(csv.DictReader(stream))
    packets[0].update(BitConservationSchema="packet_bit_ranges/v1", UnscheduledBits=600,
                      ReservedInFlightBits=0, CRCConfirmedMappedBits=400,
                      BitVerifiedPendingReassemblyBits=0, CompletedApplicationBits=0,
                      HARQReleasedUndeliveredBits=0, UnresolvedReservedBits=0,
                      BitConservationErrorBits=0)
    for number, segment in enumerate(segments):
        segment.update(ApplicationRangeStartBit=200 * number, ApplicationRangeEndBitExclusive=200 * (number + 1),
                       PacketBitState="CRCConfirmedMappedBits")
    write(root, paths[0].relative_to(root), packets)
    write(root, paths[1].relative_to(root), segments)
    return paths, packets, segments


def test_reconciles_disjoint_range_exports_without_promoting_crc_to_application(tmp_path):
    with_ranges(tmp_path)
    rows = audit_packet_conservation(tmp_path)
    assert all(row["CheckStatus"].startswith("PASS") for row in rows)
    assert any(row["Metric"] == "CompletedApplicationBits_vs_owned_segment_ranges" and row["Actual"] == 0 for row in rows)


def test_detects_range_gap_even_when_payload_and_partition_totals_match(tmp_path):
    paths, _, segments = with_ranges(tmp_path)
    segments[1]["ApplicationRangeStartBit"] += 8
    segments[1]["ApplicationRangeEndBitExclusive"] += 8
    write(tmp_path, paths[1].relative_to(tmp_path), segments)
    rows = audit_packet_conservation(tmp_path)
    row = next(row for row in rows if row["Metric"] == "Application_ranges_disjoint_scheduled_prefix")
    assert row["CheckStatus"].startswith("FAIL")


def test_detects_misclassified_counter_even_when_whole_packet_total_matches(tmp_path):
    paths, packets, _ = with_ranges(tmp_path)
    packets[0]["CRCConfirmedMappedBits"] = 200
    packets[0]["CompletedApplicationBits"] = 200
    write(tmp_path, paths[0].relative_to(tmp_path), packets)
    failed = {row["Metric"] for row in audit_packet_conservation(tmp_path) if row["CheckStatus"].startswith("FAIL")}
    assert "CompletedApplicationBits_vs_delivered" in failed
    assert "CRCConfirmedMappedBits_vs_owned_segment_ranges" in failed
    assert "CompletedApplicationBits_vs_owned_segment_ranges" in failed
