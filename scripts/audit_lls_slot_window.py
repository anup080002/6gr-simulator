"""Audit a real production LLS slot window; never execute/reconstruct PHY state.

All extracted rows remain source-labelled audit evidence. A window pass is not
scenario acceptance, standards conformance, or statistical qualification.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
import math
from pathlib import Path
import sys

import yaml

ROOT = Path(__file__).resolve().parents[1]


class UniqueLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    pairs = loader.construct_pairs(node, deep=deep)
    mapping = {}
    for key, value in pairs:
        if key in mapping:
            raise ValueError(f"Duplicate validation policy key: {key}")
        mapping[key] = value
    return mapping


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def load_plan(path):
    plan = yaml.load(Path(path).read_text(encoding="utf-8"), Loader=UniqueLoader)
    if plan.get("schema") != "SixGRSlotWindow/v1":
        raise ValueError("Unsupported slot-window policy schema")
    for key in ("first_slot", "last_slot", "expected_horizon", "max_layers", "n_prb",
                "minimum_decoded_pucch", "minimum_csi_driven_dl_trials"):
        if type(plan.get(key)) is not int or plan[key] < 1:
            raise ValueError(f"{key} must be a positive integer")
    if not plan["first_slot"] <= plan["last_slot"] <= plan["expected_horizon"]:
        raise ValueError("Window must be within the unchanged scheduling horizon")
    adaptation_last = plan.get("adaptation_last_slot", plan["last_slot"])
    if (type(adaptation_last) is not int or
            not plan["last_slot"] <= adaptation_last <= plan["expected_horizon"]):
        raise ValueError("adaptation_last_slot must be within the unchanged horizon and not precede last_slot")
    plan["adaptation_last_slot"] = adaptation_last
    if plan.get("slot_numbering") != "one_based_absolute_carrier_slot":
        raise ValueError("Do not guess or silently translate slot numbering")
    for key, values in (("minimum_rows", plan["minimum_rows"]),
                        ("minimum_adaptation_rows", plan.get("minimum_adaptation_rows", {})),
                        ("minimum_crc_passes", plan["minimum_crc_passes"])):
        if any(type(v) is not int or v < 1 for v in values.values()):
            raise ValueError(f"{key} must contain positive coverage requirements")
    return plan


def number(row, key):
    try:
        return float(row[key])
    except (ValueError, TypeError, KeyError):
        return math.nan


def yes(row, key):
    return str(row.get(key, "")).strip().lower() in {"1", "true"}


def finalized(row):
    # Match the production legacy-schema default; an explicit pending/NaN
    # flag must never become a completed receiver/state disposition.
    return "FinalizedFlag" not in row or yes(row, "FinalizedFlag")


def identity(row):
    return (str(row.get("UEIndex", "")), str(row.get("RNTI", "")))


def data_trial_valid(r, direction, grant_table, plan, tables, by_slot):
    """Same physical/grant checks for handoff and later adaptive trials."""
    s = by_slot.get(number(r, "Slot"), {})
    start, count = number(r, "SymbolStart"), number(r, "NumSymbols")
    lower, length = number(s, direction + "SymbolStart"), number(s, direction + "NumSymbols")
    layers = number(r, "Layers")
    context = r.get("FrozenGrantContextId", "")
    grants = [g for g in tables.get(grant_table, []) if context and
              g.get("FrozenGrantContextId") == context and identity(g) == identity(r)
              and number(g, "Slot") == number(r, "Slot")]
    return (start.is_integer() and count.is_integer() and count > 0 and
            lower <= start and start + count <= lower + length and
            layers.is_integer() and 1 <= layers <= plan["max_layers"] and
            number(r, "MeasuredDMRSPortCount") == layers and
            0 < number(r, "AllocatedPRBCount") <= plan["n_prb"] and
            number(r, "TBSize_bits") > 0 and yes(r, "DecodeAttempted") and
            r.get("ExecutionBackend") == "scheduler_shared_stream_receiver" and
            yes(r, "PDCCHCausalGrantDecodeOk") and yes(r, "PDCCHGrantBindingOk") and
            len(grants) == 1 and number(grants[0], "TBSBits") == number(r, "TBSize_bits") and
            number(grants[0], "NumLayers") == layers and
            str(r.get("ApproximationMode", "")).strip().lower() in ("", "none", "not_applicable") and
            not any(yes(r, k) for k in ("FallbackFlag", "PlaceholderFlag", "Fallback", "Placeholder")))


def received_csi_valid(r, plan):
    source, due, delivered = (number(r, k) for k in ("SourceSlot", "DueSlot", "DeliveredSlot"))
    return (source <= due <= delivered and yes(r, "CSIUCIDecodeOk") and
            r.get("SourceSignal") == "received_CSI_UCI" and bool(r.get("ReportIdentity")) and
            0 <= number(r, "CQI") <= 15 and 1 <= number(r, "RI") <= plan["max_layers"] and
            number(r, "CSIUCIDecodedBitCount") == number(r, "CSIUCIBitCount") > 0)


def confined(root, relative):
    path = (root / relative).resolve()
    path.relative_to(root.resolve())
    return path


def read_sources(root, plan):
    tables, provenance = {}, []
    for name, spec in plan["inputs"].items():
        path = confined(root, spec["path"])
        if not path.is_file():
            tables[name] = []
            provenance.append(dict(Input=name, Path=spec["path"], Present=False, SHA256=""))
            continue
        before = path.stat()
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        with path.open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            if not reader.fieldnames or len(set(reader.fieldnames)) != len(reader.fieldnames):
                raise ValueError(f"Missing/duplicate CSV columns: {spec['path']}")
            rows = []
            for ordinal, row in enumerate(reader, 1):
                if None in row or any(v is None for v in row.values()):
                    raise ValueError(f"Incomplete CSV record {ordinal}: {spec['path']}")
                row = dict(row, AuditSourceRecord=ordinal, AuditSourceFile=spec["path"])
                rows.append(row)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
            raise ValueError(f"Source changed while reading; retry after writer stops: {path}")
        tables[name] = rows
        provenance.append(dict(Input=name, Path=spec["path"], Present=True,
                               SHA256=digest.hexdigest(), Bytes=after.st_size, Rows=len(rows)))
    return tables, provenance


def evaluate(plan, tables):
    """Pure audit logic; test fixtures exercise this, not the physical simulator."""
    first, last = plan["first_slot"], plan["last_slot"]
    selected = {}
    checks = []

    def check(name, passed, detail, scope="handoff_window"):
        checks.append(dict(Check=name, Status="PASS" if passed else "FAIL", Detail=str(detail), Scope=scope))

    for name, spec in plan["inputs"].items():
        values = tables.get(name, [])
        field = spec["slot"]
        selected[name] = ([r for r in values if first <= number(r, field) <= last]
                          if field else values)
        if field and values:
            check(f"{name}.slot_identity", all(math.isfinite(number(r, field)) and
                  number(r, field).is_integer() and number(r, field) >= 1 for r in values), field)
        # A single-point regression cannot join different sweep points/runs.
        for key in ("RunUUID", "ConfigHash", "SweepPointIndex"):
            identities = {r[key] for r in values if r.get(key, "") not in ("", "NaN", "nan")}
            check(f"{name}.{key}.single", len(identities) <= 1, sorted(identities))

    for key in ("RunUUID", "ConfigHash"):
        ids = {r[key] for values in tables.values() for r in values
               if r.get(key, "") not in ("", "NaN", "nan")}
        check(f"joined.{key}", len(ids) == 1, f"Require one nonempty cross-table identity; observed {sorted(ids)}")
    progress = selected.get("progress", [])
    check("completed_radio_clock", len(progress) == 1 and number(progress[0], "CompletedSlots") >= last,
          "Require the completed-slot counter, not CurrentSlot or CSV count")
    check("unchanged_scheduling_horizon", len(progress) == 1 and
          number(progress[0], "TotalSlots") == plan["expected_horizon"], plan["expected_horizon"])
    slots = selected.get("slots", [])
    slot_counts = Counter(number(r, "CanonicalSlot") for r in slots)
    check("every_window_slot_once", slot_counts == Counter(range(first, last + 1)), dict(slot_counts))
    by_slot = {number(r, "CanonicalSlot"): r for r in slots}
    for name, minimum in plan["minimum_rows"].items():
        check(f"{name}.coverage", len(selected.get(name, [])) >= minimum,
              f"Observed {len(selected.get(name, []))}; required {minimum}; empty is not PASS")

    physical = ("pdsch", "pusch", "pdcch", "pucch", "csirs", "srs", "trs")
    for name in physical:
        bad = []
        for r in selected.get(name, []):
            if any(yes(r, k) for k in ("FallbackFlag", "PlaceholderFlag", "Fallback", "Placeholder")):
                bad.append(r.get("AuditSourceRecord"))
            mode = str(r.get("ApproximationMode", "")).strip().lower()
            if mode not in ("", "none", "not_applicable"):
                bad.append(r.get("AuditSourceRecord"))
        check(f"{name}.no_proxy_rows", not bad, bad)

    for name, direction, grant_table in (("pdsch", "DL", "dl_grants"), ("pusch", "UL", "ul_grants")):
        rows = selected.get(name, [])
        successes = sum(yes(r, "CRCPass") for r in rows)
        check(f"{name}.decoded_coverage", successes >= plan["minimum_crc_passes"][name],
              f"CRC passes {successes}/{len(rows)}; not a BLER qualification")
        errors = []
        for r in rows:
            good = data_trial_valid(r, direction, grant_table, plan, tables, by_slot)
            if not good:
                errors.append(r.get("AuditSourceRecord"))
        check(f"{name}.actual_grant_decode_and_symbol_mapping", not errors and bool(rows), errors)
        # Match per-slot publication counts; never equate scheduled grants
        # with decoded trials (missed DCI has a separate disposition).
        counts = Counter(number(r, "Slot") for r in rows)
        bad_counts = [slot for slot, r in by_slot.items() if number(r, direction + "TrialRows") != counts[slot]]
        check(f"{name}.published_trial_counts", not bad_counts, bad_counts)
        # A scheduled grant without a trial needs a real no-decode disposition.
        # Do not turn a radio miss into a CRC failure, or silently lose it.
        missing_outcomes = []
        for g in selected.get(grant_table, []):
            ctx = g.get("FrozenGrantContextId", "")
            outcomes = [r for r in tables.get(name, []) if ctx and
                        r.get("FrozenGrantContextId") == ctx and identity(r) == identity(g) and
                        number(r, "Slot") == number(g, "Slot")]
            no_decode_table = "dl_no_decode" if direction == "DL" else "ul_receive_only"
            key = "PHYGrantContextId" if direction == "DL" else "GrantContextID"
            source_slot = "SourceSlot" if direction == "DL" else "ScheduledSlot"
            dispositions = [r for r in tables.get(no_decode_table, []) if ctx and
                            r.get(key) == ctx and identity(r) == identity(g) and
                            number(r, source_slot) == number(g, "Slot") and bool(r.get("Disposition")) and
                            bool(r.get("Source"))]
            if len(outcomes) + len(dispositions) != 1:
                missing_outcomes.append(ctx or "missing_grant_identity")
        check(f"{name}.each_scheduled_grant_has_one_outcome", not missing_outcomes, missing_outcomes)

    # Check actual handoff activity in each direction, not merely duplex labels.
    dl_slots = {number(r, "Slot") for r in selected.get("pdsch", [])}
    ul_slots = {number(r, "Slot") for r in selected.get("pusch", [])}
    check("DL_to_UL_data_activity", any(d < u for d in dl_slots for u in ul_slots), "Actual trial order")
    check("UL_to_DL_data_activity", any(u < d for d in dl_slots for u in ul_slots), "Actual trial order")

    bad_timing = []
    for r in selected.get("ul_timing", []):
        if yes(r, "TimingEngineValid"):
            valid = (number(r, "TimingSelectedDataSlot") - number(r, "ControlSlot") == number(r, "TimingSelectedK2"))
            if yes(r, "EligibleForUEScheduling"):
                valid &= yes(r, "TargetSlotHasUL")
        else:
            valid = bool(r.get("BlockReason", "")) and not yes(r, "EligibleForUEScheduling")
        if not valid:
            bad_timing.append(r.get("AuditSourceRecord"))
    check("configured_K2_and_rejected_targets", not bad_timing, bad_timing)
    bad_admission = [r.get("AuditSourceRecord") for r in selected.get("admission", [])
                     if (not r.get("AdmissionReason") or
                         (yes(r, "ActiveAtSchedulerInput") and
                          (not yes(r, "HasTrafficDemand") or not yes(r, "ControlEligible") or
                           (yes(r, "SRSRequired") and not yes(r, "SRSCausalUsable"))))) ]
    check("directional_admission_and_SRS_gate", not bad_admission, bad_admission)

    csi_errors = []
    adaptation_last = plan["adaptation_last_slot"]
    for name in ("pdsch", "received_csi", "admission", "dl_grants", "slots"):
        field = plan["inputs"][name]["slot"]
        selected["adaptation_" + name] = [r for r in tables.get(name, [])
                                          if first <= number(r, field) <= adaptation_last]
    for name, minimum in plan.get("minimum_adaptation_rows", {}).items():
        rows = selected.get("adaptation_" + name, [])
        check(f"{name}.coverage", len(rows) >= minimum,
              f"Observed {len(rows)} through slot {adaptation_last}; required {minimum}",
              scope="causal_adaptation")
    for r in selected["adaptation_received_csi"]:
        good = received_csi_valid(r, plan)
        if not good:
            csi_errors.append(r.get("AuditSourceRecord"))
    check("received_CSI_not_UE_measurement_oracle", not csi_errors, csi_errors, scope="causal_adaptation")
    check("completed_adaptation_clock", len(progress) == 1 and
          number(progress[0], "CompletedSlots") >= adaptation_last,
          f"Require completed radio clock through {adaptation_last}; handoff window ends at {last}",
          scope="causal_adaptation")
    # Retain the actual later records in the audit bundle, rather than
    # claiming they occurred within the handoff window or inventing CSI.
    adaptation_slots = {number(r, "CanonicalSlot"): r for r in selected["adaptation_slots"]}
    check("adaptation_radio_slots_unique", len(adaptation_slots) == len(selected["adaptation_slots"]),
          "Later adaptive trials require an unambiguous retained radio slot", scope="causal_adaptation")
    adaptive = []
    for r in selected["adaptation_pdsch"]:
        if not (yes(r, "LinkAdaptationApplied") and
                data_trial_valid(r, "DL", "dl_grants", plan, tables, adaptation_slots)):
            continue
        source = number(r, "LinkAdaptationAppliedFeedbackSourceSlot")
        reports = [c for c in tables.get("received_csi", []) if identity(c) == identity(r) and
                   received_csi_valid(c, plan) and
                   number(c, "SourceSlot") == source]
        admissions = [a for a in tables.get("admission", []) if identity(a) == identity(r) and
                      a.get("Direction") == "DL" and number(a, "ScheduledDataSlot") == number(r, "Slot") and
                      yes(a, "ActiveAtSchedulerInput") and number(a, "FeedbackSourceSlot") == source]
        if any(number(c, "DeliveredSlot") <= number(a, "SchedulingKnowledgeSlot") <= number(r, "Slot")
               for c in reports for a in admissions):
            adaptive.append(r.get("AuditSourceRecord"))
    check("received_CSI_to_future_DL_trial", len(adaptive) >= plan["minimum_csi_driven_dl_trials"],
          f"Matched {len(adaptive)} actual trials through slot {adaptation_last}, received CSI and scheduler admission; no forced rank change",
          scope="causal_adaptation")

    layout_errors = []
    for r in selected.get("pucch", []):
        fields = ("ReceiverExpectedHARQBitCount", "ReceiverExpectedSRBitCount",
                  "ReceiverExpectedCSIPart1BitCount", "ReceiverExpectedCSIPart2BitCount")
        expected = sum(number(r, f) for f in fields)
        valid = expected == number(r, "ReceiverExpectedBitCount")
        if yes(r, "PUCCHDecodeOk"):
            valid &= (number(r, "DecodedBitCount") == expected and yes(r, "DetectionAttempted")
                      and yes(r, "DetectionUsable") and yes(r, "ReceiverUsable"))
            if yes(r, "CRCApplicable"):
                valid &= yes(r, "CRCPass")
        # Different valid TX/RX hypotheses may physically fail. Do not
        # require ExpectedBitCount to equal the independent RX hypothesis.
        if not valid:
            layout_errors.append(r.get("AuditSourceRecord"))
    check("independent_PUCCH_typed_layout", not layout_errors, layout_errors)
    decoded_pucch = sum(yes(r, "PUCCHDecodeOk") and yes(r, "DetectionUsable") and
                        yes(r, "ReceiverUsable") and
                        (not yes(r, "CRCApplicable") or yes(r, "CRCPass"))
                        for r in selected.get("pucch", []))
    check("pucch.decoded_coverage", decoded_pucch >= plan["minimum_decoded_pucch"], decoded_pucch)

    # Match all physical/logical grant identities. Existing failed receptions
    # are observed failures, NOT missing trials and NOT successful feedback.
    observed_ids = set()
    for r in tables.get("pucch", []):
        if (finalized(r) and str(r.get("ApproximationMode", "")).strip().lower() in {"", "none", "not_applicable"}
                and not any(yes(r, k) for k in ("Fallback", "Placeholder", "FallbackFlag", "PlaceholderFlag"))):
            for token in [r.get("PUCCHGrantId", ""), *r.get("LogicalPUCCHGrantIdSet", "").split("|")]:
                if token.strip():
                    observed_ids.add((identity(r), token.strip(), number(r, "Slot")))
    unresolved = []
    for r in selected.get("feedback_grants", []):
        if not yes(r, "GrantScheduledFlag"):
            continue
        observed = (identity(r), r.get("PUCCHGrantId"), number(r, "Slot")) in observed_ids
        transmitted = (yes(r, "MultiplexedOnPUSCH") and yes(r, "PUSCHUCIDecodeOk") and
                       yes(r, "UCIContentMatch") and yes(r, "RuntimeStateUpdated") and
                       finalized(r) and r.get("Status", "").upper() in {"PASS", "OK", "SUCCESS", "COMPLETED"} and
                       r.get("PUCCHGrantState") == "pusch_uci_feedback_applied" and
                       any(p.get("GrantContextId") == r.get("PUSCHGrantContextId") and
                           bool(r.get("PUSCHGrantContextId")) and identity(p) == identity(r) and
                           yes(p, "UCIOnPUSCHApplied") and yes(p, "HARQACKContentMatch") and
                           r.get("PUCCHGrantId") in p.get("UCIOnPUSCHFeedbackGrantIds", "").split("|")
                           for p in tables.get("pusch", [])))
        cancelled = finalized(r) and yes(r, "CanceledAtSweepBoundary") and bool(r.get("CancellationReason"))
        # The audit window is not the end of the 100-slot run. Never use
        # artificial slot-60 censoring to close feedback that should execute.
        censored = (finalized(r) and yes(r, "RightCensored") and r.get("Status") == "RIGHT_CENSORED" and
                    bool(r.get("CensorReason")) and number(r, "CensorBoundarySlot") >= plan["expected_horizon"])
        if not (observed or transmitted or cancelled or censored):
            unresolved.append(r.get("PUCCHGrantId", "missing_identity"))
    check("feedback_transport_dispositions", not unresolved, unresolved)
    return checks, selected


def audit(plan_path, run_folder, output=None):
    plan = load_plan(plan_path)
    root = Path(run_folder).resolve(strict=True)
    target = Path(output).resolve() if output else confined(root, plan["audit_directory"])
    if target.exists():
        raise ValueError("Audit destination already exists; preserve it and choose a new output path")
    tables, sources = read_sources(root, plan)
    checks, selected = evaluate(plan, tables)
    target.mkdir(parents=True, exist_ok=False)
    for name, rows in selected.items():
        if rows:
            write_csv(target / f"{name}.csv", rows)
    write_csv(target / "checks.csv", checks)
    receipt = dict(Schema="SixGRSlotWindowAudit/v1", AllChecksPassed=all(c["Status"] == "PASS" for c in checks),
                   WindowChecksPassed=all(c["Status"] == "PASS" for c in checks if c["Scope"] == "handoff_window"),
                   AdaptationChecksPassed=all(c["Status"] == "PASS" for c in checks if c["Scope"] == "causal_adaptation"),
                   AdaptationLastSlot=plan["adaptation_last_slot"],
                   ScenarioAccepted=False, StatisticallyQualified=False, FirstSlot=plan["first_slot"],
                   LastSlot=plan["last_slot"], SlotNumbering=plan["slot_numbering"],
                   RunFolder=str(root), Sources=sources,
                   PlanSHA256=hashlib.sha256(Path(plan_path).read_bytes()).hexdigest(),
                   Scope="source_bound_window_audit_not_independent_waveform_or_full_scenario_qualification",
                   Counts={name: len(rows) for name, rows in selected.items()},
                   PhysicalCRCCounts={name: dict(Pass=sum(yes(r, "CRCPass") for r in selected.get(name, [])),
                                                  Fail=sum(str(r.get("CRCPass", "")).lower() in {"0", "false"}
                                                           for r in selected.get(name, [])))
                                      for name in ("pdsch", "pusch")},
                   FailedChecks=[c["Check"] for c in checks if c["Status"] != "PASS"])
    (target / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


def write_csv(path, rows):
    columns = list(dict.fromkeys(k for r in rows for k in r))
    with path.open("x", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--run-folder", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        receipt = audit(args.config, args.run_folder, args.output)
        print(json.dumps(receipt, indent=2))
        return 0 if receipt["AllChecksPassed"] else 1
    except (OSError, ValueError, KeyError) as error:
        print(f"Window audit not accepted: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
