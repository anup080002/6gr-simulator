from __future__ import annotations

import sys
import math
import csv
import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))

import lls_web_dashboard as dashboard  # noqa: E402


def test_srs_power_preview_retains_causal_source_and_does_not_invent_zero() -> None:
    source = dict(Slot=5, UEID=1, ServingCell=1,
                  SRSPowerControlRequestedPower_dBm=16.8227,
                  SRSPowerControlAppliedPower_dBm=16.8227,
                  SRSPowerControlPCMAX_dBm=23,
                  SRSPowerControlPathloss_dB=95,
                  SRSPowerControlPathlossReferenceRS="SSB-0",
                  SRSPowerControlSignalledReferencePower_dBm=5,
                  SRSPowerControlFilteredRSRP_dBm=-90,
                  SRSPowerControlAdjustment_dB=1,
                  SRSPowerControlAdjustmentState="same_as_pusch",
                  SRSPowerControlStateOwner="received_ue_pusch_power_control",
                  SRSPowerControlStateUpdateCount=1,
                  SRSPowerControlTPCAvailableAtSample=15360,
                  SRSPowerControlTPCAppliedAtSample=60896,
                  SRSPowerControlAdjustmentReadAtSample=75160,
                  SRSPowerControlBoundAtEmission=True,
                  SRSPowerControlClipped=False,
                  SRSPowerControlReceivedAssignmentDigest="a" * 64)
    row = dashboard.summarize_control_trial_preview_rows("srs_trials", [source])[0]
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["srs_trials"])
    for name, value in source.items():
        if name.startswith("SRSPowerControl"):
            assert row[labels[name]] == value
    old = dashboard.summarize_control_trial_preview_rows("srs_trials", [dict(Slot=5)])[0]
    assert old.get(labels["SRSPowerControlAdjustment_dB"]) is None
    assert old.get(labels["SRSPowerControlAppliedPower_dBm"]) is None
    html = Path(dashboard.__file__).read_text(encoding="utf-8")
    assert "id:'srs_power'" in html
    assert "not measured post-PA power or radiated EIRP/TRP" in html


def test_live_generic_table_does_not_hide_late_measurement_columns() -> None:
    # Execute the production renderer, including fields that first appear in
    # a later row. A twelve-column preview hid the receiver-owned AMC state.
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    renderer = next(line.strip() for line in source.splitlines()
                    if line.strip().startswith("function rows(records, empty, opts)"))
    first = {f"Field{k}": k for k in range(14)}
    second = dict(first, RuntimeDLOLLAUpdateCount=6,
                  RuntimeDLPendingRankIncrease=4)
    script = """
const esc = x => String(x).replaceAll('&','&amp;').replaceAll('<','&lt;');
const text = x => x == null ? 'N/A' : String(x);
const unavailable = x => x;
const scrollWrap = x => x;
""" + renderer + "\nconsole.log(rows(" + json.dumps([first, second]) + ", 'empty', {}));"
    result = subprocess.run([node, "-e", script], capture_output=True,
                            text=True, check=True, timeout=15)
    html = result.stdout
    assert "<th>Field13</th>" in html
    assert "<th>RuntimeDLOLLAUpdateCount</th>" in html
    assert "<th>RuntimeDLPendingRankIncrease</th>" in html
    assert html.count("<th>") == 16 and html.count("<td>") == 32
    assert "<td>N/A</td>" in html and "<td>6</td>" in html


def test_csv_reader_preserves_qcl_and_zenith_field_names(tmp_path: Path) -> None:
    # Exercise the production CSV reader, not just a hand-made preview dict.
    # A blanket Q/Z-prefix repair changed QCLType to CLType before the GUI
    # projection and left every QCL cell empty despite valid MATLAB evidence.
    source = dict(Slot=41, UEID=1, QCLStatus="consumed_by_received_pdsch_dmrs_timing_estimator",
                  QCLType="A", QCLSourceRS="NZP-CSI-RS/TRS", QCLSourceResourceID=100,
                  QCLSourceSlot0=26, QCLSourceAvailableAtSample=1720320,
                  QCLTimingPriorUsed=1, QCLTimingPriorSamples=16,
                  QCLDMRSDelayResidual_samples=0,
                  QCLMeasurementStatus="type_A_average_delay_transfer_only",
                  TCIStateID=18, TCICodepoint=2, ZOA_deg=95, ZOD_deg=85,
                  QCustomEvidence="retained", ZCustomEvidence="retained")
    path = tmp_path / "dl_pdsch_trials.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(source))
        writer.writeheader()
        writer.writerow(source)
    artifact = dict(artifact_id=-1, logical_path="air_interface/csv/dl_pdsch_trials.csv",
                    filesystem_path=str(path), byte_size=path.stat().st_size)
    rows = dashboard.load_small_csv_rows([artifact], artifact["logical_path"])
    assert set(rows[0]) == set(source), "Do not rename valid measurement identities."
    preview = dashboard.summarize_data_trial_preview_rows("dl_trials", rows)[0]
    labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["dl_trials"])
    for name, value in source.items():
        if name.startswith("QCL"):
            assert preview[labels[name]] == value
    assert preview["QCL DMRS delay residual"] == 0
    # Retain only the already documented exact legacy header aliases.
    assert dashboard.normalize_csv_header_name("QStageOrder") == "StageOrder"
    assert dashboard.normalize_csv_header_name("ZCase") == "Case"


def test_rrc_preview_keeps_transmitted_and_failed_received_evidence_separate() -> None:
    rows = [
        dict(AttemptID="run-A1", UEIdentity="UE-1", Endpoint="UE", EventOrdinal=4,
             AbsoluteSlot0Based=14, Slot1Based=15, Event="UL_DCCH_CRC_FAIL",
             SRB1InstalledBefore=True, SRB1Installed=True, CRCApplicable=False,
             CRC=float("nan"), MessageSHA256="a" * 64,
             MessageEvidenceRole="transmitted_message_not_received_evidence",
             Status="FAIL", StatusScope="bounded_protocol_transition_not_PHY_CRC",
             MACRRCStandardsQualified=False),
        dict(AttemptID="run-A1", UEIdentity="UE-1", Endpoint="GNB", EventOrdinal=4,
             AbsoluteSlot0Based=14, Slot1Based=15, Event="UL_DCCH_CRC_FAIL",
             SRB1InstalledBefore=True, SRB1Installed=True, CRCApplicable=True,
             CRC=0, MessageSHA256="", CRCSource="RRCSetupCompleteCRC",
             MessageEvidenceRole="no_decoded_RRC_message_after_CRC_failure",
             Status="FAIL", StatusScope="bounded_protocol_transition_not_PHY_CRC",
             MACRRCStandardsQualified=False),
    ]
    tx, rx = dashboard.summarize_procedure_preview_rows("rrc_connection_events", rows)
    assert tx["Message SHA256"] == "a" * 64
    assert tx["Receiver CRC applicable"] == 0
    assert tx["Receiver CRC"] == "N/A"
    assert rx["Receiver CRC applicable"] == 1 and rx["Receiver CRC"] == 0
    assert rx["Message SHA256"] == "N/A"
    assert rx["SRB1 installed after event"] == 1
    assert rx["Runtime slot (1-based)"] == 15 and rx["Absolute slot (0-based)"] == 14
    assert rx["Full MAC/RRC standards qualified"] == 0
    assert rx["Status scope"] == "bounded_protocol_transition_not_PHY_CRC"
    # No absent decoded identity can be supplied by the UI.
    assert dashboard.summarize_procedure_preview_rows("rrc_connection_events", [{}]) == [{}]


def test_pdcch_preview_retains_independent_nmse_operands_and_scope() -> None:
    source = dict(PDCCHSelectedCCEIndex=4, NMSEScoringAvailable=True,
                  ChannelNMSEReferencePlane="executed_effective_DMRS_port",
                  ChannelNMSEQualificationMode="no_gain_or_phase_fit",
                  ChannelNMSEPilotResourceCount=36,
                  ChannelNMSEComparedComplexValues=144,
                  ChannelNMSEErrorEnergy=2, ChannelNMSEReferenceEnergy=200,
                  ChannelNMSEGainOrPhaseFitted=False, NMSE_dB=-20)
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["pdcch_trials"])
    preview = dashboard.summarize_control_trial_preview_rows("pdcch_trials", [source])[0]
    for field, value in source.items():
        assert preview[labels[field]] == value


def test_csi_preview_separates_reference_slot_decoded_rank_and_scheduler_admission() -> None:
    source = dict(UEIndex=1, RNTI=1, SourceSlot=9, CSIReferenceSlot=9, DueSlot=19, DeliveredSlot=19,
                  SourceSlotAuthority="configured_CSI_reference_resource_not_UE_measurement_slot",
                  RI=2, PMI=20, CRI=0, CQI=14, CSIUCIDecodeOk=1,
                  SchedulerAcceptedRank=1, SchedulerSpatialDecisionDeferred=1,
                  RankIncreaseConfirmationCount=1, RankIncreaseRequiredCount=2,
                  RankUpdateStatus="pending_increase_confirmation", Processed=1,
                  SINR_dB="NaN", SINRSource="not_reported_in_CSI_payload",
                  MCSIndex="NaN", UEReferenceRecordJSON='{"SourceSlot":6,"SINR_dB":22}')
    preview = dashboard.summarize_procedure_preview_rows("csi_report", [source])[0]
    assert preview["CSI reference-resource slot"] == 9
    assert preview["Reference-slot authority"] == source["SourceSlotAuthority"]
    assert preview["RI"] == 2 and preview["Scheduler rank"] == 1
    assert preview["Spatial decision held"] == 1 and preview["Processed"] == 1
    assert preview["Rank confirmations"] == 1 and preview["Required confirmations"] == 2
    assert preview["SINR wire status"] == "not_reported_in_CSI_payload"
    assert "CSI-RS source slot" not in preview
    for field in ("Selected MCS", "CSI SINR dB"):
        value = dashboard.coerce_numeric(preview.get(field))
        assert value is None or not math.isfinite(value)
    poisoned = dict(source, UEReferenceRecordJSON='{"SourceSlot":999,"SINR_dB":999,"RI":4}')
    assert dashboard.summarize_procedure_preview_rows("csi_report", [poisoned])[0] == preview


def _delivered_ul_quality_report() -> dict:
    return dict(Direction="UL", UEIndex=1, RNTI=4660, SourceSlot=50,
                DueSlot=51, DeliveredSlot=51, ReportIdentity="UL_UE1_SRC50_DUE51",
                SourceSignal="PUSCH-DMRS", Processed=1,
                DeliveryStatus="delivered_to_runtime_scheduler",
                AdaptationDeliveryStatus="accepted_new_feedback_delivery",
                CSIUCIDecodeOk=0, CSIUCICRCPass="NaN", CSIUCITransport="not_scheduled",
                CQI=14, RI=1, PMI=0, SchedulerResolvedCQI=13,
                RawCQIDerivedMCS=26, MCSIndex=24, LinkAdaptationMCSIndex=24,
                Modulation="64QAM", SchedulerAcceptedRank=1,
                SchedulerSpatialDecisionDeferred=0, RankIncreaseConfirmationCount=0,
                RankIncreaseRequiredCount=2, RankUpdateStatus="not_requested",
                MCSSelectionSource="runtime_cqi_to_amc")


def test_pending_dl_csi_does_not_claim_received_uci_or_selected_mcs() -> None:
    raw = dict(Direction="DL", UEIndex=1, RNTI=4660, SourceSlot=46,
               DueSlot=59, DeliveredSlot="NaN", ReportIdentity="pending_DL_59",
               SourceSignal="CSI-RS", Processed=0,
               DeliveryStatus="pending_receiver_decoded_csi_uci",
               CSIUCIDecodeOk=0, CSIUCITransport="pucch", CQI=14, RI=1, PMI=7,
               RawCQIDerivedMCS=26, MCSIndex=26, Modulation="64QAM",
               LinkAdaptationMCSIndex="NaN", SchedulerSpatialDecisionDeferred=0)
    before = dict(raw)
    view = dashboard.summarize_procedure_preview_rows("csi_report", [raw])[0]
    assert view["Feedback evidence scope"] == "pending_report_not_received"
    assert view["Direction"] == "DL" and view["Report identity"] == "pending_DL_59"
    assert view["Raw CQI-derived MCS"] == 26 and view["Stored MCS field"] == 26
    assert view["Selected MCS"] is None
    assert view["MCS decision status"] == "no_delivered_scheduler_decision"
    assert view["UCI interpretation"] == "pending_transport_not_decode_failure"
    assert raw == before, "The view must not rewrite a retained producer row."


def test_ul_quality_delivery_is_not_a_failed_uci_decode() -> None:
    raw = _delivered_ul_quality_report()
    before = dict(raw)
    view = dashboard.summarize_procedure_preview_rows("csi_report", [raw])[0]
    assert view["Feedback evidence scope"] == "delivered_gnb_local_ul_feedback"
    assert view["UCI interpretation"] == "not_applicable_gnb_local_ul_feedback"
    assert view["Source signal"] == "PUSCH-DMRS"
    assert view["Raw CQI-derived MCS"] == 26 and view["Selected MCS"] == 24
    assert view["MCS decision status"] == "accepted_for_future_grants_not_executed_trial"
    assert view["UCI decode"] == 0, "Keep the raw stored flag alongside its correct scope."
    assert raw == before
    strings = {k: str(v) for k, v in raw.items()}
    parsed = dashboard.summarize_procedure_preview_rows("csi_report", [strings])[0]
    for key in ("Feedback evidence scope", "UCI interpretation", "MCS decision status", "Selected MCS"):
        assert parsed[key] == view[key]


def test_csi_selection_requires_causal_received_and_accepted_evidence() -> None:
    raw = _delivered_ul_quality_report()
    changes = [dict(Processed=0), dict(Processed="NaN"), dict(DeliveredSlot="NaN"),
               dict(DeliveredSlot=49), dict(DeliveredSlot=50.5), dict(DueSlot=49),
               dict(DeliveryStatus="pending_causal_feedback_delay"),
               dict(AdaptationDeliveryStatus="ignored_duplicate_feedback_delivery"),
               dict(SchedulerSpatialDecisionDeferred=1),
               dict(SchedulerSpatialDecisionDeferred="NaN"),
               dict(SchedulerResolvedCQI=0), dict(LinkAdaptationMCSIndex="NaN"),
               dict(LinkAdaptationMCSIndex=25), dict(MCSIndex=24.5),
               dict(MCSIndex="Inf"), dict(Direction=""), dict(SourceSignal="configured"),
               dict(SchedulerAcceptedRank=4), dict(RI="NaN"), dict(RI=1.5),
               dict(CSIUCIDecodeOk=1), dict(CSIUCITransport="pucch_decoded")]
    for change in changes:
        view = dashboard.summarize_procedure_preview_rows("csi_report", [{**raw, **change}])[0]
        assert view["Selected MCS"] is None, change
        assert view["Stored MCS field"] == change.get("MCSIndex", raw["MCSIndex"])


def test_received_dl_uci_rank_hold_is_separate_from_candidate_mcs() -> None:
    raw = {**_delivered_ul_quality_report(), "Direction": "DL",
           "SourceSignal": "received_CSI_UCI", "CSIUCIDecodeOk": 1,
           "CSIUCITransport": "pucch_decoded", "SchedulerSpatialDecisionDeferred": 1,
           "RankUpdateStatus": "pending_increase_confirmation", "RI": 2,
           "RankIncreaseConfirmationCount": 1, "LinkAdaptationMCSIndex": "NaN",
           "MCSIndex": "NaN"}
    view = dashboard.summarize_procedure_preview_rows("csi_report", [raw])[0]
    assert view["Feedback evidence scope"] == "received_dl_csi_uci"
    assert view["UCI interpretation"] == "independently_decoded_dl_csi_feedback"
    assert view["MCS decision status"] == "held_spatial_operating_point"
    assert view["RI"] == 2 and view["Scheduler rank"] == 1 and view["Selected MCS"] is None
    accepted = {**raw, "SchedulerSpatialDecisionDeferred": 0,
                "SchedulerAcceptedRank": 2, "MCSIndex": 24, "LinkAdaptationMCSIndex": 24}
    assert dashboard.summarize_procedure_preview_rows("csi_report", [accepted])[0]["Selected MCS"] == 24


def test_csi_browser_panel_preserves_source_identity_and_decision_scope(tmp_path: Path) -> None:
    raw = [{**_delivered_ul_quality_report(), "SweepPointIndex": point,
            "ConfiguredSNR_dB": 40, "ReportIdentity": f"point_{point}_UL50"}
           for point in (1, 2)]
    path = tmp_path / "csi_feedback_reports.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(raw[0]))
        writer.writeheader()
        writer.writerows(raw)
    before = path.read_bytes()
    artifact = dict(artifact_id=-212, logical_path="air_interface/csv/csi_feedback_reports.csv",
                    filesystem_path=str(path), byte_size=path.stat().st_size,
                    artifact_kind="csv", mime_type="text/csv")
    context = dashboard.extract_runtime_context(dict(run_id=-212, status="running"), [artifact])
    preview = context["procedure_previews"]["csi_report"]
    assert [row["Sweep point"] for row in preview] == [1, 2]
    assert [row["Report identity"] for row in preview] == [r["ReportIdentity"] for r in raw]
    assert all(row["Selected MCS"] == 24 for row in preview)
    assert path.read_bytes() == before
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    panel = next(line.strip().rstrip(",") for line in source.splitlines()
                 if "{id:'csi_report', title:" in line)
    script = ("const csiReportRows=" + json.dumps(preview) + ";\n"
              "const procedureSelection={csi_report:'air_interface/csv/csi_feedback_reports.csv'};\n"
              "const selectedPath=x=>x; const spec=" + panel + ";\n"
              "console.log(JSON.stringify(spec));")
    actual = json.loads(subprocess.run([node, "-e", script], capture_output=True,
                                      text=True, check=True, timeout=15).stdout)
    assert "pending reports" in actual["title"] and "local UL measurements" in actual["title"]
    for column in ("Direction", "Sweep point", "Report identity", "Source signal",
                   "Feedback evidence scope", "UCI interpretation", "Raw CQI-derived MCS",
                   "Stored MCS field", "Selected MCS", "MCS decision status"):
        assert column in actual["columns"]
    assert actual["rows"] == preview
    assert "not proof of an executed data trial" in actual["sourcePath"]


def test_received_csi_file_does_not_hide_pending_or_local_ul_feedback(tmp_path: Path) -> None:
    local_ul = _delivered_ul_quality_report()
    pending = {**local_ul, "Direction": "DL", "SourceSignal": "CSI-RS",
               "ReportIdentity": "pending_DL59", "SourceSlot": 46, "DueSlot": 59,
               "DeliveredSlot": "NaN", "Processed": 0, "CSIUCITransport": "pucch",
               "DeliveryStatus": "pending_receiver_decoded_csi_uci"}
    received = {**local_ul, "Direction": "DL", "SourceSignal": "received_CSI_UCI",
                "ReportIdentity": "received_DL49", "CSIUCIDecodeOk": 1,
                "CSIUCITransport": "pucch_decoded"}
    artifacts = []
    for filename, rows in [("csi_feedback_reports.csv", [pending, local_ul]),
                            ("received_csi_reports.csv", [received])]:
        path = tmp_path / filename
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        artifacts.append(dict(artifact_id=-len(artifacts)-300,
            logical_path="air_interface/csv/"+filename, filesystem_path=str(path),
            byte_size=path.stat().st_size, artifact_kind="csv", mime_type="text/csv"))
    context = dashboard.extract_runtime_context(dict(run_id=-300, status="running"), artifacts)
    views = context["procedure_previews"]
    assert [row["Report identity"] for row in views["csi_report"]] == [
        "pending_DL59", local_ul["ReportIdentity"]]
    assert [row["Report identity"] for row in views["received_csi_report"]] == ["received_DL49"]
    assert views["csi_report"][0]["Selected MCS"] is None
    assert views["received_csi_report"][0]["Feedback evidence scope"] == "received_dl_csi_uci"
    # No UE-reference values may be joined into the independently received row.
    assert views["received_csi_report"][0]["Source signal"] == "received_CSI_UCI"
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    panel = next(line for line in source.splitlines() if "{id:'received_csi_report'," in line)
    assert "rows:receivedCSIReportRows" in panel
    assert "procedureSelection.received_csi_report" in panel


def test_empty_canonical_csi_table_is_not_replaced_by_stale_mirror(tmp_path: Path) -> None:
    raw = _delivered_ul_quality_report()
    for key, name in [("csi_report", "csi_feedback_reports.csv"),
                       ("received_csi_report", "received_csi_reports.csv")]:
        artifacts = []
        for prefix, rows in [("air_interface", []), ("control", [raw])]:
            path = tmp_path / (prefix+"_"+name)
            with path.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(raw))
                writer.writeheader()
                writer.writerows(rows)
            artifacts.append(dict(artifact_id=-len(artifacts)-400,
                logical_path=prefix+"/csv/"+name, filesystem_path=str(path),
                byte_size=path.stat().st_size))
        preview, source = dashboard.load_procedure_preview(artifacts,key,
            ["air_interface/csv/"+name, "control/csv/"+name])
        assert preview == [], "A committed empty canonical table owns its lifecycle state."
        assert source["selection_status"] == "canonical_empty"
        assert source["selected_logical_path"] == "air_interface/csv/"+name
        assert source["fallback_used"] is False


def test_data_cfo_preview_separates_receiver_measurement_from_simulation_reference() -> None:
    for direction in ("dl_trials", "ul_trials"):
        labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS[direction])
        assert labels["ResidualCFO_PostCorrection_Hz"] == "Simulation-reference residual CFO (Hz)"
        assert labels["ResidualCFO_EstimatedPostCorrection_Hz"] == "Post-correction frequency estimate (Hz)"
        assert labels["ResidualCFOEstimateRole"] == "Residual estimate evidence role"
        assert labels["ResidualCFOReusesAcquisitionObservation"] == "Reuses acquisition observation"
        assert labels["ResidualCFOEstimateSource"] == "Residual estimator source"
        assert labels["CFOCorrectionApplied_Hz"] == "Applied CFO correction (Hz)"
        role = "same_observation_estimator_consistency_not_independent_residual"
        preview = dashboard.summarize_data_trial_preview_rows(direction, [{
            "ResidualCFO_PostCorrection_Hz": -70,
            "ResidualCFO_EstimatedPostCorrection_Hz": 0,
            "ResidualCFOEstimateRole": role,
            "ResidualCFOReusesAcquisitionObservation": 1,
        }])[0]
        assert preview["Simulation-reference residual CFO (Hz)"] == -70
        assert preview["Post-correction frequency estimate (Hz)"] == 0
        assert preview["Residual estimate evidence role"] == role
        assert preview["Reuses acquisition observation"] == 1


def test_data_pilot_preview_retains_phase_measurements_without_doppler_claim() -> None:
    source = {
        "PilotCommonPhaseRate_Hz": 125,
        "PilotPhaseFitResidualRMS_deg": .2,
        "PilotPhasePairCount": 2,
        "PilotPhaseUnaliasedHalfWidth_Hz": 1500,
        "PilotPhaseEvolutionSource": "matched_pilot_channel_cross_products_common_phase_not_doppler_spread",
        "PilotPhaseEvolutionStatus": "measured_common_phase_rate_with_explicit_alias_interval",
        "DopplerMeasurementStatus": "not_measured_common_phase_rate_is_not_maximum_Doppler_or_spread",
    }
    for direction in ("dl_trials", "ul_trials"):
        labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS[direction])
        preview = dashboard.summarize_data_trial_preview_rows(direction, [source])[0]
        for field, value in source.items():
            assert preview[labels[field]] == value
        assert "not Doppler spread" in labels["PilotCommonPhaseRate_Hz"]
        assert "not tracking accuracy" in labels["PilotPhaseFitResidualRMS_deg"]
        missing = dashboard.summarize_data_trial_preview_rows(direction, [{"Slot": 43}])[0]
        assert dashboard.coerce_numeric(missing.get(labels["PilotCommonPhaseRate_Hz"])) is None


def test_ul_preview_keeps_codebook_ports_distinct_from_spatial_beams() -> None:
    labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["ul_trials"])
    assert labels["AppliedPrecoderPMI"] == "Applied TPMI"
    assert labels["AppliedCodebookPortIndexSet"] == "Codebook ports (1-based)"
    assert labels["PrecodingNumLogicalPorts"] == "Logical ports"
    assert labels["AppliedBeamIndexSet"] == "Applied spatial beam"
    assert "AppliedCodebookPortIndexSet" not in dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["dl_trials"])


def test_access_and_beam_previews_retain_exact_runtime_identity() -> None:
    msg1 = dashboard.summarize_procedure_preview_rows(
        "msg1_detection",
        [{
            "UEId": 1,
            "Slot": 9,
            "AssociatedSSBIndex": 1,
            "RootSequenceIndex": 7,
            "PreambleIndexTx": 11,
            "PreambleIndexDetected": 11,
            "FrequencyEstimationEnabled": 1,
            "FrequencyEstimate_Hz": -125.0,
            "FrequencyEstimateValid": 1,
            "RawTimingEstimate_samples": 1258,
            "TimingOffsetSamples": 22,
            "TimingAdvanceCommand": 1,
            "RARNTI": 127,
            "Status": "OK",
        }],
    )
    assert msg1 == [{
        "UE": 1,
        "Slot in frame (0-based)": 9,
        "Associated SSB beam": 1,
        "Root sequence index (RSI)": 7,
        "TX preamble": 11,
        "Strongest detected preamble": 11,
        "Frequency estimate enabled": 1,
        "Detected frequency offset Hz": -125.0,
        "Frequency estimate valid": 1,
        "Raw timing samples": 1258,
        "Propagation timing samples": 22,
        "RAR TA command": 1,
        "RA-RNTI": 127,
        "Status": "OK",
    }]
    beam = dashboard.summarize_procedure_preview_rows(
        "beam_state",
        [{
            "EventSequence": 4,
            "UEIndex": 1,
            "Slot": 28,
            "FromState": "P2_MEASURING",
            "Event": "TCI_ACTIVATED",
            "ToState": "ACTIVE",
            "MeasuredResourceID": "CSI-RS-3",
            "ActivatedTCIState": 3,
            "GeometryOracleUsed": 0,
            "SelectionAuthority": "receiver_measurement_and_decoded_control",
        }],
    )
    assert beam[0]["Measured RS/beam"] == "CSI-RS-3"
    assert beam[0]["Activated TCI state"] == 3
    assert beam[0]["Geometry oracle used"] == 0


def test_ra_rf_preview_preserves_endpoint_and_unknown_without_decode_claim() -> None:
    for missing in ("NaN", "nan", "<missing>", "null", float("nan")):
        assert dashboard.normalize_preview_value(missing) is None
    assert dashboard.normalize_preview_value(0) == 0
    assert dashboard.normalize_preview_value("measurement_unavailable_no_independent_reference") is not None
    rows = [dict(UEId=1, AttemptId=2, StageName="RARMonitoring", Direction="DL",
                 RuntimeSlot=11, ConfiguredSNR_dB=40, TransmitterID="gnb_1",
                 ReceiverID="ue_1_rx", ObservationID="rar_11", DACBits=12,
                 DACFullScale=.007, DACClippingRatio="NaN",
                 DACClippingStatus="unavailable_cropped_execution_population",
                 IQImbalanceApplied=1, ADCBits=12,
                 EvidenceScope="actual_receive_window_RF_execution_not_decode_or_attachment_result"),
            dict(UEId=1, AttemptId=2, StageName="Msg3", Direction="UL",
                 RuntimeSlot=15, ConfiguredSNR_dB=40, TransmitterID="ue_1",
                 ReceiverID="gnb_1_rx", ObservationID="msg3_15", DACBits=12,
                 DACFullScale=.028, IQImbalanceApplied="NaN", ADCBits=12)]
    views = dashboard.summarize_procedure_preview_rows("ra_receiver_rf", rows)
    assert views[0]["RX endpoint"] == "ue_1_rx"
    assert views[1]["RX endpoint"] == "gnb_1_rx"
    assert views[0]["TX DAC full scale"] == .007
    assert views[1]["TX DAC full scale"] == .028
    assert views[1]["RX IQ imbalance applied"] == "N/A"
    assert "TX DAC clipping fraction" not in views[0]
    assert "Status" not in views[0] and "CRC" not in views[0]
    script = dashboard.product_frontend_script()
    rendered = next(line for line in script.splitlines() if "id:'ra_receiver_rf'" in line)
    for label in ("Receive window", "RX endpoint", "TX DAC full scale", "Evidence scope"):
        assert f"'{label}'" in rendered
    source = (ROOT / "apps" / "lls_web_dashboard.py").read_text(encoding="utf-8")
    assert '"ra_receiver_rf": ["control/csv/ra_receiver_rf_observations.csv"]' in source


def test_ra_receiver_diagnostics_keep_distinct_measured_planes_and_unknowns() -> None:
    row = dict(UEId=1, ScheduledSlot=14, ReceiverDiagnosticsPresent=1,
               EstimatedCFO_Hz=-401.25, CFOCorrectionApplied_Hz=-401.25,
               ReceiverHestSINR_dB=29.3, PostEqSINR_dB=39.8,
               PostEqSINRValueStatus="OK_decision_residual_bounded",
               ResidualCFO_EstimatedPostCorrection_Hz="NaN",
               ResidualCFOEstimatorConsistency_Hz=0,
               ResidualCFOReusesAcquisitionObservation=1,
               ResidualCFOEstimateRole="same_window_not_independent")
    for key in ("ra_rx_msg2", "ra_rx_msg3", "ra_rx_msg4", "ra_rx_setup"):
        value = dict(row, Msg2Slot=10)
        out = dashboard.summarize_procedure_preview_rows(key, [value])[0]
        assert out["Pilot/Hest SINR (dB)"] == 29.3
        assert out["Post-equalizer SINR (dB)"] == 39.8
        assert out["Estimated CFO (Hz)"] == -401.25
        assert out["Same-estimator consistency (Hz)"] == 0
        assert out["Residual role"] == "same_window_not_independent"
        assert "Post-correction CFO estimate (Hz)" not in out
        assert out["Absolute slot (0-based)"] == (10 if key == "ra_rx_msg2" else 14)
    script = dashboard.product_frontend_script()
    assert "...raDiagnosticTables" in script and "receiver synchronization and SINR definitions" in script
    assert "...rows.flatMap(row => Object.keys(row))" in script


def test_ra_waveform_preview_separates_prepared_ports_and_physical_dimensions() -> None:
    rows = [
        {"StageName": "Msg2", "TxPortCount": 1,
         "RuntimeChannelPhysicalTxElements": 64, "RxPortCount": 4,
         "TxPortToElementMappingSource": "selected_ssb_beam"},
        {"StageName": "Msg3", "TxPortCount": 4,
         "RuntimeChannelPhysicalTxElements": 4, "RxPortCount": 64,
         "TxPortToElementMappingSource": "runtime_antenna_mapping"},
    ]
    views = dashboard.summarize_procedure_preview_rows("ra_stage_waveforms", rows)
    by_stage = {row["Stage"]: row for row in views}
    assert by_stage["Msg2"]["Prepared TX ports"] == 1
    assert by_stage["Msg2"]["Physical TX dimensions"] == 64
    assert by_stage["Msg2"]["Received RX dimensions"] == 4
    assert by_stage["Msg2"]["TX port-to-element mapping"] == "selected_ssb_beam"
    assert by_stage["Msg3"]["Prepared TX ports"] == 4
    assert by_stage["Msg3"]["Physical TX dimensions"] == 4
    assert by_stage["Msg3"]["Received RX dimensions"] == 64
    missing = dashboard.summarize_procedure_preview_rows(
        "ra_stage_waveforms", [{"StageName": "Msg2", "TxPortCount": 1}],
    )[0]
    assert "Physical TX dimensions" not in missing
    assert "Received RX dimensions" not in missing
    # The browser has a separate explicit column list; payload-only coverage
    # would pass while leaving the newly available evidence invisible.
    rendered = next(line for line in dashboard.product_frontend_script().splitlines()
                    if "id:'ra_stage_waveforms'" in line)
    for label in ("Prepared TX ports", "Physical TX dimensions",
                  "Received RX dimensions", "TX port-to-element mapping"):
        assert f"'{label}'" in rendered


def test_shared_msg1_preview_keeps_set_target_and_unknown_false_alarm_separate() -> None:
    row = dict(UEId=1, Frame=1, Slot=4, Msg1ScheduledSlot=14,
               PreambleIndexTx=0, PreambleIndexDetected=1, DetectedPreambleSet="1|0",
               DetectedPreambleSetAvailable=1, MissedDetection=0, FalseAlarm="NaN",
               FalseAlarmStatus="unavailable_complete_transmitted_occasion_set_not_retained",
               DetectionMetric=0.4983, DetectionThreshold=0.0144)
    view = dashboard.summarize_procedure_preview_rows("msg1_detection", [row])[0]
    assert view["Strongest detected preamble"] == 1
    assert view["TX preamble"] == 0 and view["Received preamble set"] == "1|0"
    assert view["Target preamble missed"] == 0
    assert view["Detection metric"] == 0.4983 and view["Threshold"] == 0.0144
    assert "False alarm" not in view
    assert view["False alarm applicability"] == row["FalseAlarmStatus"]
    assert view["Frame"] == 1 and view["Slot in frame (0-based)"] == 4
    assert view["Absolute slot (0-based)"] == 14
    assert dashboard.summarize_procedure_preview_rows("msg1_detection", [{}]) == [{}]


def test_ssb_sync_preview_separates_injection_estimate_correction_and_residual() -> None:
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["pbch_trials"])
    assert labels["InjectedCFO_Hz"] == "Configured / injected CFO (Hz)"
    assert labels["EstimatedCFO_PreCorrection_Hz"] == "Estimated CFO (Hz)"
    assert labels["CFOEstimateAvailability"] == "CFO estimate availability"
    assert labels["CFOCorrectionApplied_Hz"] == "Applied CFO correction (Hz)"
    assert labels["SIB1CFOCorrectionApplied_Hz"] == "SIB1 applied CFO correction (Hz)"
    assert labels["ResidualCFO_PostCorrection_Hz"] == "Oscillator-only residual CFO (Hz)"
    assert labels["ResidualCFOMeasurementStatus"] == "Oscillator-only residual status"
    assert labels["PBCHResidualCommonFrequency_Hz"] == "PBCH post-correction common frequency (Hz)"
    assert labels["PBCHResidualFrequencyIndependentCapture"] == "Independent residual capture"
    source = dict(PBCHResidualCommonFrequency_Hz=-24.5, PBCHResidualFrequencyAvailable=1,
                  PBCHResidualFrequencyIndependentCapture=0, ResidualCFO_PostCorrection_Hz=None)
    view = dashboard.summarize_control_trial_preview_rows("pbch_trials", [source])[0]
    assert view[labels["PBCHResidualCommonFrequency_Hz"]] == -24.5
    assert view[labels["PBCHResidualFrequencyIndependentCapture"]] == 0
    assert labels["AppliedTimingCorrection_samples"] == "Applied timing correction (samples)"


def test_dl_sync_renderer_retains_actual_corrections_and_distinct_residuals() -> None:
    pbch = dashboard.summarize_control_trial_preview_rows("pbch_trials", [dict(
        Slot=1, UEID=1, SSBIndex=0, InjectedCFO_Hz=400,
        EstimatedCFO_PreCorrection_Hz=414.607588654777,
        CFOCorrectionApplied=1, CFOCorrectionApplied_Hz=414.607588654777,
        CFOCorrectionSource="received_PSS_CP_estimate_capture_local_sample_clock",
        CFOCorrectionSampleOrigin=0,
        SIB1CFOCorrectionApplied_Hz=123, SIB1CFOCorrectionSource="different_SI_stage",
        ResidualCFO_PostCorrection_Hz="NaN",
        ResidualCFOMeasurementStatus="unavailable_oscillator_only_residual_not_identifiable",
        PBCHResidualCommonFrequency_Hz=9878.28369293019,
        PBCHResidualFrequencyAvailable=1, PBCHResidualFrequencyStatus="OK",
        PBCHResidualFrequencySource="received_PBCH_DMRS_after_PSS_CP_frequency_correction",
        PBCHResidualFrequencyRole="common_frequency_includes_channel_phase_evolution_not_oscillator_only",
        PBCHResidualFrequencyIndependentCapture=0,
        EstimatedTimingOffset_PreCorrection_samples=2217,
        AppliedTimingCorrection_samples=2217, InjectedTimingOffset_samples=1,
        ResidualTimingError_PostCorrection_samples="NaN")])
    trs = dashboard.summarize_control_trial_preview_rows("trs_trials", [dict(
        Slot=7, UEIndex=1, EstimatedCFO_Hz=419.575771483581,
        CFOCorrectionApplied=1, CFOCorrectionApplied_Hz=419.575771483581,
        CFOCorrectionSource="received_TRS_window_absolute_clock", CFOCorrectionSampleOrigin=92160,
        ResidualCFO_EstimatedPostCorrection_Hz=-21.2931666848223,
        ResidualCFOEstimateAvailable=1, ResidualCFOEstimateSource="TRS_phase_slope_after_correction",
        ResidualCFOEstimateRole="received_common_frequency_not_separated_oscillator",
        ResidualCFOReusesAcquisitionObservation=1, ResidualFrequencyUsesDifferentObservable=1,
        ResidualFrequencyStatus="measured_received_common_frequency_after_correction",
        TRSTimingEstimate_samples=9, AppliedTimingCorrection_samples=9,
        TimingError_samples=0, TimingScoringReferenceSource="original_TRS_correlation_reference",
        ResidualTimingError_PostCorrection_samples="NaN")])
    pdsch = dashboard.summarize_data_trial_preview_rows("dl_trials", [dict(
        Slot=41, UEIndex=1, CFOCorrectionApplied_Hz=400, CFOCorrectionApplied=1,
        ResidualCFO_PostCorrection_Hz=-5, ResidualCFO_EstimatedPostCorrection_Hz=-7,
        ResidualCFOEstimateAvailable=1, ResidualCFOEstimateSource="DMRS_phase_rate",
        ResidualCFOEstimateRole="common_frequency", ResidualCFOReusesAcquisitionObservation=1)])
    rows = _evaluate_dl_sync_projection(dict(pbch_trials=pbch, trs_trials=trs), dict(dl_trials=pdsch))
    ssb, tracking, data = rows
    assert ssb["Applied CFO correction (Hz)"] == 414.607588654777
    assert ssb["Correction source"] == "received_PSS_CP_estimate_capture_local_sample_clock"
    assert ssb["CFO correction sample origin"] == 0
    assert ssb["Timing estimate (samples)"] == 2217
    assert ssb["Post-correction measured frequency (Hz)"] == 9878.28369293019
    assert ssb["Independent residual capture"] == 0
    assert "Oscillator-only residual CFO (Hz)" not in ssb
    assert ssb["Oscillator-only residual status"].startswith("unavailable_")
    assert "Residual timing error (samples)" not in ssb
    assert tracking["Applied CFO correction (Hz)"] == 419.575771483581
    assert tracking["Post-correction measured frequency (Hz)"] == -21.2931666848223
    assert tracking["CFO correction sample origin"] == 92160
    assert tracking["Timing estimate (samples)"] == tracking["Applied timing correction (samples)"] == 9
    assert tracking["Timing estimation error vs scoring reference (samples)"] == 0
    assert "Residual timing error (samples)" not in tracking
    assert tracking["Reuses acquisition observation"] == 1
    assert data["Applied CFO correction (Hz)"] == 400
    assert data["Simulation-reference residual CFO (Hz)"] == -5
    assert data["Post-correction measured frequency (Hz)"] == -7
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    panel = source.split("{id:'ssb_sync_timing', title:", 1)[1].split("rows:recent", 1)[0]
    for label in ("Detected SSB position before correction (samples)",
                  "Oscillator-only residual status", "PBCH post-correction common frequency (Hz)",
                  "CFO correction sample origin"):
        assert label in panel
    assert "'Timing estimate before correction (samples)'" not in panel
    assert "'Residual CFO (Hz)'" not in panel
    combined_panel = source.split("{id:'dl_sync', title:", 1)[1].split("rows:dlSynchronizationRows", 1)[0]
    assert "dlSynchronizationRows.flatMap(row => Object.keys(row))" in combined_panel


def test_dl_sync_does_not_infer_applied_correction_from_estimate_or_sib1() -> None:
    pbch = dashboard.summarize_control_trial_preview_rows("pbch_trials", [dict(
        EstimatedCFO_PreCorrection_Hz=400, SIB1CFOCorrectionApplied_Hz=350,
        CFOCorrectionApplied_Hz="NaN", PBCHResidualFrequencyAvailable=0)])
    row = _evaluate_dl_sync_projection(dict(pbch_trials=pbch, trs_trials=[]), dict(dl_trials=[]))[0]
    assert row["Estimated CFO (Hz)"] == 400
    assert "Applied CFO correction (Hz)" not in row
    assert "Post-correction measured frequency (Hz)" not in row
    assert row["Post-correction estimate available"] == 0


def _evaluate_dl_sync_projection(control, data):
    return _evaluate_sync_projection(control, data)["dl"]


def _evaluate_sync_projection(control, data):
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    block = source.split("    const receiverFrequencyFields =", 1)[1].split("    const tableSpecs =", 1)[0]
    script = ("const recent = v => v || []; const controlPreviews=" + json.dumps(control) +
              "; const dataPreviews=" + json.dumps(data) +
              "; const msg1Rows=[]; const receiverFrequencyFields =" + block +
              "console.log(JSON.stringify({dl:dlSynchronizationRows,ul:ulSynchronizationRows}));")
    result = subprocess.run([node, "-e", script], capture_output=True, text=True,
                            encoding="utf-8", check=True, timeout=15)
    return json.loads(result.stdout)


def test_four_channel_sync_original_frequency_fields_and_rendered_rows() -> None:
    # Declared CSV metadata, not native receiver or campaign qualification.
    source = dict(Slot=17, UEID=2, EstimatedCFO_Hz=-125.25,
                  EstimatedCommonFrequency_Hz=-125.25,
                  CFOEstimateAvailable=1, CFOEstimateAvailability="legacy_status_separate",
                  CFOEstimateSource="declared_original_receiver", CFOCorrectionEnabled=1,
                  CFOCorrectionApplied=1, CFOCorrectionApplied_Hz=-125.25,
                  CFOCorrectionSource="declared_original_operator", CFOCorrectionSampleOrigin=0,
                  CFOCorrectionAbsoluteSampleOrigin=1234,
                  CFOCorrectionClockSource="original_capture_plus_timing",
                  FrequencyEstimateDomain="received_common_frequency_not_oscillator_only",
                  FrequencyCorrectionStatus="available",
                  ResidualCFOEstimatorConsistency_Hz=0,
                  ResidualCFOEstimateAvailable=1, ResidualCFOReusesAcquisitionObservation=1,
                  ResidualCFOEstimateRole="same_observation_estimator_consistency_not_independent_residual",
                  ReceiverFrequencyEvidenceSHA256="a" * 64,
                  ResidualCFO_PostCorrection_Hz="NaN", ResidualCFO_EstimatedPostCorrection_Hz="NaN")
    before = dict(source)
    control = {key: dashboard.summarize_control_trial_preview_rows(key, [source])
               for key in ("pdcch_trials", "pucch_trials")}
    data = {key: dashboard.summarize_data_trial_preview_rows(key, [source])
            for key in ("dl_trials", "ul_trials")}
    projected = _evaluate_sync_projection(control, data)
    assert {row["Stage"] for row in projected["dl"]} == {"PDCCH receiver", "PDSCH receiver"}
    assert {row["Stage"] for row in projected["ul"]} == {"PUCCH receiver", "PUSCH receiver"}
    for row in projected["dl"] + projected["ul"]:
        assert row["Receiver frequency estimate (Hz)"] == -125.25
        assert row["Receiver estimate available (boolean)"] == 1
        assert row["Applied CFO correction (Hz)"] == -125.25
        assert row["Correction source"] == "declared_original_operator"
        assert row["CFO correction sample origin"] == 0
        assert row["CFO correction absolute sample origin"] == 1234
        assert row["Same-observation estimator consistency (Hz)"] == 0
        assert row["Residual evidence role"] == source["ResidualCFOEstimateRole"]
        assert row["Reuses acquisition observation"] == 1
        assert row["Receiver frequency evidence SHA256"] == "a" * 64
        assert "Post-correction measured frequency (Hz)" not in row
        assert "Simulation-reference residual CFO (Hz)" not in row
    assert source == before
    script = Path(dashboard.__file__).read_text(encoding="utf-8")
    ul_panel = script.split("{id:'ul_sync', title:", 1)[1].split("rows:ulSynchronizationRows", 1)[0]
    assert "ulSynchronizationRows.flatMap(row => Object.keys(row))" in ul_panel


def test_four_channel_sync_disabled_unavailable_and_legacy_not_invented() -> None:
    for key, summarize in [("pdcch_trials", dashboard.summarize_control_trial_preview_rows),
                           ("pucch_trials", dashboard.summarize_control_trial_preview_rows),
                           ("dl_trials", dashboard.summarize_data_trial_preview_rows),
                           ("ul_trials", dashboard.summarize_data_trial_preview_rows)]:
        rows = summarize(key, [dict(Slot=1, CFOCorrectionEnabled=0,
                                   CFOCorrectionApplied=0, CFOEstimateAvailable=0,
                                   CFOCorrectionApplied_Hz="NaN", EstimatedCFO_Hz="NaN",
                                   FrequencyCorrectionStatus="disabled_by_receiver_configuration"),
                               dict(Slot=2, EstimatedCFO_Hz=400,
                                    CFOEstimateAvailability="legacy_only")])
        assert rows[0]["CFO correction applied"] == 0
        assert rows[0]["Receiver frequency estimate available"] == 0
        assert rows[1]["CFO correction applied"] == "N/A"
        assert rows[1]["CFO estimate availability"] == "legacy_only"
        assert rows[1]["Receiver frequency estimate available"] == "N/A"
        assert all("Applied CFO correction (Hz)" not in row for row in rows)
        assert all("Same-observation estimator consistency (Hz)" not in row for row in rows)
        control = {key: rows} if key in ("pdcch_trials", "pucch_trials") else {}
        data = {key: rows} if not control else {}
        projected = _evaluate_sync_projection(control, data)
        actual = projected["dl"] + projected["ul"]
        assert len(actual) == 2
        assert all("Applied CFO correction (Hz)" not in row for row in actual)
        assert actual[1]["Receiver frequency estimate (Hz)"] == 400


def test_waveform_quality_previews_expose_evm_nmse_and_receiver_plane() -> None:
    for key in ("pbch_trials", "pdcch_trials", "pucch_trials", "srs_trials", "trs_trials"):
        labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS[key])
        assert "EVM_rms" in labels
        assert "NMSE_dB" in labels
    for key in ("dl_trials", "ul_trials"):
        labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS[key])
        assert labels["EVM_rms"] == "EVM rms"
        assert labels["NMSE_dB"] == "NMSE dB"
        assert labels["ChannelEstimateAvailable"] == "Channel estimate available"
        assert labels["EqualizationAvailable"] == "Equalization available"


def test_srs_scoring_clock_never_becomes_receiver_timing_or_cfo() -> None:
    source = dict(Slot=5, NMSE_dB=-26.0, RawChannelNMSE_dB=-25.5,
                  PreRXClockChannelNMSE_dB=2.0,
                  ChannelNMSEReferencePlane="executed_RX_clock_before_other_RX_RF",
                  ChannelNMSEQualificationMode="common_receiver_LO_phase_equivalent_no_gain_fit",
                  ChannelNMSEReceiverTimingIncluded=1,
                  ChannelNMSERecordedReceiverTimingOffset_samples=1,
                  ChannelNMSEReceiverCFOIncluded=1,
                  ChannelNMSEExecutedReceiverCFO_Hz=400,
                  EstimatedTimingOffset_samples=1252, AppliedTimingCorrection_samples=1252,
                  CFOEstimateAvailability="unavailable")
    view = dashboard.summarize_control_trial_preview_rows("srs_trials", [source])[0]
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["srs_trials"])
    keys = ("RawChannelNMSE_dB", "PreRXClockChannelNMSE_dB", "ChannelNMSEReferencePlane",
            "ChannelNMSEQualificationMode", "ChannelNMSEReceiverTimingIncluded",
            "ChannelNMSERecordedReceiverTimingOffset_samples", "ChannelNMSEReceiverCFOIncluded",
            "ChannelNMSEExecutedReceiverCFO_Hz", "EstimatedTimingOffset_samples",
            "AppliedTimingCorrection_samples", "CFOEstimateAvailability")
    for key in keys:
        assert view[labels[key]] == source[key]
    assert "Estimated CFO (Hz)" not in view  # Recorded CFO is never an estimate.
    rendered = next(line for line in dashboard.product_frontend_script().splitlines()
                    if "id:'srs'" in line)
    for key in keys:
        assert f"'{labels[key]}'" in rendered
    no_clock = dashboard.summarize_control_trial_preview_rows(
        "srs_trials", [dict(Slot=5, NMSE_dB=-26.0)]
    )[0]
    assert all(labels[key] not in no_clock for key in keys)
    zero = dict(source, ChannelNMSERecordedReceiverTimingOffset_samples=0,
                ChannelNMSEExecutedReceiverCFO_Hz=0)
    view = dashboard.summarize_control_trial_preview_rows("srs_trials", [zero])[0]
    assert view["Scoring-only recorded RX delay (samples)"] == 0
    assert view["Scoring-only recorded RX CFO (Hz)"] == 0


def test_srs_arrival_scoring_never_replaces_receiver_or_injected_timing(tmp_path: Path) -> None:
    # Declared CSV binding fixture, not a measured waveform or performance row.
    source = dict(Slot=55, UEID=1, ObservationStartSample=3314931,
                  SRSExpectedReceiveCenterSample=3316160,
                  SRSExpectedCaptureOffset_samples=1229,
                  SRSCaptureExtractionOffset_samples=1231,
                  SRSReceiveTimingOffset_samples=2,
                  SRSAppliedTimingCorrection_samples=1231,
                  SRSReceiveTimingSource="received_reference_correlation_bounded_search",
                  SRSArrivalTimingReferenceAvailable=1,
                  SRSExpectedEarliestArrivalSample=3316147,
                  SRSExpectedEarliestArrivalCaptureOffset_samples=1216,
                  SRSExpectedEarliestArrivalRelativeToReceiveCenter_samples=-13,
                  SRSSelectedPeakMinusEarliestArrival_samples=15,
                  SRSArrivalTimingReferencePlane="earliest_path_not_strongest_peak",
                  SRSArrivalTimingScoringStatus="available_earliest_path_not_post_correction_residual",
                  TimingScoringReferenceSource="same_executed_clock_and_RF_channel_operators",
                  TimingScoringReferenceJSON=json.dumps({"ReceiverEstimatorInput": False,
                                                        "AdditionalChannelExecutions": 0}))
    path = tmp_path / "srs_trials.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(source))
        writer.writeheader()
        writer.writerow(source)
    artifact = dict(artifact_id=-1, logical_path="air_interface/csv/srs_trials.csv",
                    filesystem_path=str(path), byte_size=path.stat().st_size)
    rows = dashboard.load_small_csv_rows([artifact], artifact["logical_path"])
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["srs_trials"])
    view = dashboard.summarize_control_trial_preview_rows("srs_trials", rows)[0]
    for name, value in source.items():
        assert view[labels[name]] == value
    rendered = next(line for line in dashboard.product_frontend_script().splitlines()
                    if "id:'srs_arrival_timing'" in line)
    for name in source:
        assert f"'{labels[name]}'" in rendered
    old = dict(Slot=45, TrueTimingOffset_samples=0,
               InjectedTimingOffset_samples=1, TimingError_samples=3,
               TimingScoringReferenceSource="unavailable")
    historical = dashboard.summarize_control_trial_preview_rows("srs_trials", [old])[0]
    for name in source:
        if name.startswith("SRS"):
            assert labels[name] not in historical
    zero = dict(source, SRSExpectedEarliestArrivalRelativeToReceiveCenter_samples=0,
                SRSSelectedPeakMinusEarliestArrival_samples=0)
    measured_zero = dashboard.summarize_control_trial_preview_rows("srs_trials", [zero])[0]
    assert measured_zero[labels["SRSExpectedEarliestArrivalRelativeToReceiveCenter_samples"]] == 0
    assert measured_zero[labels["SRSSelectedPeakMinusEarliestArrival_samples"]] == 0
    # Execute the complete production channel-table renderer, not a copy of
    # its table logic or merely an assertion that labels exist in the source.
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    frontend = dashboard.product_frontend_script()
    renderer = frontend[frontend.index("  function realtimeValue("):
                        frontend.index("  function realtimeMeasuredValue(")]
    payload = {"live": {"realtime_dashboard": {"components": [{"component_id": "SRS"}]},
                        "runtime_context": {"control_trial_previews": {
                            "srs_trials": [view, measured_zero]}, "artifact_selection": {
                            "raw_control_trials": {"srs_trials": {
                                "selected_logical_path": artifact["logical_path"]}}}}}}
    script = "const state=" + json.dumps(payload) + ";\n"
    script += "const esc=x=>String(x); const unavailable=x=>x; const metricExplorerPayload=()=>({rows:[]});\n"
    script += renderer + "\nconsole.log(realtimeComponentPanel());"
    result = subprocess.run([node, "-"], input=script, capture_output=True,
                            text=True, check=True, timeout=15)
    title = "SRS receiver timing versus independent earliest-path scoring"
    # Navigation repeats titles; select the actual measurement article.
    section = result.stdout.split('id="measurement-srs_arrival_timing"', 1)[1].split("</article>", 1)[0]
    for value in ("<td>1231</td>", "<td>-13</td>", "<td>15</td>", "<td>0</td>"):
        assert value in section
    assert "not an injected delay or measured post-correction residual" in section


def test_trs_preview_separates_scheduler_tracking_and_qualification() -> None:
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["trs_trials"])
    assert labels["TrackingEligibility"] == "Scheduler usable"
    assert labels["TRSValidityState"] == "Tracking state"
    assert labels["StrictOk"] == "Qualification pass"


def test_beam_power_preview_keeps_absolute_and_normalized_units_distinct() -> None:
    labels = dict(dashboard.PROCEDURE_PREVIEW_COLUMNS["beam_state"])
    assert labels["MeasuredRSRPDBM"] == "Legacy RSRP column (unit not inferred)"
    assert labels["MeasuredRSRPDBReUnitOccupiedREEs"] == "Measured SS-RSRP (dB re unit Es)"
    assert labels["MeasuredPowerUnit"] == "Measured power unit"
    assert labels["PowerReferencePlane"] == "Power reference plane"
    source = dict(MeasuredSINRDB=25.58, MeasuredSINRQuantity="SS-SINR",
                  MeasuredSINRMethod="selected_sss_receiver_measurement",
                  MeasuredSINRReferencePlane="received_sss_resource_elements",
                  MeasurementSourceSSBIndex=1, MeasurementSourceSlot1Based=1,
                  MeasurementAvailableSlot1Based=15, MeasurementResultAvailableAtSample=860160,
                  ReceiverHestSINR_dB=27.38)
    view = dashboard.summarize_procedure_preview_rows("beam_state", [source])[0]
    for name, value in source.items():
        if name != "ReceiverHestSINR_dB":
            assert view[labels[name]] == value


def test_qcl_tci_and_srs_angle_labels_do_not_upgrade_model_metadata() -> None:
    dl = dashboard.summarize_data_trial_preview_rows(
        "dl_trials",
        [{
            "Slot": 31,
            "UEID": 1,
            "QCLStatus": "bound_received_reference_timing_prior",
            "QCLType": "A",
            "QCLSourceRS": "NZP-CSI-RS/TRS",
            "QCLSourceResourceID": 3000,
            "QCLTimingPriorUsed": 1,
            "TCIStateID": 3,
            "TCICodepoint": 1,
            "TCIStatus": "received_codepoint_bound_to_preconfigured_state",
        }],
    )[0]
    assert dl["QCL source RS"] == "NZP-CSI-RS/TRS"
    assert dl["TCI state ID"] == 3
    angles = dashboard.summarize_procedure_preview_rows(
        "channel_angles",
        [{
            "Direction": "UL",
            "TapIndex": 1,
            "AzimuthDeparture_deg": -46.6,
            "ZenithDeparture_deg": 97.2,
            "AzimuthArrival_deg": -101.0,
            "ZenithArrival_deg": 87.6,
            "AngleCoordinateFrame": "3gpp_tr38901_global_coordinate_system",
            "Source": "sixgr.channel.ChannelFactory.info.model_profile_metadata_not_in_path_realization",
        }],
    )[0]
    assert angles["AoD azimuth deg"] == -46.6
    assert "model_profile_metadata" in angles["Source"]


def artifact(path: str, mime_type: str = "text/csv", artifact_id: int = 1) -> dict:
    return {
        "artifact_id": artifact_id,
        "logical_path": path,
        "mime_type": mime_type,
        "artifact_kind": "table_csv" if path.endswith(".csv") else "image",
        "created_utc": "2026-08-02T00:00:00Z",
        "byte_size": 10,
    }


def test_failed_run_raw_observations_remain_visible_but_not_accepted() -> None:
    paths = ["air_interface/csv/pbch_trials.csv", "control/csv/msg1_prach_detection.csv",
             "air_interface/csv/prach_trials.csv", "air_interface/csv/dl_pdsch_trials.csv"]
    artifacts = [artifact(path, artifact_id=i + 1) for i, path in enumerate(paths)]
    runtime = dict(
        control_trial_previews=dict(pbch_trials=[{"CRC pass": 1}], prach_trials=[]),
        procedure_previews=dict(msg1_detection=[{"Strongest detected preamble": 0}]),
        data_trial_previews=dict(dl_trials=[]),
        artifact_selection=dict(
            raw_control_trials={"pbch_trials": {"selected_logical_path": paths[0]},
                                "prach_trials": {"selected_logical_path": paths[2]}},
            procedure_evidence={"msg1_detection": {"selected_logical_path": paths[1]}},
            raw_link_trials={"dl": {"selected_logical_path": paths[3]}}))
    primary, authority = dashboard.select_primary_result_artifacts(artifacts)
    assert not primary and authority["status"] == "no_atomic_result_authority"
    observations = dashboard.runtime_preview_artifacts(artifacts, runtime)
    assert {row["logical_path"] for row in observations} == set(paths[:2])
    assert all(row["evidence_scope"] == "raw_runtime_observation_not_qualified"
               for row in observations)
    components = {row["component_id"]: row for row in
                  dashboard.build_realtime_component_dashboard(primary, "failed", [], observations)}
    for key in ("ssb_pbch", "prach_rach"):
        assert components[key]["status"] == "runtime_observations_unqualified"
        assert components[key]["canonical_artifact_count"] == 0
        assert components[key]["runtime_observation_artifact_count"] == 1
    assert components["pdsch"]["status"] == "not_published"
    # Raw cards must not change qualification/gallery authority or mutate input.
    assert not dashboard.select_primary_result_artifacts(artifacts)[0]
    assert all("evidence_scope" not in row for row in artifacts)


def test_runtime_preview_requires_exact_selected_producer_and_no_duplicate() -> None:
    source = artifact("air_interface/csv/pbch_trials.csv")
    runtime = dict(control_trial_previews=dict(pbch_trials=[{"Slot": 1}]),
                   artifact_selection=dict(raw_control_trials=dict(pbch_trials={
                       "selected_logical_path": "another_run/pbch_trials.csv"})))
    assert dashboard.runtime_preview_artifacts([source], runtime) == []
    runtime["artifact_selection"]["raw_control_trials"]["pbch_trials"]["selected_logical_path"] = source["logical_path"]
    observations = dashboard.runtime_preview_artifacts([source], runtime)
    rows = dashboard.build_realtime_component_dashboard([source], "failed", [], observations)
    ssb = next(row for row in rows if row["component_id"] == "ssb_pbch")
    assert ssb["artifact_count"] == 1 and ssb["runtime_observation_artifact_count"] == 0


def test_ssb_sweep_preview_preserves_all_four_received_candidates() -> None:
    raw = [dict(UEIndex=1, CellID=1, Slot=1, ObservationDeliverySlot=15,
                SSBIndex=i, SelectedBeamFlag=int(i == 1), SelectedSSBIndex=1,
                SSBCandidateCarrierSlot0Based=i // 2, SSBCandidateSymbolWithinSlot0Based=4,
                SSBBurstConfiguredBeamCount=4, SSBBurstExecutedBeamCount=4,
                SSBBurstSweepObservedCandidateCount=4, SSBBurstSweepCoverageComplete=True,
                SS_RSRP_dB_re_UnitOccupiedRE_Es=-15.0-i, SS_SINR_dB=25.0-i,
                CRCPass=True, SelectionSource="PBCH_receiver", Status="PASS")
           for i in (0, 2, 3, 1)]
    rows = dashboard.summarize_procedure_preview_rows("ssb_sweep", raw)
    assert {row["SSB index (0-based)"] for row in rows} == {0, 1, 2, 3}
    assert sum(row["Selected"] for row in rows) == 1
    assert rows[-1]["Selected SSB index"] == 1
    assert rows[-1]["Source slot (1-based)"] == 1
    assert rows[-1]["Delivery slot (1-based)"] == 15
    assert rows[-1]["SS-RSRP (dB re unit Es)"] == -16
    assert dashboard.summarize_procedure_preview_rows("ssb_sweep", []) == []


def test_ssb_sweep_absolute_power_and_coordinates_reach_rendered_columns() -> None:
    import re

    powers = [-97.3532702609121, -97.6448024184975, -107.023014713919, -109.628958765184]
    raw = [dict(SSBIndex=i, SS_RSRP_dBm=power,
                SS_RSRP_dB_re_UnitOccupiedRE_Es="NaN",
                SelectedBeamFlag=int(i == 0), SelectedSSBIndex=0,
                SelectionMetric="SS_RSRP_dBm",
                PowerReferencePlane="internal_physical_receive_element_before_RX_front_end",
                SSMeasurementSource="received_sss_power",
                SSPhysicalMeasurementStatus="available_rsrp_and_sinr",
                SSBCandidateCarrierSlot0Based=i // 2,
                SSBCandidateSymbolWithinSlot0Based=4 + 4 * (i % 2),
                SSBCandidateNativeSlot0Based=i // 2,
                SSBCandidateNativeSymbolWithinSlot0Based=4 + 4 * (i % 2),
                SSBCandidateNativeSCS_kHz=30)
           for i, power in enumerate(powers)]
    rows = dashboard.summarize_procedure_preview_rows("ssb_sweep", raw)
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    panel = source.split("{id:'ssb_sweep', title:", 1)[1].split("rows:recent", 1)[0]
    columns = re.findall(r"'([^']+)'", panel.split("columns:[", 1)[1])
    for row, power in zip(rows, powers):
        assert row["SS-RSRP (dBm)"] == power
        assert "SS-RSRP (dB re unit Es)" not in row
        assert row["Selection metric"] == "SS_RSRP_dBm"
        # Test the actual browser column keys, not only the Python projection.
        assert set(row).issubset(columns)
    assert rows[0]["Containing common-carrier slot (0-based)"] == 0
    assert rows[0]["Containing common-carrier symbol (0-based)"] == 4
    assert "Candidate carrier slot (0-based)" not in columns
    assert "Candidate symbol (0-based)" not in columns


def test_ssb_sweep_never_converts_normalized_or_missing_power_to_dbm() -> None:
    rows = dashboard.summarize_procedure_preview_rows("ssb_sweep", [
        dict(SSBIndex=0, SS_RSRP_dBm="NaN", SS_RSRP_dB_re_UnitOccupiedRE_Es=-15.0,
             SelectionMetric="SS_RSRP_dB_re_UnitOccupiedRE_Es"),
        dict(SSBIndex=1, SelectionMetric="SS_RSRP_dBm"),
    ])
    assert all("SS-RSRP (dBm)" not in row for row in rows)
    assert rows[0]["SS-RSRP (dB re unit Es)"] == -15.0
    assert rows[1]["SS-RSRP (dB re unit Es)"] == "N/A"


def test_initial_access_renderer_includes_msg1_before_completed_ra() -> None:
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    block = source.split("    const initialAccessRows = [", 1)[1].split("    const csiRows", 1)[0]
    control = dict(pbch_trials=[dict(Slot=1, Cell=1, Status="PASS", **{"CRC pass": 1})],
                   prach_trials=[])
    procedure = dict(msg1_detection=[{"UE": 1, "Absolute slot (0-based)": 29,
                                      "Strongest detected preamble": 0, "Status": "PASS"}])
    script = ("const recent = v => (v || []).slice(-8).reverse();\nconst controlPreviews=" +
              json.dumps(control) + ";\nconst procedurePreviews=" + json.dumps(procedure) +
              ";\nconst initialAccessRows = [" + block + "\nconsole.log(JSON.stringify(initialAccessRows));")
    result = subprocess.run([node, "-e", script], capture_output=True, text=True,
                            encoding="utf-8", check=True, timeout=15)
    rows = json.loads(result.stdout)
    assert len(rows) == 2
    assert rows[1]["Procedure"] == "PRACH Msg1 observation (not completed RA)"
    assert rows[1]["Slot"] == 29 and rows[1]["Outcome"] == 0
    assert rows[1]["Slot convention"] == "absolute, 0-based"
    assert dashboard.PRODUCT_PAGE_ROUTES["/live"] == "realtime"
    assert "'Proposed RAR TA command':row['RAR TA command']" in source
    assert "'Applied TA command':row['RAR TA command']" not in source


def test_component_dashboard_separates_raster_from_legacy_svg() -> None:
    rows = dashboard.build_realtime_component_dashboard(
        [
            artifact("air_interface/csv/prach_trials.csv", artifact_id=1),
            artifact("reports/image/prach_correlation.png", "image/png", 2),
            artifact("reports/image/prach_legacy.svg", "image/svg+xml", 3),
            artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=4),
            artifact("prach/csv/prach_trials.csv", artifact_id=5),
            artifact("reports/csv/mac_harq_trials.csv", artifact_id=6),
            artifact("reports/image/channel_geometry.png", "image/png", 7),
        ],
        "completed",
    )
    by_id = {row["component_id"]: row for row in rows}
    assert len(rows) == 24
    assert len(by_id) == len(rows)
    assert by_id["prach_rach"]["status"] == "evidence_available"
    assert by_id["prach_rach"]["csv_count"] == 1
    assert by_id["prach_rach"]["image_count"] == 1
    assert by_id["prach_rach"]["legacy_svg_count"] == 1
    assert by_id["prach_rach"]["planned_folder"] == "prach"
    assert "pass" not in by_id["prach_rach"]["status"]
    assert by_id["l3"]["status"] == "not_published"
    assert by_id["mac_harq_scheduler"]["csv_count"] == 1
    assert by_id["channel"]["image_count"] == 1
    assert dashboard.is_component_view_artifact_path("prach/csv/prach_trials.csv")
    assert not dashboard.is_component_view_artifact_path(
        "control/csv/prach_trials.csv"
    )


def test_canonical_component_dashboard_uses_exact_folder_ownership() -> None:
    rows = dashboard.build_realtime_component_dashboard(
        [
            artifact(
                "components/initial_access/qualification/csv/type0_coreset_resolution.csv",
                artifact_id=1,
            ),
            artifact(
                "components/pdcch/qualification/csv/pdcch_detection_trials.csv",
                artifact_id=2,
            ),
            artifact(
                "components/frame_grid/qualification/png/channel_grid.png",
                "image/png",
                3,
            ),
            artifact(
                "artifact_generation/component_qualification_manifest.csv",
                artifact_id=4,
            ),
        ],
        "completed_with_failures",
    )
    by_id = {row["component_id"]: row for row in rows}
    assert by_id["pdcch"]["artifact_count"] == 1
    assert by_id["pdcch"]["latest_artifacts"][0]["logical_path"].startswith(
        "components/pdcch/"
    )
    assert by_id["channel"]["artifact_count"] == 0
    assert by_id["channel"]["status"] == "not_published"
    assert by_id["mimo"]["artifact_count"] == 0
    assert by_id["frame_grid"]["artifact_count"] == 1


def test_ue_status_merges_control_and_performance_without_upgrading_fidelity() -> None:
    metric_explorer = {
        "ue_summaries": {
            "1": {
                "ueid": 1,
                "dl_bler": 0.0,
                "ul_bler": 0.25,
                "dl_mean_measured_sinr_dB": 12.5,
                "ul_mean_measured_sinr_dB": 7.0,
                "source_table": "reports/csv/live_user_performance_snapshot.csv",
                "fidelity_level": "abstraction_level",
            }
        }
    }
    runtime = {
        "control_state_preview": [
            {
                "UEIndex": 1,
                "ServingCell": 3,
                "SchedulingEligibility": 1,
                "AccessState": "connected",
                "LastPDCCHStatus": "control_ok",
                "SRSValidityState": "valid",
                "CSIValidityState": "fresh_srs",
                "TRSValidityState": "valid",
            }
        ]
    }
    rows = dashboard.build_realtime_ue_status(metric_explorer, runtime)
    assert len(rows) == 1
    assert rows[0]["ue_id"] == "1"
    assert rows[0]["health"] == "attention"
    assert rows[0]["scheduling_eligible"] is True
    assert rows[0]["performance_fidelity"] == "abstraction_level"
    assert rows[0]["control_source"] == "reports/csv/live_control_gating_state.csv"


def test_ue_status_retains_distinct_dl_ul_admission() -> None:
    # Slot41-style state: global SRS admission is off, but codebook UL
    # requires causal SRS. The current DL direction must not hide UL=false.
    control = {
        "UEIndex": "1", "RNTI": "4660", "AccessState": "succeeded",
        "CurrentSchedulingDirection": "DL", "SchedulingEligibility": "1",
        "SharedSchedulingEligibility": "1", "DLSchedulingEligibility": "1",
        "ULSchedulingEligibility": "0", "SRSValidityState": "not_required",
        "DLSchedulingBlockReason": "", "ULSchedulingBlockReason": "srs_no_measurements",
        "DLSRSRequired": "0", "ULSRSRequired": "1", "ULSRSCausalUsable": "0",
        "ULSRSCausalStatus": "no_measurements",
    }
    for direction, current in (("DL", "1"), ("UL", "0")):
        control.update(CurrentSchedulingDirection=direction,
                       SchedulingEligibility=current)
        ue = dashboard.build_realtime_ue_status(
            {}, {"control_state_preview": [control]})[0]
        assert ue["dl_scheduling_eligible"] is True
        assert ue["ul_scheduling_eligible"] is False
        assert ue["scheduling_eligible"] is (direction == "DL")
        assert ue["ul_srs_required"] is True and ue["dl_srs_required"] is False
        assert ue["ul_srs_causal_usable"] is False
        assert ue["ul_scheduling_block_reason"] == "srs_no_measurements"
        assert ue["ul_srs_causal_status"] == "no_measurements"


def test_scheduler_admission_orders_control_knowledge_not_future_target() -> None:
    older = dict(UEIndex=1, Direction="UL", SweepPointIndex=1,
                 ControlSlot=41, SchedulingKnowledgeSlot=41, ScheduledDataSlot=50,
                 QueueBytes=0, CandidateGrantCount=0)
    newer = dict(older, ControlSlot=42, SchedulingKnowledgeSlot=42,
                 ScheduledDataSlot=45, QueueBytes=100)
    dl = dict(older, Direction="DL", QueueBytes=200)
    for inputs in ([older, newer, dl], [newer, dl, older]):
        selected = dashboard.latest_realtime_scheduler_admission(inputs)
        assert selected["1"]["UL"] == newer
        assert selected["1"]["DL"] == dl
    next_point = dict(older, SweepPointIndex=2, ControlSlot=1, SchedulingKnowledgeSlot=1)
    assert dashboard.latest_realtime_scheduler_admission([newer, next_point])["1"]["UL"] == next_point


def test_scheduler_admission_does_not_manufacture_missing_directions() -> None:
    row = dict(UEIndex=2, Direction="UL", QueueBytes=0,
               AdmissionReason="no_queued_bytes_or_pending_retransmission")
    ue = dashboard.build_realtime_ue_status({}, {}, {"scheduler_admission": [row]})[0]
    assert ue["ue_id"] == "2" and ue["scheduler_admission"] == {"UL": row}
    assert ue["dl_scheduling_eligible"] is None and ue["ul_scheduling_eligible"] is None
    assert dashboard.latest_realtime_scheduler_admission([None, {}, dict(row, Direction="BAD")]) == {}


def test_scheduler_admission_csv_is_loaded_from_canonical_producer(tmp_path: Path) -> None:
    path = tmp_path / "scheduler_admission_trace.csv"
    values = dict(UEIndex=1, Direction="UL", QueueBytes=0, SchedulerBufferBytes=1,
                  HasPendingRetransmission=1, CandidateRank=4, ControlSlot=41,
                  ScheduledDataSlot=45, SRSRequired=1, SRSCausalUsable=0,
                  HARQNewDataProcessAvailable=0, CandidateGrantCount=0,
                  AdmissionReason="srs_no_measurements", SchedulerDecisionReasons="")
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(values))
        writer.writeheader(); writer.writerow(values)
    artifact = dict(artifact_id=-1, logical_path="packet_flow/csv/scheduler_admission_trace.csv",
                    filesystem_path=str(path), byte_size=path.stat().st_size)
    sources = dashboard.load_realtime_ue_measurement_sources([artifact])
    ue = dashboard.build_realtime_ue_status({}, {}, sources)[0]
    row = ue["scheduler_admission"]["UL"]
    for key in ("QueueBytes", "CandidateRank", "HARQNewDataProcessAvailable", "CandidateGrantCount"):
        assert float(row[key]) == values[key]
    assert row["AdmissionReason"] == "srs_no_measurements"
    assert "SchedulerDecisionReasons" in row


def test_scheduler_admission_card_renders_actual_zero_and_scopes() -> None:
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    renderer = source[source.index("  function realtimeSchedulerAdmission("):
                      source.index("  function realtimeUEStatusPanel(")]
    record = dict(Direction="UL", QueueBytes=0, HasPendingRetransmission=1,
                  HARQNewDataProcessAvailable=0, CandidateGrantCount=0,
                  CandidateRank=4, ControlSlot=41, ScheduledDataSlot=45,
                  ConfiguredSNR_dB="NaN",
                  SlotNumbering="one_based_absolute_carrier_slot",
                  AdmissionReason="srs_no_measurements", SchedulerDecisionReasons="")
    ue = dict(scheduler_admission=dict(UL=record))
    script = "const esc=x=>String(x).replaceAll('<','&lt;');\n" + renderer
    script += "\nconsole.log(realtimeSchedulerAdmission(" + json.dumps(ue) + "));"
    result = subprocess.run([node, "-e", script], capture_output=True, text=True,
                            encoding="utf-8", check=True, timeout=15)
    html = result.stdout
    assert "UL last observed scheduling decision" in html
    assert "DL last observed" not in html
    assert "Queued bytes</th><td>0</td>" in html
    assert "Candidate rank</th><td>4</td>" in html
    assert "Candidate grant count</th><td>0</td>" in html
    assert "Control slot</th><td>41</td>" in html and "Target data slot</th><td>45</td>" in html
    assert "Configured SNR (dB)</th><td>—</td>" in html
    assert "srs_no_measurements" in html and "one_based_absolute_carrier_slot" in html
    assert "Historical decision-time inputs" in html and "not current queue state" in html
    assert "not required to retransmit" in html


def test_ul_timing_loader_retains_engine_failure_and_preflight_distinction(tmp_path: Path) -> None:
    tables = {
        "ul_scheduler_timing": [
            dict(DecisionSequence=1, ControlSlot=41, TimingEngineValid=1,
                 TimingSelectedDataSlot=45, TimingSelectedK2=4, EligibleForUEScheduling=0,
                 BlockReason="target_already_has_queued_UL_grant"),
            dict(DecisionSequence=2, ControlSlot=42, TimingEngineValid=0,
                 TimingSelectedDataSlot="NaN", TimingSelectedK2="NaN", EligibleForUEScheduling=0,
                 BlockReason="timing_rejected:data_timing_rejected:target_hits_fixed_opposite_direction"),
        ],
        "ul_scheduler_timing_candidates": [
            dict(DecisionSequence=1, CandidateOrdinal=1, K2=4, TargetAbsoluteSlot0Based=44,
                 TimingValid=1, SelectedByTimingEngine=1, ReasonCode="timing_relation_valid"),
            dict(DecisionSequence=2, CandidateOrdinal=1, K2=4, TargetAbsoluteSlot0Based=45,
                 TimingValid=0, SelectedByTimingEngine=0, ReasonCode="target_hits_fixed_opposite_direction"),
        ],
    }
    artifacts = []
    for name, values in tables.items():
        path = tmp_path / f"{name}.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(values[0]))
            writer.writeheader(); writer.writerows(values)
        artifacts.append(dict(artifact_id=-len(artifacts)-1,
                              logical_path=f"packet_flow/csv/{name}.csv",
                              filesystem_path=str(path), byte_size=path.stat().st_size))
    actual = dashboard.load_realtime_ul_planning_sources(artifacts)
    assert len(actual["ul_scheduler_timing"]) == 2
    assert len(actual["ul_scheduler_timing_candidates"]) == 2
    assert actual["ul_scheduler_timing"][0]["BlockReason"] == "target_already_has_queued_UL_grant"
    assert float(actual["ul_scheduler_timing"][0]["TimingEngineValid"]) == 1
    assert float(actual["ul_scheduler_timing"][0]["EligibleForUEScheduling"]) == 0
    assert actual["ul_scheduler_timing_candidates"][1]["ReasonCode"] == "target_hits_fixed_opposite_direction"
    assert dashboard.load_realtime_ul_planning_sources([]) == {
        "ul_scheduler_timing": [], "ul_scheduler_timing_candidates": []}


def test_ul_timing_panel_keeps_rejected_candidates_and_historical_scope() -> None:
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    renderer = source[source.index("  function realtimeULPlanningPanel("):
                      source.index("  function realtimeUEStatusPanel(")]
    events = [dict(DecisionSequence=k, ControlSlot=k+40,
                   TimingSelectedDataSlot="NaN", TimingSelectedK2="NaN",
                   TimingEngineValid=0, EligibleForUEScheduling=0,
                   EvaluatedCandidateCount=1, BlockReason=f"timing_rejected:case{k}")
              for k in range(1, 21)]
    candidates = [dict(DecisionSequence=k, CandidateOrdinal=1, K2=4,
                       TargetAbsoluteSlot0Based=k+43, TargetStartSymbol0Based=0,
                       TargetNumSymbols=11, TimingValid=0, SelectedByTimingEngine=0,
                       ReasonCode="target_hits_fixed_opposite_direction")
                  for k in range(1, 21)]
    data = dict(ul_scheduler_timing=events, ul_scheduler_timing_candidates=candidates)
    script = "const esc=x=>String(x).replaceAll('<','&lt;');\n" + renderer
    script += "\nlet state=" + json.dumps(dict(live=dict(realtime_dashboard=data))) + ";"
    script += "\nconsole.log(realtimeULPlanningPanel()); state={}; console.log(JSON.stringify(realtimeULPlanningPanel()));"
    result = subprocess.run([node, "-e", script], capture_output=True, text=True,
                            encoding="utf-8", check=True, timeout=15)
    html = result.stdout
    assert "UL timing / resource preflight" in html
    assert "Evaluated K2 candidates (12)" in html
    assert "timing_rejected:case20</td>" in html and "timing_rejected:case9</td>" in html
    assert "timing_rejected:case8</td>" not in html
    assert "target_hits_fixed_opposite_direction" in html
    assert "Target slot (0-based)" in html and "Control slot (1-based)" in html
    assert "not a decoded DCI or transmitted PUSCH" in html
    assert "stops at the first valid candidate" in html and "last 12 decisions" in html
    assert html.endswith('""\n')


def test_ue_status_does_not_infer_directional_admission_from_shared_flag() -> None:
    # Legacy or incomplete rows cannot establish either directional result.
    control = {"UEIndex": 1, "SharedSchedulingEligibility": 1}
    ue = dashboard.build_realtime_ue_status(
        {}, {"control_state_preview": [control]})[0]
    assert ue["dl_scheduling_eligible"] is None
    assert ue["ul_scheduling_eligible"] is None


def test_ue_status_directional_admission_numeric_and_unknown_flags() -> None:
    for raw, expected in ((1.0, True), (0.0, False), ("1.0", True),
                          ("0.0", False), ("NaN", None), (float("nan"), None),
                          (2, None), ("unavailable", None)):
        row = {"UEIndex": 1, "ULSchedulingEligibility": raw, "ULSRSRequired": raw}
        ue = dashboard.build_realtime_ue_status({}, {"control_state_preview": [row]})[0]
        assert ue["ul_scheduling_eligible"] is expected
        assert ue["ul_srs_required"] is expected


def test_ue_card_renders_separate_directional_admission() -> None:
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    assert 'DL eligible' in source and 'UL eligible' in source
    assert '${admissionDetails}' in source
    assert 'not proof of a grant' in source


def test_ue_status_keeps_serving_ss_and_csi_measurements_distinct() -> None:
    sources = {
        # Explicit receiver-provenance fixture; a dBm suffix alone cannot
        # establish a received measurement (tested independently below).
        "serving": [{"UEID": 1, "Slot": 8, "ServingRSRP_dBm": -82.5,
                     "ServingRSRPSource": "nrChannelEstimate_port3000_reference_RE_power_per_receive_branch",
                     "ServingRSRPReferencePlane": "physical_receive_reference_RE"}],
        "csi": [
            {
                "UEIndex": 1,
                "Slot": 8,
                "MeasurementRSRP_dBm": -86.25,
                "MeasurementRelativeRSRP_dB": 23.0,
                "MeasurementRSRPPerReceiveAntenna_dBm": "[-85.5,-87.2]",
                "SINR_dB": 11.75,
                "SINRMeasurementDomain": "csi_rs_resource_selective_channel_estimate",
                "PhysicalMeasurementStatus": "available",
                "MeasurementSource": "nrCSIRSMeasurements_runtime_received_grid",
                "MeasurementPowerUnit": "dB_re_unit_occupied_RE_Es",
                "PowerReferencePlane": "normalized_fixed_snr_occupied_re",
            }
        ],
        "ssb": [
            {
                "UEID": 1,
                "Slot": 2,
                "SS_RSRP_dBm": -91.0,
                "SS_SINR_dB": 7.5,
                "ConfiguredSNR_dB": 3.0,
                "MeasuredReferenceSignalChannelGain_dB": 4.25,
                "SSSINRMeasurementMethod": "ts38215_received_reference_disturbance",
                "SSBReceivedPower_dB": -3.0,
                "MeasuredTrialSINR_dB": 9.25,
            }
        ],
        "ul": [{"UEID": 1, "Slot": 9, "PUSCHPowerHeadroom_dB": 13.5}],
        "dl": [{"UEID": 1, "Slot": 8, "CSI_RSRP_dB": 99.0}],
        "cell_paths": [
            {
                "UEID": 1,
                "Slot": 8,
                "CandidateRank": 1,
                "CellID": 3,
                "Pathloss_dB": 104.0,
                "RSRP_dBm": -82.5,
                "BeamIndex": 2,
                "PathlossModelSource": "nrPathLoss",
                "PathlossComplianceStatus": "available",
            },
            {
                "UEID": 1,
                "Slot": 8,
                "CandidateRank": 2,
                "CellID": 4,
                "Pathloss_dB": 0,
                "RSRP_dBm": -110.0,
                "PathlossModelSource": "pathloss_disabled",
                "PathlossComplianceStatus": "unsupported_pathloss_configuration",
            },
        ],
    }
    rows = dashboard.build_realtime_ue_status({}, {}, sources)
    assert len(rows) == 1
    ue = rows[0]
    assert ue["serving_rsrp_dbm"] == -82.5
    assert ue["ss_rsrp_dbm"] == -91.0
    assert ue["ss_sinr_db"] == 7.5
    assert ue["configured_snr_db"] == 3.0
    assert ue["ss_sinr_delta_db"] == 4.5
    assert ue["ss_channel_gain_db"] == 4.25
    assert ue["ss_sinr_method"] == "ts38215_received_reference_disturbance"
    assert ue["pbch_dmrs_sinr_db"] == 9.25
    assert ue["csi_rsrp_dbm"] == -86.25
    assert ue["csi_rsrp_relative_db"] == 23.0
    assert ue["csi_power_unit"] == "dB_re_unit_occupied_RE_Es"
    assert ue["csi_power_reference_plane"] == "normalized_fixed_snr_occupied_re"
    assert ue["csi_sinr_db"] == 11.75
    assert ue["ue_phr_db"] == 13.5
    assert ue["pathloss_paths"][0]["pathloss_db"] == 104.0
    assert ue["pathloss_paths"][1]["pathloss_db"] is None
    assert ue["pathloss_paths"][1]["raw_pathloss_db"] == 0
    assert ue["pathloss_paths"][1]["beam_index"] is None
    assert ue["pathloss_paths"][1]["beam_gain_db"] is None
    del sources["serving"][0]["ServingRSRPSource"]
    unknown = dashboard.build_realtime_ue_status({}, {}, sources)[0]
    assert unknown["serving_rsrp_dbm"] is None
    assert unknown["serving_rsrp_published_dbm"] == -82.5


def test_csi_normalized_physical_power_is_not_legacy_grid_power() -> None:
    sources = {"csi": [{"UEIndex": 1, "Slot": 6,
        "MeasurementRelativeRSRP_dB": -18.69,
        "MeasurementRSRP_dB_re_UnitOccupiedRE_Es": -10.61,
        "MeasurementRSSI_dB_re_UnitOccupiedRE_Es": 18.225,
        "MeasurementRSRQ_dB": -4.474,
        "MeasurementReceiveAntennaIndex1Based": 2,
        "MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es": "[-11.29,-10.61]"}]}
    ue = dashboard.build_realtime_ue_status({}, {}, sources)[0]
    assert ue["csi_rsrp_normalized_db"] == -10.61
    assert ue["csi_rsrp_relative_db"] == -18.69
    assert ue["csi_rsrp_dbm"] is None
    assert ue["csi_rsrq_db"] == -4.474
    assert ue["csi_rsrp_receive_branch"] == 2
    assert ue["csi_power_unit"] == "dB_re_unit_occupied_RE_Es"
    del sources["csi"][0]["MeasurementRSRP_dB_re_UnitOccupiedRE_Es"]
    assert dashboard.build_realtime_ue_status({}, {}, sources)[0]["csi_rsrp_normalized_db"] is None
    assert dashboard.build_realtime_ue_status({}, {}, sources)[0]["csi_power_unit"] == ""


def test_csi_independent_channel_nmse_never_uses_pilot_residual() -> None:
    row = dict(UEIndex=1, Slot=6, NMSE_dB=-31, PilotResidualNMSE_dB=-7,
               NMSEScoringAvailable=1, ChannelNMSEComparedComplexValues=48,
               ChannelNMSEMeasuredResourceCount=2, ChannelNMSEReferencePlane="nominal_linear",
               ChannelNMSEScope="all_pilot_ports", ChannelEstimateResourcesCSV="channel_estimation/csv/csirs_test.csv")
    ue = dashboard.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    assert ue["csi_channel_nmse_db"] == -31
    assert ue["csi_pilot_residual_nmse_db"] == -7
    assert ue["csi_channel_nmse_count"] == 48
    assert ue["csi_channel_nmse_reference_plane"] == "nominal_linear"
    assert ue["csi_channel_nmse_csv"] == row["ChannelEstimateResourcesCSV"]
    row["NMSEScoringAvailable"] = 0
    assert dashboard.build_realtime_ue_status({}, {}, {"csi": [row]})[0]["csi_channel_nmse_db"] is None
    del row["NMSE_dB"]
    assert dashboard.build_realtime_ue_status({}, {}, {"csi": [row]})[0]["csi_pilot_residual_nmse_db"] == -7


def test_csi_synchronization_keeps_actual_receive_planes_separate() -> None:
    row = dict(UEIndex=1, Slot=6)
    for prefix, cfo, delay in (("Receiver", 1100, 20), ("PhysicalMeasurement", 700, 13)):
        row.update({prefix + "SynchronizationSource": prefix + "_received_samples",
                    prefix + "TimingOffset_samples": delay,
                    prefix + "TimingCorrection_samples": delay,
                    prefix + "DemodulatedSampleCount": 61440,
                    prefix + "EstimatedCFO_Hz": cfo,
                    prefix + "AppliedCFO_Hz": cfo,
                    prefix + "CFOStatus": "OK",
                    prefix + "CFOSource": "cyclic_prefix_cfo_estimator",
                    prefix + "SynchronizationSampleDomain": "relative_to_observation_capture_start_zero_based"})
    ue = dashboard.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    planes = ue["csi_synchronization"]
    assert [p["estimated_cfo_hz"] for p in planes] == [1100, 700]
    assert [p["timing_applied_samples"] for p in planes] == [20, 13]
    assert planes[0]["plane"] == "post-front-end practical CSI"
    assert planes[1]["plane"] == "pre-front-end antenna measurement"
    # Execute the production browser projection; do not only inspect strings.
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    projection = next(line.strip() for line in source.splitlines()
                      if line.strip().startswith("const csiSyncRows ="))
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    js = "const recent=x=>x; const dashboard=" + json.dumps({"ue_status": [ue]}) + ";"
    result = subprocess.run([node, "-e", js + projection + "console.log(JSON.stringify(csiSyncRows));"],
                            capture_output=True, text=True, check=True, timeout=15)
    displayed = json.loads(result.stdout)
    assert [p["Estimated CFO (Hz)"] for p in displayed] == [1100, 700]
    assert [p["Timing applied (samples)"] for p in displayed] == [20, 13]
    assert all(p["Slot"] == 6 and str(p["UE"]) == "1" for p in displayed)
    del row["PhysicalMeasurementSynchronizationSource"]
    remaining = dashboard.build_realtime_ue_status({}, {}, {"csi": [row]})[0]["csi_synchronization"]
    assert len(remaining) == 1 and remaining[0]["plane"] == planes[0]["plane"]
    assert dashboard.build_realtime_ue_status({}, {}, {"csi": [dict(UEIndex=1)]})[0]["csi_synchronization"] == []


def test_ue_card_normalized_power_and_missing_ul_are_source_bound() -> None:
    sources = {
        "ssb": [dict(UEIndex=1, Slot=1, SSBIndex=1, SelectedSSBIndex=1,
                     SelectedBeamFlag=1, SS_RSRP_dBm="",
                     SS_RSRP_dB_re_UnitOccupiedRE_Es=-15.0007707867825,
                     SSBReceivedPower_dB=-17.8374355122784,
                     PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es")],
        "csi": [dict(UEIndex=1, Slot=46,
                     MeasurementRSRP_dB_re_UnitOccupiedRE_Es=-10.2622251253811,
                     MeasurementRelativeRSRP_dB=-18.235357987713)],
        "ul": [],
        "cell_paths": [dict(UEID=1, Slot=50, CellID=1, CandidateRank=1,
                            Pathloss_dB=0, RxPower_dBm=31.4889,
                            PathlossModelSource="pathloss_disabled_fixed_snr_identity",
                            PathlossComplianceStatus="unavailable")],
    }
    ue = dashboard.build_realtime_ue_status({}, {}, sources)[0]
    assert ue["ss_rsrp_normalized_db"] == -15.0007707867825
    assert ue["ss_rsrp_relative_db"] == -17.8374355122784
    assert ue["csi_rsrp_normalized_db"] == -10.2622251253811
    assert ue["ss_rsrp_dbm"] is None and ue["csi_rsrp_dbm"] is None
    assert ue["serving_rsrp_dbm"] is None  # Do not substitute another RS.
    assert ue["serving_rsrp_missing_reason"] == "No absolute power plane"
    assert ue["ul_missing_reason"] == "No PUSCH trials"
    assert ue["phr_missing_reason"] == "No PUSCH measurement"
    assert ue["pathloss_status"] == "disabled_fixed_snr"
    assert ue["pathloss_paths"][0]["pathloss_db"] is None
    assert ue["pathloss_paths"][0]["rx_power_dbm"] is None
    del sources["ssb"][0]["SS_RSRP_dB_re_UnitOccupiedRE_Es"]
    assert dashboard.build_realtime_ue_status({}, {}, sources)[0]["ss_rsrp_normalized_db"] is None


def test_ue_ssb_summary_uses_selected_candidate_not_csv_order_or_power() -> None:
    selected = dict(UEIndex=1, Slot=1, SSBIndex=1, SelectedSSBIndex=1,
                    SelectedBeamFlag=1, SS_RSRP_dB_re_UnitOccupiedRE_Es=-15)
    other = dict(selected, SSBIndex=0, SelectedBeamFlag=0,
                 SS_RSRP_dB_re_UnitOccupiedRE_Es=20)
    for candidates in ([selected, other], [other, selected]):
        ue = dashboard.build_realtime_ue_status({}, {}, {"ssb": candidates})[0]
        assert ue["ss_selected_index"] == 1 and ue["ss_rsrp_normalized_db"] == -15
    # An incomplete newer occasion cannot inherit an older selected power.
    assert dashboard.latest_realtime_selected_ssb_by_ue(
        [selected, dict(other, Slot=21)]) == {}
    assert dashboard.latest_realtime_selected_ssb_by_ue([other]) == {}


def test_ue_card_renders_relative_power_without_faking_dbm_or_ul() -> None:
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    formatter = source[source.index("  function realtimeValue("):
                       source.index("  function realtimeComponentPanel(")]
    renderer = source[source.index("  function realtimeMeasuredValue("):
                      source.index("  function realtimeLogPanel(")]
    ue = dashboard.build_realtime_ue_status({}, {}, {
        "ssb": [dict(UEIndex=1, Slot=1, SS_RSRP_dB_re_UnitOccupiedRE_Es=-15.00077,
                     PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es")],
        "csi": [dict(UEIndex=1, Slot=46,
                     MeasurementRSRP_dB_re_UnitOccupiedRE_Es=-10.26223)]})[0]
    script = "const esc = x => String(x); const unavailable = x => x;\n"
    script += "const state = " + json.dumps({"live": {"realtime_dashboard": {"ue_status": [ue]}}}) + ";\n"
    script += formatter + renderer + "\nconsole.log(realtimeUEStatusPanel());"
    script += "\nconsole.log(realtimePowerValue(-91, -15));"
    script += "\nconsole.log(realtimeMeasuredValue(0, '', 3, 'missing'));"
    result = subprocess.run([node, "-e", script], capture_output=True,
                            text=True, check=True, timeout=15)
    html = result.stdout
    assert "SS-RSRP <strong>-15.00 dB re unit Es</strong>" in html
    assert "CSI-RSRP <strong>-10.26 dB re unit Es</strong>" in html
    assert "UL SINR <strong>No PUSCH trials</strong>" in html
    assert "UL BLER <strong>No PUSCH trials</strong>" in html
    assert "UL rate <strong>No PUSCH trials</strong>" in html
    assert "No absolute power plane" in html and "No PUSCH measurement" in html
    assert "Cell-link loss evidence" in html and "<th>Candidate order</th>" in html
    assert "-15.00 dBm" not in html and "-10.26 dBm" not in html
    assert "-91.00 dBm" in html and "0.000" in html


def test_post_equalization_csi_row_is_not_relabelled_as_csi_sinr() -> None:
    sources = {
        "csi": [
            {
                "UEIndex": 1,
                "Slot": 1,
                "SINR_dB": 18.0,
                "SINRMeasurementDomain": "pdsch_post_equalization_data_re",
            }
        ]
    }
    ue = dashboard.build_realtime_ue_status({}, {}, sources)[0]
    assert ue["csi_sinr_db"] is None


def test_runtime_log_component_annotation_preserves_original_message() -> None:
    source = [{"level_str": "INFO", "message_text": "PDCCH DCI decoded for UE 2"}]
    rows = dashboard.annotate_realtime_logs(source)
    assert rows[0]["component"] == "pdcch"
    assert rows[0]["message_text"] == source[0]["message_text"]
    assert "component" not in source[0]


def test_ra_stage_preview_exposes_zero_and_one_based_slot_coordinates() -> None:
    rows = dashboard.summarize_procedure_preview_rows(
        "ra_stage_waveforms",
        [{"UEId": 1, "StageName": "Msg1", "StageSlot": 9}],
    )
    assert rows == [{
        "UE": 1,
        "Stage": "Msg1",
        "Absolute slot (0-based)": 9,
        "Runtime slot (1-based)": 10,
    }]


def test_large_header_only_csv_does_not_advance_live_stage() -> None:
    artifacts = [artifact("air_interface/csv/ul_pusch_trials.csv", artifact_id=91)]
    artifacts[0]["byte_size"] = 50_000
    original = dashboard.load_small_csv_rows
    try:
        dashboard.load_small_csv_rows = lambda *_args, **_kwargs: []
        stage = dashboard.infer_effective_live_stage({"Stage": "pre_raw_sweep"}, artifacts)
        assert stage["Stage"] == "control_access_pending"
        assert stage["SourceStage"] == "pre_raw_sweep"
        assert stage["ULTrialsReady"] == 0

        dashboard.load_small_csv_rows = lambda *_args, **_kwargs: [{"Slot": 1}]
        stage = dashboard.infer_effective_live_stage({"Stage": "pre_raw_sweep"}, artifacts)
        assert stage["Stage"] == "ul_raw_trials_streaming"
        assert stage["ULTrialsReady"] == 1
    finally:
        dashboard.load_small_csv_rows = original


def test_publisher_raw_streaming_label_requires_parsed_trial_rows() -> None:
    artifacts = [artifact("air_interface/csv/ul_pusch_trials.csv", artifact_id=92)]
    artifacts[0]["byte_size"] = 50_000
    original = dashboard.load_small_csv_rows
    try:
        dashboard.load_small_csv_rows = lambda *_args, **_kwargs: []
        stage = dashboard.infer_effective_live_stage(
            {"Stage": "dl_ul_raw_trials_streaming", "DLTrialRows": 0, "ULTrialRows": 0},
            artifacts,
        )
        assert stage["Stage"] == "control_access_pending"
        assert stage["SourceStage"] == "dl_ul_raw_trials_streaming"
        assert stage["DLTrialsReady"] == 0
        assert stage["ULTrialsReady"] == 0
    finally:
        dashboard.load_small_csv_rows = original


def test_blank_runtime_truth_flags_do_not_become_negative_claims() -> None:
    truth = dashboard.infer_runtime_truth_modes(
        {},
        [
            {
                "ChannelUsesSameRuntimeAntennaAssumptions": "",
                "InterferenceUsesSameRuntimeAntennaAssumptions": "",
                "InterferencePathUsesSameArrayAssumptions": "",
                "TRSInfluencedDecision": "",
                "ParallelExecutionActive": "",
            }
        ],
    )
    assert "channel_uses_same_runtime_antenna_assumptions" not in truth
    assert "interference_uses_same_runtime_antenna_assumptions" not in truth
    assert "interference_path_uses_same_array_assumptions" not in truth
    assert "trs_influenced_decision" not in truth
    assert "parallel_execution_active" not in truth


def test_srs_signal_enablement_is_not_global_scheduler_admission() -> None:
    # The selected H4 scenario deliberately has SRS on and the global gate
    # off. This must not present the physical SRS feature as disabled.
    cfg = {"users": {"execution_model": "slot_coupled_truth"},
           "reference_signals": {"srs_enabled": True},
           "control_gating": {"srs_required": False}}
    truth = dashboard.infer_browser_truth_modes(cfg)
    assert truth["configured_srs_enabled"] is True
    assert truth["srs_mode"] == "configured_srs_without_global_scheduler_gate"
    assert truth["srs_gating_active"] is False
    assert "srs_valid" not in truth  # Configuration is not received evidence.
    cfg["control_gating"]["srs_required"] = True
    assert dashboard.infer_browser_truth_modes(cfg)["srs_mode"] == "srs_freshness_csi_gate"
    cfg["reference_signals"]["srs_enabled"] = False
    assert "configuration_conflict" in dashboard.infer_browser_truth_modes(cfg)["srs_mode"]
    cfg["control_gating"]["srs_required"] = "false"
    cfg["reference_signals"]["srs_enabled"] = "false"
    truth = dashboard.infer_browser_truth_modes(cfg)
    assert truth["srs_mode"] == "disabled" and truth["srs_gating_active"] is False
    absent = dashboard.infer_browser_truth_modes({})
    assert absent["configured_srs_enabled"] is None
    assert absent["srs_mode"] == "configuration_unavailable"


def test_srs_runtime_evidence_overrides_mode_not_configuration() -> None:
    cfg = {"reference_signals": {"srs_enabled": True},
           "control_gating": {"srs_required": False}}
    truth = dashboard.infer_runtime_truth_modes(cfg, [{
        "SRSMode": "received_causal_srs", "SRSGatingActive": "0"}])
    assert truth["srs_mode"] == "received_causal_srs"
    assert truth["configured_srs_enabled"] is True
    assert truth["srs_gating_active"] is False
    native = dashboard.infer_runtime_truth_modes({**cfg, "schemaVersion": "sixgr.lls.config/v1"}, [])
    assert native["srs_mode"] == "disabled"
    assert native["configured_srs_enabled"] is False


def test_artifact_content_version_changes_for_stable_id_in_place_update(tmp_path: Path) -> None:
    run_folder = tmp_path / "run"
    live_path = run_folder / "reports" / "csv" / "live_control_gating_state.csv"
    live_path.parent.mkdir(parents=True)
    live_path.write_text("Slot,State\n1,old\n", encoding="utf-8")
    row = artifact("reports/csv/live_control_gating_state.csv", artifact_id=77)
    row["filesystem_path"] = str(live_path)
    row["byte_size"] = live_path.stat().st_size
    run = {"run_folder": str(run_folder)}
    first = dashboard.artifact_content_version([row], run)

    live_path.write_text("Slot,State\n2,new\n", encoding="utf-8")
    second = dashboard.artifact_content_version([row], run)
    assert first != second


def test_data_preview_retains_crc_and_measured_beam_fields() -> None:
    rows = dashboard.summarize_data_trial_preview_rows(
        "dl_trials",
        [
            {
                "Slot": 7,
                "UEID": 2,
                "Direction": "DL",
                "MCSIndex": 11,
                "Modulation": "64QAM",
                "MeasuredTrialSINR_dB": 13.25,
                "CRCPass": 1,
                "SchedulerCQIRawCQI": 7,
                "AppliedLinkAdaptationMCS": 11,
                "SelectedBeamIndex": 3,
                "PMI": 2,
                "AppliedPrecoderPMI": 2,
                "RequestedPrecoderPMI": 3,
                "RequestedPrecoderSource": "delayed_csi_report_pmi",
                "RequestedVsAppliedPrecoderPMIMatchStatus": "requested_equals_runtime_applied_matrix_after_csirs_basis_composition",
                "AppliedPrecoderPMITruthClassification": "applied_runtime_value",
                "AppliedBeamIndexSet": "3",
                "SelectedBeamGain_dB": 8.75,
                "BestBeamIndex": 4,
                "BestBeamGain_dB": 9.25,
                "BeamGainGap_dB": 0.5,
            }
        ],
    )
    assert rows == [
        {
            "Direction": "DL",
            "Slot": 7,
            "UE": 2,
            "MCS": 11,
            "Modulation": "64QAM",
            "Measured SINR dB": 13.25,
            "CRC pass": 1,
            "Scheduler CQI used": 7,
            "LA MCS": 11,
            "Beam": 3,
            "PMI": 2,
            "Requested CSI PMI": 3,
            "PMI request source": "delayed_csi_report_pmi",
            "Applied basis PMI": 2,
            "Applied beam": "3",
            "Precoder match": "requested_equals_runtime_applied_matrix_after_csirs_basis_composition",
            "Applied PMI status": "applied_runtime_value",
            "Applied beam gain dB": 8.75,
            "Best measured beam": 4,
            "Best beam gain dB": 9.25,
            "Beam gap dB": 0.5,
            "Best projection index": 4,
            "Best projection power (dB)": 9.25,
            "Selected projection power (dB)": 8.75,
            "Projection gap (dB)": 0.5,
            "Decode acceptance": "decoded CRC and channel-specific context checks; not an EVM limit",
        }
    ]


def test_component_view_detection_does_not_hide_canonical_roots() -> None:
    assert not dashboard.is_component_view_artifact_path(
        "air_interface/csv/dl_pdsch_trials.csv"
    )
    assert not dashboard.is_component_view_artifact_path(
        "system/image/system_topology.png"
    )
    assert dashboard.is_component_view_artifact_path(
        "pdsch/image/dl_bler_vs_snr.png"
    )
    assert dashboard.is_component_view_artifact_path(
        "components/pdsch/png/pdsch_bler_vs_snr.png"
    )
    assert dashboard.is_contract_component_artifact_path(
        "components/pdsch/png/pdsch_bler_vs_snr.png"
    )
    assert dashboard.is_contract_component_artifact_path(
        "components/frame_grid/qualification/png/resource_grid.png"
    )
    assert dashboard.is_runtime_contract_component_artifact_path(
        "components/pdsch/png/pdsch_bler_vs_snr.png"
    )
    assert not dashboard.is_runtime_contract_component_artifact_path(
        "components/frame_grid/qualification/png/resource_grid.png"
    )
    assert dashboard.is_component_qualification_artifact_path(
        "components/frame_grid/qualification/png/resource_grid.png"
    )
    for phase_component in ("mac", "protocol", "rsla", "integration"):
        assert dashboard.is_component_qualification_artifact_path(
            f"components/{phase_component}/qualification/csv/evidence.csv"
        )
    assert not dashboard.is_contract_component_artifact_path(
        "pdsch/image/dl_bler_vs_snr.png"
    )


def test_manifest_hides_mirrors_from_primary_gallery_only() -> None:
    rows = [
        artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=1),
        artifact("pdsch/csv/dl_pdsch_trials.csv", artifact_id=2),
    ]
    assert dashboard.prefer_canonical_artifacts_over_component_views(rows, None) == rows
    filtered = dashboard.prefer_canonical_artifacts_over_component_views(
        rows, artifact("reports/csv/component_artifact_publication_manifest.csv", artifact_id=3)
    )
    assert [row["artifact_id"] for row in filtered] == [1]


def test_completed_contract_tree_replaces_legacy_results_authority() -> None:
    rows = [
        artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=1),
        artifact("reports/image/dl_bler_old.png", "image/png", 2),
        artifact("components/pdsch/csv/pdsch_bler_curve.csv", artifact_id=3),
        artifact(
            "components/pdsch/png/pdsch_bler_vs_snr.png", "image/png", 4
        ),
        artifact(
            "artifact_generation/canonical_component_manifest.csv", artifact_id=5
        ),
    ]
    selected, authority = dashboard.select_primary_result_artifacts(rows)
    selected_paths = {row["logical_path"] for row in selected}
    assert authority["status"] == "contract_components_authoritative"
    assert authority["evidence_scope"] == "in_path_runtime"
    assert authority["canonical_count"] == 2
    assert authority["legacy_diagnostic_count"] == 2
    assert "components/pdsch/csv/pdsch_bler_curve.csv" in selected_paths
    assert "components/pdsch/png/pdsch_bler_vs_snr.png" in selected_paths
    assert "air_interface/csv/dl_pdsch_trials.csv" not in selected_paths
    assert "reports/image/dl_bler_old.png" not in selected_paths


def test_generation_audit_without_atomic_component_payload_is_not_authority() -> None:
    rows = [
        artifact("reports/csv/scenario_summary.csv", artifact_id=1),
        artifact(
            "artifact_generation/artifact_generation_results.csv", artifact_id=2
        ),
        artifact("components/pdsch/csv/partial.csv", artifact_id=3),
    ]
    selected, authority = dashboard.select_primary_result_artifacts(rows)
    assert selected == []
    assert authority["status"] == "no_atomic_result_authority"
    assert authority["evidence_scope"] == "unaccepted_diagnostics"
    assert authority["canonical_count"] == 0
    assert authority["legacy_diagnostic_count"] == len(rows)


def test_atomic_qualification_manifest_selects_only_scoped_qualification() -> None:
    rows = [
        artifact("reports/csv/scenario_summary.csv", artifact_id=1),
        artifact(
            "components/frame_grid/qualification/csv/allocation_legality.csv",
            artifact_id=2,
        ),
        artifact(
            "components/frame_grid/qualification/png/resource_grid.png",
            "image/png",
            3,
        ),
        artifact(
            "artifact_generation/component_qualification_manifest.csv",
            artifact_id=4,
        ),
        artifact(
            "artifact_generation/component_qualification_summary.csv",
            artifact_id=5,
        ),
    ]
    selected, authority = dashboard.select_primary_result_artifacts(rows)
    selected_paths = {row["logical_path"] for row in selected}
    assert authority["status"] == "component_qualification_evidence_only"
    assert authority["evidence_scope"] == "component_validation_campaign"
    assert authority["canonical_count"] == 2
    assert "reports/csv/scenario_summary.csv" not in selected_paths
    assert len(selected) == 4
