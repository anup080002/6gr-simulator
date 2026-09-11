"""Read-only consistency audit of retained SSB occasion evidence, not NR qualification.

No inference of missing reception, no replacement of primary measurements.
RSSI arithmetic applies only to the explicitly retained SSB window, not a
full-carrier or SMTC measurement. Input is one atomically published CSV.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path


def number(value):
    try:
        value = float(value)
        return value if math.isfinite(value) else None
    except (ValueError, TypeError):
        return None


def vector(value):
    return value if isinstance(value, list) else [value]


def close(a, b):
    return number(a) is not None and number(b) is not None and math.isclose(
        float(a), float(b), rel_tol=0, abs_tol=1e-8)


def audit_rows(rows, slot_duration_s):
    if not math.isfinite(slot_duration_s) or slot_duration_s <= 0:
        raise ValueError("Actual configured slot duration must be positive and finite.")
    checks, observed, seen = [], 0, set()
    for index, row in enumerate(rows):
        if row.get("MeasurementSource") != "actual_shared_ssb_occasion_pre_rx_rf_measurement":
            continue
        observed += 1

        def check(name, passed, detail):
            checks.append(dict(CSVRow=index + 2, MeasurementId=row.get("MeasurementId", ""),
                               Check=name, Passed=bool(passed), Detail=detail))

        key = tuple(row.get(name, "") for name in (
            "TargetId", "ServingCell", "BurstSlot", "ResourceId"))
        check("unique_ssb_occasion", key not in seen, "One retained measurement per UE/cell/burst/SSB.")
        seen.add(key)
        start, end, fs, producer, available = [number(row.get(name)) for name in (
            "ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz",
            "ProducerSlot", "AvailableSlot")]
        clock_ok = all(value is not None for value in (start, end, fs, producer, available))
        clock_ok = clock_ok and fs > 0 and 0 <= start < end and producer >= 1 and available >= producer
        clock_ok = clock_ok and all(value == int(value) for value in (start, end, producer, available))
        check("sample_clock_fields", clock_ok, "Integer samples and one-based actual slot coordinates required.")
        if clock_ok:
            # A sub-sample rounding tolerance only; never permit a future sample.
            delivery_sample = (available - 1) * slot_duration_s * fs
            check("no_future_observation", end <= delivery_sample + 1e-6,
                  f"Observation ends at sample {end}; delivery slot starts at {delivery_sample}.")
        if str(row.get("Valid", "")).lower() in ("1", "true"):
            check("valid_serving_identity", number(row.get("MeasuredNCellID")) is not None and
                  number(row.get("MeasuredNCellID")) == number(row.get("ExpectedNCellID")),
                  "Valid serving measurement must match decoded serving PCI.")
            check("valid_rsrp_available", number(row.get("RSRP_dBm")) is not None,
                  "Valid measurement requires actual finite RSRP; no field-range clamp.")
        # BCH decode status is deliberately not used to redefine measurement validity.
        payload = row.get("SSBWindowPowerMeasurementJSON", "")
        if not payload or payload.lower() == "nan":
            check("window_power_evidence", False, "This occasion has no retained RSSI power evidence.")
            continue
        try:
            data = json.loads(payload)
            if not isinstance(data, dict):
                raise ValueError("Expected a JSON object.")
            check("ssb_window_scope", data.get("Scope") ==
                  "ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI" and
                  data.get("AmplitudeUnit") == "sqrt_W" and data.get("CPIncluded") is False,
                  "Only the declared useful-symbol, physical-power SSB window is audited.")
            count = number(data.get("NumReceiveAntennas"))
            if count is None or count < 1 or count != int(count):
                raise ValueError("Invalid receive antenna count.")
            count = int(count)
            powers = [vector(item) for item in data["SymbolPowerPerAntenna_W"]]
            rssi = vector(data["RSSIPerAntenna_dBm"])
            rsrp = vector(data["ReferenceRSRPPerAntenna_dBm"])
            rsrq = vector(data["ReferenceRSRQPerAntenna_dB"])
            tokens = str(row["SSBWindowRSSIPerReceiveAntenna_dBm"]).split("|")
            dimensions = len(powers) == 4 and all(len(item) == count for item in powers)
            dimensions = dimensions and all(len(item) == count for item in (rssi, rsrp, rsrq, tokens))
            check("per_antenna_dimensions", dimensions, "Four useful SSB symbols by declared receive antennas.")
            if not dimensions:
                continue
            rb = number(data.get("NumRB"))
            if rb is None or rb <= 0:
                raise ValueError("Invalid measured resource-block count.")
            for ant in range(count):
                values = [number(item[ant]) for item in powers]
                usable = all(value is not None and value >= 0 for value in values)
                mean_w = sum(values) / len(values) if usable else 0
                check(f"antenna_{ant}_rssi_power_closure", mean_w > 0 and
                      close(rssi[ant], 10 * math.log10(mean_w) + 30) if mean_w > 0 else False,
                      "RSSI is 10*log10(mean symbol power in W)+30 dBm.")
                check(f"antenna_{ant}_rssi_csv_closure", close(rssi[ant], tokens[ant]),
                      "CSV antenna token must equal the retained JSON power result.")
                usable_ratio = number(rsrp[ant]) is not None and number(rssi[ant]) is not None
                check(f"antenna_{ant}_window_rsrq_closure", usable_ratio and close(
                    rsrq[ant], 10 * math.log10(rb) + float(rsrp[ant]) - float(rssi[ant])),
                    "Window RSRQ uses its own SSS/PBCH-DMRS reference, not serving SSS-only RSRP.")
        except (KeyError, ValueError, TypeError, OverflowError) as error:
            check("window_power_payload_schema", False, str(error))
    return dict(ObservedOccasions=observed, Checks=checks,
                FailedChecks=sum(not check["Passed"] for check in checks))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("--slot-duration-s", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    content = args.csv_path.read_bytes()
    reader = csv.DictReader(io.StringIO(content.decode("utf-8-sig")))
    if not reader.fieldnames or "MeasurementSource" not in reader.fieldnames:
        raise ValueError("Missing canonical measurement ledger schema.")
    result = audit_rows(list(reader), args.slot_duration_s)
    result.update(Scope="retained_ssb_occasion_consistency_not_phy_qualification",
                  Source=str(args.csv_path.resolve()), SHA256=hashlib.sha256(content).hexdigest(),
                  ConfiguredSlotDuration_s=args.slot_duration_s)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, allow_nan=False)
        handle.write("\n")
    print(json.dumps({key: result[key] for key in ("ObservedOccasions", "FailedChecks")}))
    return 1 if result["FailedChecks"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
