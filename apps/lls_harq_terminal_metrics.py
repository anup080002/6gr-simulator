"""Unique-TB receiver outcomes joined to actual transmitter lifecycle events.

An observed ACK is never a data CRC. Unfinished/unknown TBs remain explicit;
the bounds below describe censoring, not statistical confidence intervals.
"""
import math
from collections import defaultdict


def _integer(row, name, minimum=0):
    value = float(row[name])
    if not math.isfinite(value) or value < minimum or value != int(value):
        raise ValueError(f"Invalid HARQ identity {name}: {row[name]}")
    return int(value)


def _crc(value):
    if value is None or str(value).strip().lower() in {"", "nan", "<missing>"}:
        return None
    token = str(value).strip().lower()
    if token in {"1", "1.0", "true"}:
        return True
    if token in {"0", "0.0", "false"}:
        return False
    raise ValueError(f"Invalid binary HARQ outcome: {value}")


def _key(row):
    direction = str(row["Direction"]).upper()
    tb = str(row["TBId"]).strip()
    if direction not in {"DL", "UL"} or not tb or tb.lower() in {"nan", "<missing>"}:
        raise ValueError("Missing canonical direction/TB identity")
    return (direction, _integer(row, "SweepPointIndex", 1),
            _integer(row, "RNTI", 1), tb)


def reconcile(lifecycle, decoder):
    """Return per-TB outcomes and per-direction/sweep summaries; no PHY replay."""
    tx, rx = defaultdict(list), {}
    for row in lifecycle:
        tx[_key(row)].append(row)
    for row in decoder:
        identity = (*_key(row), _integer(row, "Slot"))
        if identity in rx:
            raise ValueError("Duplicate receiver HARQ attempt")
        if identity[:-1] not in tx:
            raise ValueError("Receiver TB has no actual transmitter lifecycle evidence")
        rx[identity] = row
    packets = []
    consumed = set()
    for key, attempts in tx.items():
        attempts.sort(key=lambda row: _integer(row, "AttemptSlot"))
        slots = [_integer(row, "AttemptSlot") for row in attempts]
        if len(set(slots)) != len(slots):
            raise ValueError("Duplicate transmitted HARQ attempt")
        if [_integer(row, "AttemptIndex", 1) for row in attempts] != list(range(1, len(attempts)+1)):
            raise ValueError("Incomplete actual transmission history")
        if len({_integer(row, "Codeword") for row in attempts}) != 1:
            raise ValueError("Ambiguous codeword ownership for canonical TB")
        terminals = [_crc(row["TransmitterTerminal"]) for row in attempts]
        if any(value is None for value in terminals) or any(terminals[:-1]):
            raise ValueError("Unknown terminal state or transmission after terminal release")
        outcomes = []
        for slot in slots:
            identity = (*key, slot)
            observed = rx.get(identity)
            if observed is not None:
                consumed.add(identity)
            outcomes.append(None if observed is None else _crc(observed.get("CombinedDecodeOK")))
        delivered = any(value is True for value in outcomes)
        known = all(value is not None for value in outcomes)
        failed = bool(terminals[-1] and known and not delivered)
        unresolved = not delivered and not failed
        points = {float(row["ConfiguredSNR_dB"]) for row in attempts}
        if len(points) != 1 or not all(math.isfinite(value) for value in points):
            raise ValueError("Fixed-SNR TB history has inconsistent operating-point identity")
        first = rx.get((*key, slots[0]))
        initial = None if first is None else _crc(first.get("CurrentDecodeOK"))
        packets.append(dict(Direction=key[0], SweepPointIndex=key[1], RNTI=key[2],
            TBId=key[3], ConfiguredSNR_dB=next(iter(points)),
            HARQProcessId=_integer(attempts[0], "HARQProcessId"),
            TransmittedAttempts=len(attempts), ReceiverObservedAttempts=sum(v is not None for v in outcomes),
            TransmitterTerminal=bool(terminals[-1]), ReceiverDelivered=delivered,
            TerminalReceiverFailure=failed, Unresolved=unresolved,
            RightCensored=bool(unresolved and not terminals[-1]),
            ReceiverOutcomeMissing=bool(unresolved and terminals[-1]),
            InitialDecodeObserved=initial is not None,
            InitialDecodeFailed=initial is False))
    if set(rx) != consumed:
        raise ValueError("Receiver attempt has no matching actual transmission slot")
    groups = defaultdict(list)
    for row in packets:
        groups[(row["Direction"], row["SweepPointIndex"], row["ConfiguredSNR_dB"])].append(row)
    summaries = []
    for (direction, point, snr), rows in sorted(groups.items()):
        count = len(rows)
        failures = sum(row["TerminalReceiverFailure"] for row in rows)
        unresolved = sum(row["Unresolved"] for row in rows)
        initial_observed = sum(row["InitialDecodeObserved"] for row in rows)
        initial_failures = sum(row["InitialDecodeFailed"] for row in rows)
        summaries.append(dict(Direction=direction, SweepPointIndex=point, ConfiguredSNR_dB=snr,
            TransmittedTBCount=count, ReceiverDeliveredTBCount=sum(row["ReceiverDelivered"] for row in rows),
            TerminalReceiverFailureCount=failures, UnresolvedTBCount=unresolved,
            RightCensoredTBCount=sum(row["RightCensored"] for row in rows),
            ReceiverOutcomeMissingTBCount=sum(row["ReceiverOutcomeMissing"] for row in rows),
            ResidualBLER=failures/count if not unresolved else math.nan,
            ResidualBLERLowerBound=failures/count,
            ResidualBLERUpperBound=(failures+unresolved)/count,
            InitialObservedTBCount=initial_observed, InitialFailureCount=initial_failures,
            InitialBLER=initial_failures/count if initial_observed == count else math.nan,
            BoundMeaning="unresolved_outcome_bounds_not_confidence_intervals"))
    return packets, summaries
