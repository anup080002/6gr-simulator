#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, hashlib, json, math, sys, tempfile
from pathlib import Path
try:
    from PIL import Image, ImageDraw, ImageStat
except ImportError as exc:
    raise SystemExit("Pillow is required") from exc

HERE = Path(__file__).resolve().parent

def truth(value) -> bool:
    return str(value).strip().upper() in {"1","TRUE","YES","PASS"}

def finite(value):
    try:
        x = float(str(value).strip())
    except Exception:
        return None
    return x if math.isfinite(x) else None

def integer(value):
    x = finite(value)
    return int(round(x)) if x is not None and abs(x-round(x)) < 1e-9 else None

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024*1024), b""):
            h.update(block)
    return h.hexdigest()

def read_contract(name: str):
    with (HERE/name).open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))

def read_csv(path: Path):
    with path.open(newline="", encoding="utf-8-sig") as f:
        raw = list(csv.reader(f))
    if not raw:
        return [], [], ["empty"]
    header = raw[0]
    errors = []
    if len(header) != len(set(header)):
        errors.append("duplicate_header")
    rows = []
    for idx, values in enumerate(raw[1:], 2):
        if len(values) != len(header):
            errors.append(f"nonrectangular:{idx}")
        else:
            rows.append(dict(zip(header, values)))
    if not rows:
        errors.append("no_rows")
    return header, rows, errors

def combined_source_hash(root: Path, names):
    h = hashlib.sha256()
    for name in sorted(n for n in names if n):
        path = root/name
        if not path.exists():
            return ""
        h.update(name.encode("utf-8"))
        h.update(sha256(path).encode("ascii"))
    return h.hexdigest()

def verify(root: Path):
    failures = []
    parsed = {}
    csv_contract = read_contract("desired_initial_access_csv_contract.csv")
    image_contract = read_contract("desired_initial_access_image_contract.csv")

    for contract in csv_contract:
        path = root/contract["FileName"]
        required = [x for x in contract["RequiredColumns"].split("|") if x]
        if not path.exists():
            failures.append("missing_csv:" + path.name)
            continue
        header, rows, errors = read_csv(path)
        parsed[path.name] = rows
        failures.extend(path.name + ":" + e for e in errors)
        missing = [x for x in required if x not in header]
        if missing:
            failures.append(path.name + ":missing_columns:" + ",".join(missing))
            continue
        if len(rows) < int(contract["MinRows"]):
            failures.append(path.name + ":too_few_rows")
        keys = [x for x in contract["PrimaryKey"].split("|") if x]
        seen = set()
        for idx, row in enumerate(rows, 2):
            key = tuple(row.get(x,"") for x in keys)
            if key in seen:
                failures.append(path.name + ":duplicate_key:" + repr(key))
            seen.add(key)
            if "Status" in row and row["Status"].strip().upper() != "PASS":
                failures.append(path.name + f":nonpass:{idx}")

    # Fail-closed technical checks.
    for idx, row in enumerate(parsed.get("ssb_case_resolution.csv", []), 2):
        if truth(row.get("ClampOrRetryUsed")):
            failures.append(f"ssb_clamp_retry:{idx}")
        if integer(row.get("RequestedGridRB")) != integer(row.get("AppliedGridRB")):
            failures.append(f"ssb_grid_mutated:{idx}")
        if len(row.get("PlanSHA256","")) != 64:
            failures.append(f"ssb_plan_hash:{idx}")

    for idx, row in enumerate(parsed.get("ssb_burst_plan.csv", []), 2):
        if truth(row.get("Active")) and (not row.get("BeamID","").strip() or len(row.get("MIBSHA256","")) != 64):
            failures.append(f"ssb_active_beam_or_mib:{idx}")
        if len(row.get("PrecodingSHA256","")) != 64:
            failures.append(f"ssb_precoder_hash:{idx}")

    for idx, row in enumerate(parsed.get("ssb_re_ownership.csv", []), 2):
        if truth(row.get("Mismatch")) or row.get("Owner") != row.get("ExpectedOwner"):
            failures.append(f"ssb_re_mismatch:{idx}")

    selected_by_trial = {}
    for idx, row in enumerate(parsed.get("ssb_blind_search_hypotheses.csv", []), 2):
        if truth(row.get("OracleFieldUsed")):
            failures.append(f"ssb_receiver_oracle:{idx}")
        if truth(row.get("Selected")):
            selected_by_trial[row.get("TrialID","")] = selected_by_trial.get(row.get("TrialID",""),0) + 1
    for trial, count in selected_by_trial.items():
        if count != 1:
            failures.append("ssb_selected_hypothesis_count:" + trial)

    for idx, row in enumerate(parsed.get("pbch_mib_decode.csv", []), 2):
        if not truth(row.get("BCHCRC")):
            failures.append(f"pbch_crc:{idx}")
        if integer(row.get("IndependentMismatchCount")) != 0:
            failures.append(f"mib_independent_mismatch:{idx}")
        if len(row.get("MIBBits23","")) != 23:
            failures.append(f"mib_length:{idx}")

    for idx, row in enumerate(parsed.get("type0_coreset_resolution.csv", []), 2):
        if integer(row.get("IndependentMismatchCount")) != 0:
            failures.append(f"type0_mismatch:{idx}")
        if truth(row.get("Reserved")):
            failures.append(f"type0_reserved_accepted:{idx}")

    for idx, row in enumerate(parsed.get("type0_monitoring_candidates.csv", []), 2):
        if truth(row.get("Selected")) and (not truth(row.get("CRCResult")) or row.get("RNTI") not in {"65535","SI-RNTI"}):
            failures.append(f"type0_invalid_selected:{idx}")

    for idx, row in enumerate(parsed.get("sib1_dci_resolution.csv", []), 2):
        if truth(row.get("ConfiguredGrantUsed")):
            failures.append(f"sib1_configured_grant:{idx}")
        if not truth(row.get("CRCResult")) or row.get("RNTI") not in {"65535","SI-RNTI"} or row.get("Format") != "1_0":
            failures.append(f"sib1_dci_invalid:{idx}")
        if len(row.get("AssignmentSHA256","")) != 64:
            failures.append(f"sib1_assignment_hash:{idx}")

    for idx, row in enumerate(parsed.get("sib1_resource_ownership.csv", []), 2):
        if truth(row.get("Collision")) or len(row.get("IndexSHA256","")) != 64:
            failures.append(f"sib1_resource_map:{idx}")

    for idx, row in enumerate(parsed.get("sib1_asn1_decode.csv", []), 2):
        if row.get("DecodeError","").strip():
            failures.append(f"sib1_asn1_error:{idx}")
        if not row.get("IndependentCodec","").strip() or not row.get("IndependentVersion","").strip():
            failures.append(f"sib1_independent_codec:{idx}")
        for field in ("UPERHexSHA256","ASN1SchemaSHA256","SemanticSHA256"):
            if len(row.get(field,"")) != 64:
                failures.append(f"sib1_hash:{field}:{idx}")

    for idx, row in enumerate(parsed.get("decoded_sib1_install.csv", []), 2):
        if not truth(row.get("Installed")) or truth(row.get("Mismatch")):
            failures.append(f"sib1_install:{idx}")
        if row.get("ConfigurationEpochBefore") == row.get("ConfigurationEpochAfter"):
            failures.append(f"sib1_epoch_not_changed:{idx}")

    for idx, row in enumerate(parsed.get("prach_config_resolution.csv", []), 2):
        if integer(row.get("IndependentMismatchCount")) != 0:
            failures.append(f"prach_config_mismatch:{idx}")
        if truth(row.get("Reserved")):
            failures.append(f"prach_reserved_accepted:{idx}")

    for idx, row in enumerate(parsed.get("prach_occasion_resolution.csv", []), 2):
        if not truth(row.get("Valid")) or truth(row.get("Mismatch")):
            failures.append(f"prach_occasion:{idx}")
        if integer(row.get("RARNTI")) is None:
            failures.append(f"prach_rarnti:{idx}")

    for idx, row in enumerate(parsed.get("ssb_ro_association.csv", []), 2):
        if truth(row.get("Mismatch")) or not row.get("BeamStateID","").strip():
            failures.append(f"ssb_ro_association:{idx}")

    for idx, row in enumerate(parsed.get("prach_sequence_indices.csv", []), 2):
        if integer(row.get("IndependentMismatchCount")) != 0:
            failures.append(f"prach_sequence_mismatch:{idx}")
        if len(row.get("SequenceSHA256","")) != 64 or len(row.get("IndexSHA256","")) != 64:
            failures.append(f"prach_sequence_hash:{idx}")

    for idx, row in enumerate(parsed.get("prach_detection_trials.csv", []), 2):
        if truth(row.get("FalseAlarm")) or truth(row.get("MissedDetection")) or truth(row.get("Ambiguous")):
            failures.append(f"prach_detection_failure:{idx}")
        for field in ("PeakMetric","Threshold","TimingEstimate_samples","TimingError_samples","FrequencyEstimate_Hz"):
            if finite(row.get(field)) is None:
                failures.append(f"prach_metric_nonfinite:{field}:{idx}")

    for idx, row in enumerate(parsed.get("ra_power_control.csv", []), 2):
        error = finite(row.get("PowerError_dB"))
        if error is None or abs(error) > 0.05:
            failures.append(f"ra_power_reconcile:{idx}")
        if not row.get("SourceMeasurementID","").strip():
            failures.append(f"ra_power_source:{idx}")

    for idx, row in enumerate(parsed.get("ra_timer_events.csv", []), 2):
        if truth(row.get("Mismatch")):
            failures.append(f"ra_timer_mismatch:{idx}")

    for idx, row in enumerate(parsed.get("ra_attempt_events.csv", []), 2):
        if not row.get("DecodedEvidenceID","").strip() and row.get("Event") not in {"START","BACKOFF_START","BACKOFF_END"}:
            failures.append(f"ra_event_evidence:{idx}")

    for idx, row in enumerate(parsed.get("rar_decode.csv", []), 2):
        if row.get("RARNTIExpected") != row.get("RARNTIDecoded") or row.get("RAPIDExpected") != row.get("RAPIDDecoded"):
            failures.append(f"rar_identity:{idx}")
        if not truth(row.get("InsideResponseWindow")) or not truth(row.get("PDCCHCRC")) or not truth(row.get("PDSCHCRC")):
            failures.append(f"rar_decode:{idx}")

    for idx, row in enumerate(parsed.get("msg3_harq.csv", []), 2):
        if not truth(row.get("CRC")):
            failures.append(f"msg3_crc:{idx}")
        for field in ("TBIdentitySHA256","RRCSetupRequestSHA256","SoftBufferSHA256"):
            if len(row.get(field,"")) != 64:
                failures.append(f"msg3_hash:{field}:{idx}")

    for idx, row in enumerate(parsed.get("contention_resolution.csv", []), 2):
        if not truth(row.get("IdentityMatch")) or truth(row.get("TimerExpired")):
            failures.append(f"contention_resolution:{idx}")
        if not truth(row.get("Msg4PDCCHCRC")) or not truth(row.get("Msg4PDSCHCRC")):
            failures.append(f"msg4_crc:{idx}")

    rrc_states = {}
    for idx, row in enumerate(parsed.get("rrc_connection_events.csv", []), 2):
        if not row.get("MessageSHA256","").strip() or len(row.get("MessageSHA256","")) != 64:
            failures.append(f"rrc_message_hash:{idx}")
        key = (row.get("AttemptID",""), row.get("Endpoint",""))
        rrc_states[key] = row.get("NextState","")
        if row.get("NextState") == "CONNECTED" and row.get("Event") != "RRC_SETUP_COMPLETE_OK":
            failures.append(f"rrc_connected_too_early:{idx}")
    attempts = {k[0] for k in rrc_states}
    for attempt in attempts:
        if rrc_states.get((attempt,"UE")) != rrc_states.get((attempt,"GNB")):
            failures.append("rrc_endpoint_state_mismatch:" + attempt)

    for idx, row in enumerate(parsed.get("initial_access_receiver_metrics.csv", []), 2):
        if integer(row.get("OracleFieldCount")) != 0:
            failures.append(f"receiver_oracle_count:{idx}")
        if finite(row.get("MeasuredSINR_dB")) is None:
            failures.append(f"receiver_sinr:{idx}")

    for idx, row in enumerate(parsed.get("initial_access_stage_bler.csv", []), 2):
        if truth(row.get("Incomplete")):
            failures.append(f"bler_incomplete:{idx}")
        for field in ("Trials","Errors","BLER","CILower","CIUpper","ConfidenceLevel"):
            if finite(row.get(field)) is None:
                failures.append(f"bler_nonfinite:{field}:{idx}")

    for idx, row in enumerate(parsed.get("initial_access_negative_tests.csv", []), 2):
        if truth(row.get("InvalidStageOrLaterWaveformGenerated")) or truth(row.get("GrantCreated")) or truth(row.get("StateChangedAfterFailure")) or not truth(row.get("Pass")):
            failures.append(f"negative_fail_closed:{idx}")
        if row.get("ActualError") != row.get("ExpectedError"):
            failures.append(f"negative_error_mismatch:{idx}")

    for idx, row in enumerate(parsed.get("initial_access_independent_vector_results.csv", []), 2):
        if integer(row.get("MismatchCount")) != 0 or truth(row.get("SelfConsistencyOnly")):
            failures.append(f"independent_vector:{idx}")
        if not row.get("IndependentImplementation","").strip() or len(row.get("SourceSHA256","")) != 64:
            failures.append(f"independent_source:{idx}")

    for idx, row in enumerate(parsed.get("initial_access_test_summary.csv", []), 2):
        if truth(row.get("Mandatory")) and (integer(row.get("Failed")) != 0 or integer(row.get("Skipped")) != 0 or integer(row.get("Blocked")) != 0):
            failures.append(f"mandatory_test_not_clean:{idx}")
        if integer(row.get("Passed")) != integer(row.get("TestsRun")):
            failures.append(f"test_count_mismatch:{idx}")

    # Image files and semantic-audit reconciliation.
    audit_rows = {r.get("ImageFile",""):r for r in parsed.get("initial_access_image_semantic_audit.csv", [])}
    for contract in image_contract:
        name = contract["ImageFile"]
        path = root/name
        if not path.exists():
            failures.append("missing_png:" + name)
            continue
        try:
            with Image.open(path) as im:
                im.load()
                width, height = im.size
                gray = im.convert("L")
                extrema = gray.getextrema()
                if width < int(contract["MinWidth"]) or height < int(contract["MinHeight"]):
                    failures.append("png_dimensions:" + name)
                if extrema[0] == extrema[1]:
                    failures.append("png_blank:" + name)
        except Exception as exc:
            failures.append("png_decode:" + name + ":" + type(exc).__name__)
            continue
        audit = audit_rows.get(name)
        if audit is None:
            failures.append("missing_image_audit:" + name)
            continue
        if audit.get("PNG_SHA256") != sha256(path):
            failures.append("png_hash_mismatch:" + name)
        source_names = [x for x in contract["SourceCSVFiles"].split("|") if x]
        if audit.get("SourceCSVSHA256") != combined_source_hash(root, source_names):
            failures.append("source_csv_hash_mismatch:" + name)
        if integer(audit.get("Width")) != width or integer(audit.get("Height")) != height:
            failures.append("image_recorded_dimensions:" + name)
        if integer(audit.get("AxesCount")) is None or integer(audit.get("AxesCount")) < int(contract["MinAxes"]):
            failures.append("image_axes:" + name)
        if integer(audit.get("SeriesCount")) is None or integer(audit.get("SeriesCount")) < int(contract["MinSeries"]):
            failures.append("image_series:" + name)
        if integer(audit.get("FinitePointCount")) is None or integer(audit.get("FinitePointCount")) < int(contract["MinFinitePoints"]):
            failures.append("image_points:" + name)
        if not truth(audit.get("SemanticCheck")):
            failures.append("image_semantic_check:" + name)
        for field, expected in (("Title",contract["ExpectedTitleTokens"]),("XLabel",contract["ExpectedXLabelTokens"]),("YLabel",contract["ExpectedYLabelTokens"])):
            actual = audit.get(field,"").lower()
            tokens = [x.strip().lower() for x in expected.replace("/"," ").split() if x.strip()]
            if tokens and not any(t in actual for t in tokens):
                failures.append(f"image_{field.lower()}_semantics:" + name)

    return failures

def default_value(column: str, row_index: int):
    low = column.lower()
    if column == "Status":
        return "PASS"
    if column in {"Pass","Active","Selected","BCHCRC","CRCResult","Installed","Valid","Detected","InsideResponseWindow","PDCCHCRC","PDSCHCRC","CRC","IdentityMatch","Msg4PDCCHCRC","Msg4PDSCHCRC","SemanticCheck","Mandatory"}:
        return "true"
    if column in {"MismatchCount","IndependentMismatchCount","OracleFieldCount","FalseCandidateCount"}:
        return "0"
    if any(x in low for x in ("mismatch","oraclefieldused","clamporretryused","configuredgrantused","collision","reserved","falsealarm","misseddetection","ambiguous","timerexpired","incomplete","selfconsistencyonly","invalidstageorlaterwaveformgenerated","grantcreated","statechangedafterfailure")):
        return "false"
    if "sha256" in low or low.endswith("hash"):
        return "0"*64
    if column == "MIBBits23":
        return "0"*23
    if column == "RNTI":
        return "65535"
    if column == "Format":
        return "1_0"
    if column in {"Owner","ExpectedOwner"}:
        return "PSS"
    if column == "IndependentCodec":
        return "independent_asn1"
    if column == "IndependentVersion":
        return "1.0"
    if column == "DecodeError":
        return ""
    if column == "ConfigurationEpochBefore":
        return "1"
    if column == "ConfigurationEpochAfter":
        return "2"
    if column == "RequestedGridRB" or column == "AppliedGridRB":
        return "106"
    if column == "BeamID" or column == "SelectedBeamID":
        return "beam0"
    if column == "K1Source":
        return "decoded_dci"
    if column == "RARNTIExpected" or column == "RARNTIDecoded":
        return "1"
    if column == "RAPIDExpected" or column == "RAPIDDecoded":
        return "0"
    if column == "ExpectedError" or column == "ActualError":
        return "sixgr:phy:ia:ExpectedNegative"
    if column == "PreviousState":
        return "WAIT_SETUP_COMPLETE"
    if column == "Event":
        return "RRC_SETUP_COMPLETE_OK"
    if column == "NextState":
        return "CONNECTED"
    if column == "Endpoint":
        return "UE" if row_index % 2 == 0 else "GNB"
    if column == "SourceMeasurementID":
        return "measurement0"
    if column == "DecodedEvidenceID":
        return "evidence0"
    if column == "TestsRun" or column == "Passed":
        return "10"
    if column in {"Failed","Skipped","Blocked","MismatchCount","IndependentMismatchCount","OracleFieldCount","PowerError_dB"}:
        return "0"
    if column == "ConfidenceLevel":
        return "0.95"
    if column in {"Trials","FinitePointCount"}:
        return "100"
    if column in {"Errors","BLER","CILower"}:
        return "0"
    if column == "CIUpper":
        return "0.03"
    if column == "StopReason":
        return "target_met"
    if column == "PlanSHA256" or column == "AssignmentSHA256" or column == "IndexSHA256" or column == "SequenceSHA256":
        return "0"*64
    if column == "SRB1Installed":
        return "true"
    if column == "ActualError":
        return "sixgr:phy:ia:ExpectedNegative"
    return str(row_index)

def build_synthetic(root: Path):
    root.mkdir(parents=True, exist_ok=True)
    contracts = read_contract("desired_initial_access_csv_contract.csv")
    for contract in contracts:
        if contract["FileName"] == "initial_access_image_semantic_audit.csv":
            continue
        cols = [x for x in contract["RequiredColumns"].split("|") if x]
        count = int(contract["MinRows"])
        rows = []
        for i in range(count):
            row = {c: default_value(c,i) for c in cols}
            # make composite keys unique
            for key in contract["PrimaryKey"].split("|"):
                if key:
                    row[key] = f"{key}_{i}"
            if contract["FileName"] == "ssb_blind_search_hypotheses.csv":
                row["TrialID"] = f"T{i}"
                row["Selected"] = "true"
                row["BCHCRC"] = "true"
            if contract["FileName"] == "type0_monitoring_candidates.csv":
                row["RNTI"] = "65535"; row["DCIFormat"]="1_0"; row["CRCResult"]="true"; row["Selected"]="true"
            if contract["FileName"] == "rrc_connection_events.csv":
                row["AttemptID"] = f"A{i//2}"
                row["Endpoint"] = "UE" if i%2==0 else "GNB"
                row["EventOrdinal"] = str(i)
                row["PreviousState"]="WAIT_SETUP_COMPLETE"; row["Event"]="RRC_SETUP_COMPLETE_OK"; row["NextState"]="CONNECTED"
                row["MessageSHA256"]="0"*64; row["CRC"]="true"; row["Status"]="PASS"
            if contract["FileName"] == "initial_access_negative_tests.csv":
                row["ExpectedError"]="sixgr:phy:ia:ExpectedNegative"; row["ActualError"]=row["ExpectedError"]; row["Pass"]="true"
            rows.append(row)
        with (root/contract["FileName"]).open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rows)

    # Create nonblank PNGs first.
    image_contract = read_contract("desired_initial_access_image_contract.csv")
    image_meta = []
    for idx, contract in enumerate(image_contract):
        path = root/contract["ImageFile"]
        im = Image.new("RGB",(1000,700),"white")
        d = ImageDraw.Draw(im)
        d.rectangle((50,50,950,650),outline="black",width=3)
        d.line((80,620,900,100+idx*3),fill="black",width=4)
        d.text((90,80),contract["ExpectedTitleTokens"],fill="black")
        im.save(path)
        sources=[x for x in contract["SourceCSVFiles"].split("|") if x]
        image_meta.append({
            "ImageFile":contract["ImageFile"],"SourceCSVFiles":contract["SourceCSVFiles"],
            "SourceCSVSHA256":combined_source_hash(root,sources),"PNG_SHA256":sha256(path),
            "Width":1000,"Height":700,"AxesCount":max(1,int(contract["MinAxes"])),
            "SeriesCount":max(1,int(contract["MinSeries"])),"FinitePointCount":max(100,int(contract["MinFinitePoints"])),
            "Title":contract["ExpectedTitleTokens"],"XLabel":contract["ExpectedXLabelTokens"],
            "YLabel":contract["ExpectedYLabelTokens"],"SemanticCheck":"true","Status":"PASS"
        })
    cols=[x for x in next(c for c in contracts if c["FileName"]=="initial_access_image_semantic_audit.csv")["RequiredColumns"].split("|") if x]
    with (root/"initial_access_image_semantic_audit.csv").open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(image_meta)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("root",nargs="?")
    parser.add_argument("--self-test",action="store_true")
    args=parser.parse_args()
    if args.self_test:
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            build_synthetic(root)
            valid=verify(root)
            target=root/read_contract("desired_initial_access_image_contract.csv")[0]["ImageFile"]
            with Image.open(target) as im:
                d=ImageDraw.Draw(im);d.rectangle((0,0,20,20),fill="red");im.save(target)
            corrupt=verify(root)
            result={"valid_failures":valid,"corrupt_failure_count":len(corrupt),
                    "corruption_detected":any("png_hash_mismatch" in x for x in corrupt)}
            print(json.dumps(result,indent=2))
            sys.exit(0 if not valid and result["corruption_detected"] else 2)
    if not args.root:
        parser.error("root is required unless --self-test is used")
    failures=verify(Path(args.root))
    print(json.dumps({"root":args.root,"failure_count":len(failures),"failures":failures},indent=2))
    sys.exit(0 if not failures else 2)

if __name__ == "__main__":
    main()
