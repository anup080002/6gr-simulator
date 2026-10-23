"""Explicit audit fixtures, never performance data or PHY qualification."""
import copy
import csv
import hashlib
import importlib
import json
from pathlib import Path

import pytest
import yaml

from scripts.audit_lls_slot_window import audit, evaluate, load_plan, read_sources

PLAN = Path(__file__).resolve().parents[1] / "simulator/configs/validation/h4_100_slot40_60.yaml"


def test_h4_checkpoint_policy_anchors_three_slot_cadence_and_preserves_radio_horizon():
    """Configuration guard, not proof of an executed checkpoint or PHY pass."""
    plan = load_plan(PLAN)
    root = Path(__file__).resolve().parents[1]
    scenario = yaml.safe_load((root / plan["scenario_config"]).read_text(encoding="utf-8"))
    control = scenario["run_control"]
    assert control["runtime_checkpoint_enable"] is True
    assert control["checkpoint_every_slots"] == 3
    assert control["checkpoint_first_slot"] == 49
    assert [s for s in range(40, 61) if s >= control["checkpoint_first_slot"]
            and (s - control["checkpoint_first_slot"]) % control["checkpoint_every_slots"] == 0] == [49, 52, 55, 58]
    assert control["total_slots"] == plan["expected_horizon"] == 100
    assert control["total_time_ms"] == 50
    assert scenario["simulation"]["random_seed"] == 20260927
    assert not control.get("runtime_checkpoint_resume_from")


def fixture():
    plan = load_plan(PLAN)
    tables = {key: [] for key in plan["inputs"]}

    def row(**kw):
        return dict(RunUUID="audit_fixture_not_PHY", ConfigHash="test_configuration",
                    UEIndex="1", RNTI="4660", AuditSourceRecord="1", **{k: str(v) for k, v in kw.items()})

    for slot in range(40, 61):
        ul = slot % 5 == 0
        tables["slots"].append(row(CanonicalSlot=slot, DLSymbolStart=0, DLNumSymbols=0 if ul else 14,
                                  ULSymbolStart=0, ULNumSymbols=14 if ul else 0,
                                  DLTrialRows=int(slot in (41, 46, 51)), ULTrialRows=int(slot in (45, 50))))
    tables["progress"] = [row(CompletedSlots=100, CurrentSlot=100, TotalSlots=100)]
    for name, slots, grants in (("pdsch", (41, 46, 51), "dl_grants"), ("pusch", (45, 50), "ul_grants")):
        for slot in slots:
            ctx = f"fixture_{name}_{slot}"
            tables[name].append(row(Slot=slot, SymbolStart=0, NumSymbols=11, Layers=2,
                                    MeasuredDMRSPortCount=2, AllocatedPRBCount=273,
                                    TBSize_bits=12344, DecodeAttempted=1, CRCPass=1,
                                    ExecutionBackend="scheduler_shared_stream_receiver", ApproximationMode="none",
                                    PDCCHCausalGrantDecodeOk=1, PDCCHGrantBindingOk=1,
                                    GrantContextId=ctx, FrozenGrantContextId=ctx,
                                    LinkAdaptationApplied=1,
                                    LinkAdaptationAppliedFeedbackSourceSlot=29))
            tables[grants].append(row(Slot=slot, FrozenGrantContextId=ctx, TBSBits=12344, NumLayers=2))
    for name, slot in (("pdcch", 41), ("csirs", 46), ("srs", 45), ("trs", 47)):
        tables[name] = [row(Slot=slot)]
    tables["received_csi"] = [row(SourceSlot=29, DueSlot=39, DeliveredSlot=40, CSIUCIDecodeOk=1,
                                   SourceSignal="received_CSI_UCI", ReportIdentity="fixture_report", CQI=14,
                                   RI=2, CSIUCIDecodedBitCount=10, CSIUCIBitCount=10)]
    tables["ul_timing"] = [row(ControlSlot=41, TimingEngineValid=1, TimingSelectedDataSlot=45,
                                TimingSelectedK2=4, EligibleForUEScheduling=1, TargetSlotHasUL=1)]
    tables["admission"] = [row(ControlSlot=41, AdmissionReason="passed_traffic_and_reference_admission",
                                ActiveAtSchedulerInput=1, HasTrafficDemand=1, ControlEligible=1,
                                SRSRequired=1, SRSCausalUsable=1, Direction="DL", ScheduledDataSlot=41,
                                SchedulingKnowledgeSlot=41, FeedbackSourceSlot=29)]
    tables["pucch"] = [row(Slot=44, PUCCHGrantId="physical1", LogicalPUCCHGrantIdSet="logical1|logical2",
                            ReceiverExpectedHARQBitCount=3, ReceiverExpectedSRBitCount=1,
                            ReceiverExpectedCSIPart1BitCount=0, ReceiverExpectedCSIPart2BitCount=0,
                            ReceiverExpectedBitCount=4, DecodedBitCount=4, PUCCHDecodeOk=1,
                            DetectionAttempted=1, DetectionUsable=1, ReceiverUsable=1, CRCApplicable=0)]
    tables["feedback_grants"] = [row(Slot=44, GrantScheduledFlag=1, PUCCHGrantId="logical1")]
    return plan, tables


def failures(plan, tables):
    checks, _ = evaluate(plan, tables)
    return {c["Check"] for c in checks if c["Status"] == "FAIL"}


def test_audit_logic_fixture_not_physical_acceptance():
    assert not failures(*fixture())


def canonical_identity_fixture():
    plan, tables = fixture()
    for values in tables.values():
        for row in values:
            row.update(RunUUID="", RunID="audit_fixture_run",
                       ExecutionID="execution_fixture_not_phy")
    return plan, tables


def test_filesystem_execution_identity_does_not_require_database_uuid():
    plan, tables = canonical_identity_fixture()
    original = copy.deepcopy(tables)
    assert not failures(plan, tables)
    assert tables == original  # no replacement or repair of the input rows


@pytest.mark.parametrize("field,value,expected", [
    ("RunID", "another_run", "joined.RunID"),
    ("ExecutionID", "another_execution", "joined.ExecutionID"),
    ("RunID", "", "physical.canonical_execution_identity"),
    ("ExecutionID", "", "physical.canonical_execution_identity"),
])
def test_filesystem_identity_mismatch_or_missing_never_passes(field, value, expected):
    plan, tables = canonical_identity_fixture()
    tables["pucch"][0][field] = value
    assert expected in failures(plan, tables)


def test_canonical_mode_cannot_hide_unbound_physical_table_behind_legacy_uuid():
    plan, tables = canonical_identity_fixture()
    for row in tables["pucch"]:
        row.pop("RunID")
        row.pop("ExecutionID")
        row["RunUUID"] = "legacy_id_not_replacement_execution_authority"
    assert "physical.canonical_execution_identity" in failures(plan, tables)


def test_partial_canonical_pair_cannot_fall_back_to_valid_legacy_identity():
    plan, tables = fixture()
    tables["pdsch"][0]["ExecutionID"] = "execution_fixture_not_phy"
    missing = failures(plan, tables)
    assert {"joined.RunID", "physical.canonical_execution_identity"} <= missing


def test_optional_database_uuid_still_rejects_conflicting_values():
    plan, tables = canonical_identity_fixture()
    tables["pdsch"][0]["RunUUID"] = "db_A"
    tables["pucch"][0]["RunUUID"] = "db_B"
    assert "joined.RunUUID" in failures(plan, tables)


@pytest.mark.parametrize("table,field,value,expected", [
    ("progress", "CompletedSlots", "59", "completed_radio_clock"),
    ("progress", "TotalSlots", "60", "unchanged_scheduling_horizon"),
    ("pdsch", "NumSymbols", "15", "pdsch.actual_grant_decode_and_symbol_mapping"),
    ("pusch", "MeasuredDMRSPortCount", "1", "pusch.actual_grant_decode_and_symbol_mapping"),
    ("pusch", "FrozenGrantContextId", "anotherUE", "pusch.actual_grant_decode_and_symbol_mapping"),
    ("pusch", "PDCCHCausalGrantDecodeOk", "0", "pusch.actual_grant_decode_and_symbol_mapping"),
    ("pusch", "ExecutionBackend", "fast_proxy", "pusch.actual_grant_decode_and_symbol_mapping"),
    ("pusch", "FallbackFlag", "1", "pusch.no_proxy_rows"),
    ("ul_timing", "TimingSelectedK2", "3", "configured_K2_and_rejected_targets"),
    ("admission", "SRSCausalUsable", "0", "directional_admission_and_SRS_gate"),
    ("received_csi", "SourceSlot", "61", "received_CSI_not_UE_measurement_oracle"),
    ("received_csi", "SourceSignal", "UE_reference", "received_CSI_not_UE_measurement_oracle"),
    ("pucch", "ReceiverExpectedBitCount", "14", "independent_PUCCH_typed_layout"),
    ("pucch", "DecodedBitCount", "14", "independent_PUCCH_typed_layout"),
    ("pucch", "DetectionAttempted", "0", "independent_PUCCH_typed_layout"),
    ("feedback_grants", "PUCCHGrantId", "unknown", "feedback_transport_dispositions"),
    ("pucch", "RNTI", "9999", "feedback_transport_dispositions"),
    ("pucch", "FinalizedFlag", "0", "feedback_transport_dispositions"),
    ("pucch", "FinalizedFlag", "NaN", "feedback_transport_dispositions"),
    ("pucch", "ApproximationMode", "fast_proxy", "feedback_transport_dispositions"),
    ("pusch", "ConfigHash", "other_run", "joined.ConfigHash"),
])
def test_detects_known_failure_classes(table, field, value, expected):
    plan, tables = fixture()
    tables[table][0][field] = value
    assert expected in failures(plan, tables)


def test_missing_and_duplicate_slots_never_pass():
    plan, tables = fixture()
    tables["slots"][5] = copy.deepcopy(tables["slots"][4])
    assert "every_window_slot_once" in failures(plan, tables)


def test_empty_ul_cannot_pass_and_no_trial_counters_fabricated():
    plan, tables = fixture()
    tables["pusch"] = []
    missing = failures(plan, tables)
    assert {"pusch.coverage", "pusch.decoded_coverage", "pusch.published_trial_counts",
            "DL_to_UL_data_activity", "UL_to_DL_data_activity"} <= missing


def test_failed_physical_pucch_is_not_missing_or_forced_layout_success():
    plan, tables = fixture()
    r = tables["pucch"][0]
    r.update(PUCCHDecodeOk="0", DecodedBitCount="0", ExpectedBitCount="14", Status="FAIL")
    # Receiver's own 3+1+0+0 layout is valid; a different TX hypothesis may fail.
    assert failures(plan, tables) == {"pucch.decoded_coverage"}


def test_crc_applicability_and_failed_crc_are_not_hidden():
    plan, tables = fixture()
    tables["pucch"][0].update(CRCApplicable="1", CRCPass="0")
    assert "independent_PUCCH_typed_layout" in failures(plan, tables)


def test_transfer_requires_same_pusch_decode():
    plan, tables = fixture()
    g = tables["feedback_grants"][0]
    g.update(PUCCHGrantId="transfer1", MultiplexedOnPUSCH="1", PUSCHUCIDecodeOk="1",
             UCIContentMatch="1", RuntimeStateUpdated="1", PUCCHGrantState="pusch_uci_feedback_applied",
             Status="PASS", FinalizedFlag="1",
             PUSCHGrantContextId=tables["pusch"][0]["GrantContextId"])
    assert "feedback_transport_dispositions" in failures(plan, tables)
    tables["pusch"][0].update(UCIOnPUSCHApplied="1", HARQACKContentMatch="1", UCIOnPUSCHFeedbackGrantIds="transfer1")
    assert not failures(plan, tables)
    g["FinalizedFlag"] = "0"
    assert "feedback_transport_dispositions" in failures(plan, tables)
    g["FinalizedFlag"] = "1"
    g["Status"] = "FAIL"
    assert "feedback_transport_dispositions" in failures(plan, tables)


@pytest.mark.parametrize("mode", ["cancelled", "censored"])
def test_pending_terminal_marker_is_not_a_disposition(mode):
    plan, tables = fixture()
    g = tables["feedback_grants"][0]
    g.update(PUCCHGrantId="unobserved", FinalizedFlag="0")
    if mode == "cancelled":
        g.update(CanceledAtSweepBoundary="1", CancellationReason="independent_point_boundary")
    else:
        g.update(RightCensored="1", Status="RIGHT_CENSORED",
                 CensorReason="finite_horizon_reached", CensorBoundarySlot="100")
    assert "feedback_transport_dispositions" in failures(plan, tables)
    g["FinalizedFlag"] = "1"
    assert not failures(plan, tables)


def test_window_end_is_not_permission_to_censor_feedback():
    plan, tables = fixture()
    tables["feedback_grants"][0].update(PUCCHGrantId="unobserved", RightCensored="1",
                                         Status="RIGHT_CENSORED", CensorReason="end", CensorBoundarySlot="60")
    assert "feedback_transport_dispositions" in failures(plan, tables)


def test_empty_run_receives_failed_receipt_and_no_primary_rows(tmp_path):
    root = tmp_path / "run"
    root.mkdir()
    receipt = audit(PLAN, root)
    assert not receipt["WindowChecksPassed"] and not receipt["ScenarioAccepted"]
    assert receipt["Counts"]["pusch"] == 0
    assert not (root / "air_interface").exists()
    assert not (root / "reports/validation/slot40_60/pusch.csv").exists()
    with pytest.raises(ValueError, match="already exists"):
        audit(PLAN, root)


def test_source_bound_extraction_and_hashes_preserve_originals(tmp_path):
    plan, tables = fixture()
    source_hashes = {}
    for name, spec in plan["inputs"].items():
        if not tables[name]:
            continue
        path = tmp_path / spec["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        rows = tables[name]
        with path.open("w", newline="", encoding="utf-8") as stream:
            fields = list(rows[0])
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        source_hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    receipt = audit(PLAN, tmp_path)
    assert receipt["WindowChecksPassed"] and not receipt["ScenarioAccepted"]
    assert not receipt["StatisticallyQualified"]
    for path, digest in source_hashes.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    disk = json.loads((tmp_path / plan["audit_directory"] / "receipt.json").read_text())
    assert len(disk["Sources"]) == len(plan["inputs"])


def test_large_retained_phy_field_preserved_with_scoped_limit(tmp_path):
    """A wide evidence field is valid CSV, not permission to invent a trial."""
    path = tmp_path / "physical.csv"
    retained = json.dumps({"fixture_only_not_phy": [0, 1] * 70000})
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["Slot", "EvidenceJSON"])
        writer.writerow([46, retained])
    before = path.read_bytes()
    previous = csv.field_size_limit()
    csv.field_size_limit(131072)
    try:
        tables, sources = read_sources(
            tmp_path, {"inputs": {"physical": {"path": path.name, "slot": "Slot"}}})
        assert csv.field_size_limit() == 131072
    finally:
        csv.field_size_limit(previous)
    assert tables["physical"][0]["EvidenceJSON"] == retained
    assert tables["physical"][0]["AuditSourceRecord"] == 1
    assert len(tables["physical"]) == 1
    assert sources[0]["SHA256"] == hashlib.sha256(before).hexdigest()
    assert sources[0]["Bytes"] == len(before)
    assert path.read_bytes() == before


@pytest.mark.parametrize("body", [
    '46,"' + "x" * 200000,  # Unterminated field must not be accepted.
    "46," + "x" * 200000 + ",unexpected\n",
    "46\n",
], ids=["unterminated_large_field", "extra_column_after_large_field", "missing_column"])
def test_large_field_support_keeps_malformed_evidence_rejected(tmp_path, body):
    path = tmp_path / "physical.csv"
    path.write_text("Slot,EvidenceJSON\n" + body, encoding="utf-8")
    before = path.read_bytes()
    previous = csv.field_size_limit()
    with pytest.raises(ValueError, match="Malformed CSV evidence|Incomplete CSV record"):
        read_sources(tmp_path, {"inputs": {"physical": {"path": path.name}}})
    assert csv.field_size_limit() == previous
    assert path.read_bytes() == before


def test_read_path_escape_refused(tmp_path):
    plan = load_plan(PLAN)
    plan["inputs"]["slots"]["path"] = "../outside.csv"
    config = tmp_path / "bad.yaml"
    config.write_text(json.dumps(plan))
    with pytest.raises(ValueError):
        audit(config, tmp_path)


def test_future_csi_must_not_control_an_earlier_grant():
    plan, tables = fixture()
    tables["received_csi"][0]["DeliveredSlot"] = "42"
    assert "received_CSI_to_future_DL_trial" in failures(plan, tables)


def late_csi_fixture():
    """Physical-calendar-shaped audit inputs, not simulated measurements."""
    plan, tables = fixture()
    tables["received_csi"][0].update(SourceSlot="46", DueSlot="59", DeliveredSlot="60")
    for r in tables["pdsch"]:
        r["LinkAdaptationApplied"] = "0"
    trial = dict(tables["pdsch"][0], Slot="61", LinkAdaptationApplied="1",
                 LinkAdaptationAppliedFeedbackSourceSlot="46", FrozenGrantContextId="later61",
                 GrantContextId="later61")
    tables["pdsch"].append(trial)
    tables["dl_grants"].append(dict(tables["dl_grants"][0], Slot="61", FrozenGrantContextId="later61"))
    tables["slots"].append(dict(tables["slots"][1], CanonicalSlot="61", DLTrialRows="1"))
    tables["admission"].append(dict(tables["admission"][0], ControlSlot="61", ScheduledDataSlot="61",
                                     SchedulingKnowledgeSlot="61", FeedbackSourceSlot="46"))
    return plan, tables


def test_legal_post_window_csi_adaptation_is_required_not_forced_before_ul_feedback():
    plan, tables = late_csi_fixture()
    assert plan["last_slot"] == 60 and plan["adaptation_last_slot"] == 100
    checks, selected = evaluate(plan, tables)
    assert not failures(plan, tables)
    assert all(float(r["Slot"]) <= 60 for r in selected["pdsch"])
    assert selected["adaptation_pdsch"][-1]["Slot"] == "61"
    assert next(c for c in checks if c["Check"] == "received_CSI_to_future_DL_trial")["Scope"] == "causal_adaptation"


@pytest.mark.parametrize("field,value", [
    ("LinkAdaptationApplied", "0"), ("PDCCHCausalGrantDecodeOk", "0"),
    ("MeasuredDMRSPortCount", "1"), ("TBSize_bits", "12345"),
    ("ApproximationMode", "fast_proxy"), ("DecodeAttempted", "0"),
    ("Slot", "101"), ("FrozenGrantContextId", "unknown"),
])
def test_post_window_adaptation_requires_real_matched_phy_execution(field, value):
    plan, tables = late_csi_fixture()
    tables["pdsch"][-1][field] = value
    assert "received_CSI_to_future_DL_trial" in failures(plan, tables)


def test_post_window_adaptation_still_rejects_future_and_invalid_received_feedback():
    plan, tables = late_csi_fixture()
    tables["received_csi"][0]["DeliveredSlot"] = "62"
    assert "received_CSI_to_future_DL_trial" in failures(plan, tables)
    tables["received_csi"][0].update(DeliveredSlot="60", CSIUCIDecodedBitCount="9")
    assert "received_CSI_to_future_DL_trial" in failures(plan, tables)


def test_completed_handoff_does_not_finish_the_adaptation_audit():
    plan, tables = late_csi_fixture()
    tables["progress"][0].update(CompletedSlots="60", CurrentSlot="61")
    checks, _ = evaluate(plan, tables)
    assert all(c["Status"] == "PASS" for c in checks if c["Scope"] == "handoff_window")
    assert "completed_adaptation_clock" in failures(plan, tables)


def test_received_csi_after_handoff_window_must_still_precede_scheduling():
    plan, tables = late_csi_fixture()
    tables["received_csi"][0]["DeliveredSlot"] = "61"
    assert not failures(plan, tables)
    tables["admission"][-1]["SchedulingKnowledgeSlot"] = "60"
    assert "received_CSI_to_future_DL_trial" in failures(plan, tables)


def test_missing_csi_cannot_be_excused_by_extended_adaptation_horizon():
    plan, tables = late_csi_fixture()
    tables["received_csi"] = []
    assert {"received_csi.coverage", "received_CSI_to_future_DL_trial"} <= failures(plan, tables)


def test_duplicate_post_window_radio_slot_is_not_silently_collapsed():
    plan, tables = late_csi_fixture()
    tables["slots"].append(dict(tables["slots"][-1]))
    assert "adaptation_radio_slots_unique" in failures(plan, tables)


@pytest.mark.parametrize("last", [59, 101, 60.5, True])
def test_adaptation_policy_cannot_shrink_handoff_or_extend_physical_horizon(tmp_path, last):
    plan = load_plan(PLAN)
    plan["adaptation_last_slot"] = last
    path = tmp_path / "bad.yaml"
    path.write_text(json.dumps(plan))
    with pytest.raises(ValueError, match="adaptation_last_slot"):
        load_plan(path)


def test_grant_without_receiver_outcome_is_not_silently_dropped():
    plan, tables = fixture()
    missing = copy.deepcopy(tables["ul_grants"][0])
    missing["FrozenGrantContextId"] = "lost_grant"
    tables["ul_grants"].append(missing)
    assert "pusch.each_scheduled_grant_has_one_outcome" in failures(plan, tables)
    tables["ul_receive_only"] = [dict(missing, GrantContextID="lost_grant", ScheduledSlot="45",
                                      Disposition="actual_rejected_control", Source="audit_fixture_not_PHY")]
    assert not failures(plan, tables)


def test_duplicate_policy_key_is_not_silent_last_writer_wins(tmp_path):
    path = tmp_path / "bad.yaml"
    path.write_text(PLAN.read_text() + "\nfirst_slot: 1\n")
    with pytest.raises(ValueError, match="Duplicate"):
        load_plan(path)


@pytest.mark.parametrize("scenario_exit,window_pass,adaptation_pass,expected",
                         [(0, True, True, 0), (1, True, True, 1), (0, False, True, 1),
                          (0, True, False, 1)])
def test_server_wrapper_keeps_scenario_and_window_acceptance_separate(monkeypatch, tmp_path,
                                                                     scenario_exit, window_pass, adaptation_pass, expected):
    monkeypatch.syspath_prepend(str(PLAN.parents[3] / "scripts"))
    launch = importlib.import_module("run_lls_slot_window")
    calls = []
    monkeypatch.setattr(launch.server, "execute", lambda args: calls.append(args) or scenario_exit)
    monkeypatch.setattr(launch, "audit", lambda *args: {"WindowChecksPassed": window_pass,
                       "AdaptationChecksPassed": adaptation_pass,
                       "AllChecksPassed": window_pass and adaptation_pass})
    root = tmp_path / "lls" / load_plan(PLAN)["scenario_id"] / "fixture"
    root.mkdir(parents=True)
    monkeypatch.setattr("sys.argv", ["run_lls_slot_window.py", "--config", str(PLAN),
                                   "--matlab", "fixture_not_executed", "--results", str(tmp_path), "--tag", "fixture"])
    assert launch.main() == expected
    assert calls[0].scenario == load_plan(PLAN)["scenario_config"]
    assert calls[0].tag == "fixture" and not calls[0].plan


def test_server_plan_does_not_execute_audit_or_create_run(monkeypatch, tmp_path):
    monkeypatch.syspath_prepend(str(PLAN.parents[3] / "scripts"))
    launch = importlib.import_module("run_lls_slot_window")
    calls = []
    monkeypatch.setattr(launch.server, "execute", lambda args: calls.append(args) or 0)
    monkeypatch.setattr(launch, "audit", lambda *args: pytest.fail("Dry plan must not audit or write"))
    monkeypatch.setattr("sys.argv", ["run_lls_slot_window.py", "--config", str(PLAN),
                                   "--matlab", "fixture_not_executed", "--results", str(tmp_path),
                                   "--tag", "fixture", "--plan"])
    assert launch.main() == 0 and calls[0].plan
    assert not list(tmp_path.iterdir())
