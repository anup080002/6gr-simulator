"""Metadata-only audit fixtures, not simulated radio measurements."""
import importlib.util
import csv
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("ul_audit", Path(__file__).parents[1] / "tools/audit_lls_uplink_evidence.py")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class UplinkEvidenceAuditTest(unittest.TestCase):
    def row(self):
        return dict(Slot="3", UCIExpectedBitVector="00101", UCIDecodedBitVector="00101",
                    UCIBitErrorVector="00000", ExpectedBitCount="5", DecodedBitCount="5",
                    UCIContentMatch="1", PUCCHDecodeOk="1", UCICRCBitCount="0",
                    UCICRCApplicable="0", CRCApplicable="0", CRCPass="NaN",
                    TimingEstimateSource="received_reference_correlation_bounded_search",
                    AppliedTimingCorrectionSamples="84", TimingEstimateUsed="1")

    def failures(self, row, channel="PUCCH"):
        return [item["Check"] for item in AUDIT.audit_rows(channel, [row]) if not item["Passed"]]

    def test_consistent_metadata(self):
        self.assertEqual([], self.failures(self.row()))

    def test_pusch_pre_equalization_decoder_noise_domain(self):
        row = dict(DecoderNoiseVarianceConfiguredMode="pre_equalization",
                   LLRNoiseVarianceSource="configured_pre_equalization_noise_variance",
                   LLRNoiseVarianceDomain="pre_equalization_channel_estimator_noise_variance_for_nrPUSCHDecode",
                   LLRNoiseVariance=0.0026, PreEqualizationNoiseVariance=0.0026)
        self.assertEqual([], self.failures(row, "PUSCH"))
        # Integrated exports retain the executed source, not necessarily
        # the optional configured-mode field. Do not silently skip them.
        del row["DecoderNoiseVarianceConfiguredMode"]
        row["LLRNoiseVarianceDomain"] = "unit_constellation_soft_demapper_input"
        self.assertIn("pusch_pre_equalization_llr_variance_domain", self.failures(row, "PUSCH"))
        row["LLRNoiseVariance"] = 0.0072
        self.assertIn("pusch_pre_equalization_llr_variance_value", self.failures(row, "PUSCH"))

    def test_leading_zero_corruption(self):
        row = self.row()
        row["UCIDecodedBitVector"] = "101"
        self.assertIn("DecodedBitCount_closure", self.failures(row))
        self.assertIn("uci_error_vector_closure", self.failures(row))

    def test_wrong_xor(self):
        row = self.row()
        row["UCIBitErrorVector"] = "00001"
        self.assertIn("uci_error_vector_closure", self.failures(row))

    def test_actual_decode_failure_is_not_synthetic_audit_failure(self):
        row = self.row()
        row.update(UCIDecodedBitVector="00100", UCIBitErrorVector="00001", UCIContentMatch="0", PUCCHDecodeOk="0")
        self.assertEqual([], self.failures(row))

    def test_false_timing_flag(self):
        row = self.row()
        row["TimingEstimateUsed"] = "0"
        self.assertIn("measured_timing_application_flag", self.failures(row))

    def test_empty_generic_source_does_not_hide_srs_timing(self):
        row = dict(TimingEstimateSource="", SRSReceiveTimingSource="received_reference_correlation_bounded_search",
                   AppliedTimingCorrection_samples="84", TimingEstimateUsed="0")
        self.assertIn("measured_timing_application_flag", self.failures(row, "SRS"))
        row["TimingEstimateUsed"] = "1"
        self.assertEqual([], self.failures(row, "SRS"))

    def test_usable_srs_missing_producer_provenance(self):
        row = dict(SRSRuntimeEvidenceUsable="1", RuntimeEvidenceSource="not_emitted_by_active_srs_runtime")
        self.assertIn("usable_srs_runtime_provenance", self.failures(row, "SRS"))
        row["RuntimeEvidenceSource"] = "metadata_test_named_producer_not_rf_evidence"
        self.assertEqual([], self.failures(row, "SRS"))

    def test_shared_srs_clock_and_pending_delivery(self):
        row = dict(RuntimeTransportMode="shared_physical_stream_SRS_received_completion",
                   ObservationStartSample="1000", ObservationEndSampleExclusive="1500",
                   ObservationSampleRateHz="1000000", ObservationCompletionTime_s="0.0015",
                   RuntimeStateUpdated="0", ObservationDeliveryTime_s="NaN")
        self.assertEqual([], self.failures(row, "SRS"))
        row.update(RuntimeStateUpdated="1", ObservationDeliveryTime_s="0.001")
        self.assertIn("shared_srs_no_future_delivery", self.failures(row, "SRS"))
        row["ObservationDeliveryTime_s"] = "0.002"
        self.assertEqual([], self.failures(row, "SRS"))
        row["ObservationEndSampleExclusive"] = "1501"
        self.assertIn("shared_srs_observation_clock", self.failures(row, "SRS"))

    def srs_prediction(self):
        # Arithmetic/provenance fixture only, not a receiver measurement.
        return dict(PredictedPUSCHPostEqSINRValueStatus="PASS",
                    PredictedPUSCHPostEqSINRValueRole=
                    "power_plane_calibrated_predicted_pusch_data_channel_scheduling_input",
                    PredictedPUSCHPostEqSINRSource=
                    "receiver_measured_srs_reference_power_selected_ri_tpmi_mmse_layer_prediction",
                    PredictedPUSCHPostEqSINRCalibrationOffset_dB="0",
                    PredictedPUSCHPostEqSINRAnchor_dB="20",
                    PredictedPUSCHPostEqSINRAnchorSource="measured_ul_srs_pilot_reconstruction_sinr",
                    PredictedPUSCHPostEqSINRPowerReferencePlane=
                    "receiver_srs_resource_elements_after_ofdm_demodulation",
                    PredictedPUSCHReferenceSignalPower="1",
                    PredictedPUSCHDisturbancePower="0.01",
                    RankEstimate="2",
                    PredictedPUSCHPostEqSINRPerLayer_dB="16.9897|16.9897",
                    PredictedPUSCHMinimumLayerSINR_dB="16.9897000433602",
                    PredictedPUSCHWidebandMeanSINR_dB="16.9897000433602",
                    PUSCHToSRSReferenceEnergyRatio="1",
                    PUSCHToSRSReferenceEnergySource=
                    "normalized_fixed_snr_unit_grid_reference_no_device_power_scaling")

    def test_srs_prediction_cannot_shift_post_mmse_layer_sinr(self):
        row = self.srs_prediction()
        self.assertEqual([], self.failures(row, "SRS"))
        for offset in ("3.0103", "-3", "NaN"):
            row["PredictedPUSCHPostEqSINRCalibrationOffset_dB"] = offset
            self.assertIn("srs_prediction_no_post_mmse_shift", self.failures(row, "SRS"))

    def test_srs_prediction_requires_actual_power_provenance(self):
        for field in ("PredictedPUSCHReferenceSignalPower", "PredictedPUSCHDisturbancePower",
                      "PUSCHToSRSReferenceEnergyRatio", "PUSCHToSRSReferenceEnergySource",
                      "PredictedPUSCHPostEqSINRSource", "PredictedPUSCHPostEqSINRAnchorSource",
                      "PredictedPUSCHPostEqSINRPowerReferencePlane"):
            row = self.srs_prediction()
            del row[field]
            self.assertIn("srs_prediction_power_provenance", self.failures(row, "SRS"), field)

    def test_srs_prediction_reference_power_must_close(self):
        row = self.srs_prediction()
        row["PredictedPUSCHDisturbancePower"] = "0.001"
        self.assertIn("srs_prediction_reference_power_closure", self.failures(row, "SRS"))

    def test_srs_prediction_old_anchor_only_source_is_not_authority(self):
        row = self.srs_prediction()
        row["PredictedPUSCHPostEqSINRSource"] = (
            "receiver_measured_srs_sinr_anchored_selected_ri_tpmi_mmse_relative_layer_prediction")
        self.assertIn("srs_prediction_power_provenance", self.failures(row, "SRS"))

    def test_unavailable_srs_prediction_is_not_fabricated_into_a_failure(self):
        row = dict(PredictedPUSCHPostEqSINRValueStatus="DIAGNOSTIC_ONLY_UNCALIBRATED_POWER_PLANE")
        self.assertEqual([], self.failures(row, "SRS"))

    def test_srs_prediction_requires_one_finite_value_per_selected_layer(self):
        for vector in ("16.9897", "16.9897|NaN", "16.9897||16.9897", ""):
            row = self.srs_prediction()
            row["PredictedPUSCHPostEqSINRPerLayer_dB"] = vector
            self.assertIn("srs_prediction_layer_count", self.failures(row, "SRS"), vector)

    def test_srs_prediction_minimum_is_not_the_pilot_sinr(self):
        row = self.srs_prediction()
        row["PredictedPUSCHMinimumLayerSINR_dB"] = "20"
        self.assertIn("srs_prediction_minimum_layer_closure", self.failures(row, "SRS"))

    def test_srs_prediction_mean_is_linear_not_db_average(self):
        row = self.srs_prediction()
        row.update(PredictedPUSCHPostEqSINRPerLayer_dB="10|20",
                   PredictedPUSCHMinimumLayerSINR_dB="10",
                   PredictedPUSCHWidebandMeanSINR_dB="17.4036268949424")
        self.assertEqual([], self.failures(row, "SRS"))
        row["PredictedPUSCHWidebandMeanSINR_dB"] = "15"
        self.assertIn("srs_prediction_mean_layer_closure", self.failures(row, "SRS"))

    def test_fake_nonapplicable_crc_pass(self):
        row = self.row()
        row["CRCPass"] = "1"
        self.assertIn("nonapplicable_pucch_crc_not_passed", self.failures(row))
        self.assertNotIn("nonapplicable_pucch_crc_not_passed", self.failures(row, "PUSCH"))

    def srs_grant_pair(self):
        srs = self.srs_prediction()
        identity = dict(UEIndex="1", RNTI="7", ServingCell="1", ConfiguredSNR_dB="20")
        srs.update(identity, Slot="30")
        grant = dict(identity, Slot="35", LinkAdaptationAppliedFeedbackSourceSlot="30",
                     LinkAdaptationAppliedFeedbackAgeSlots="5",
                     SchedulerCQISource="ul_srs_power_plane_calibrated_selected_ri_tpmi_minimum_layer_post_equalization",
                     SchedulerSINRBackoff_dB="1", SchedulerAdjustedSINR_dB="15.9897000433602")
        return srs, grant

    def grant_failures(self, srs, grant):
        return [c["Check"] for c in AUDIT.audit_srs_grant_binding(srs, [grant]) if not c["Passed"]]

    def test_srs_grant_binding_preserves_explicit_backoff(self):
        srs, grant = self.srs_grant_pair()
        self.assertEqual([], self.grant_failures([srs], grant))
        grant["SchedulerAdjustedSINR_dB"] = "20"
        self.assertIn("srs_grant_prediction_binding", self.grant_failures([srs], grant))

    def test_srs_grant_binding_rejects_wrong_or_ambiguous_source(self):
        for field in ("Slot", "UEIndex", "RNTI", "ServingCell", "ConfiguredSNR_dB"):
            srs, grant = self.srs_grant_pair()
            srs[field] = "99"
            self.assertIn("srs_grant_unique_source", self.grant_failures([srs], grant), field)
        srs, grant = self.srs_grant_pair()
        self.assertIn("srs_grant_unique_source", self.grant_failures([srs, srs], grant))

    def test_srs_grant_binding_requires_trusted_prediction_and_valid_age(self):
        srs, grant = self.srs_grant_pair()
        srs["PredictedPUSCHPostEqSINRValueStatus"] = "DIAGNOSTIC_ONLY_UNCALIBRATED_POWER_PLANE"
        self.assertIn("srs_grant_prediction_binding", self.grant_failures([srs], grant))
        srs, grant = self.srs_grant_pair()
        grant["LinkAdaptationAppliedFeedbackAgeSlots"] = "0"
        self.assertIn("srs_grant_source_age", self.grant_failures([srs], grant))
        grant.update(Slot="29", LinkAdaptationAppliedFeedbackAgeSlots="-1")
        self.assertIn("srs_grant_source_age", self.grant_failures([srs], grant))

    def test_srs_grant_binding_does_not_invent_other_feedback_sources(self):
        _, grant = self.srs_grant_pair()
        grant["SchedulerCQISource"] = "received_pusch_feedback"
        self.assertEqual([], AUDIT.audit_srs_grant_binding([], [grant]))

    def test_run_audit_executes_cross_table_srs_binding(self):
        srs, grant = self.srs_grant_pair()
        grant["SchedulerAdjustedSINR_dB"] = "20"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            directory = root / "air_interface/csv"
            directory.mkdir(parents=True)
            for stem, row in (("srs", srs), ("ul_pusch", grant)):
                with (directory / (stem + "_trials.csv")).open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.DictWriter(handle, fieldnames=list(row))
                    writer.writeheader()
                    writer.writerow(row)
            receipt = AUDIT.audit_run(root)
        self.assertEqual(["srs_grant_prediction_binding"],
                         [c["Check"] for c in receipt["Checks"] if not c["Passed"]])
        self.assertEqual(1, receipt["FailedChecks"])
        self.assertFalse(receipt["CrossFileAtomicCheckpoint"])
        self.assertEqual(2, len(receipt["Sources"]))

    def test_missing_decoded_payload(self):
        row = self.row()
        row["UCIDecodedBitVector"] = ""
        self.assertIn("successful_pucch_has_complete_payload", self.failures(row))

    def test_explicit_unavailable_failed_decode_is_not_binary_payload(self):
        row = dict(PUCCHDecodeOk="0", UCIDecodedBitVector="not_applicable_for_active_pucch_runtime")
        self.assertEqual([], self.failures(row))
        row["PUCCHDecodeOk"] = "1"
        self.assertIn("successful_pucch_has_complete_payload", self.failures(row))

    def receiver_only(self):
        return dict(PUCCHDecodeOk="1", ReceiverUsable="1", DTXFlag="0",
                    ReceiverOnlyAssignment="1", PUCCHTransmissionPrepared="0",
                    UCIDecodedBitVector="10110110100", ReceiverExpectedHARQBitCount="0",
                    ReceiverExpectedSRBitCount="1", ReceiverExpectedCSIPart1BitCount="10",
                    ReceiverExpectedCSIPart2BitCount="0")

    def test_receiver_only_uses_independent_width_not_transmitted_reference(self):
        row = self.receiver_only()
        self.assertEqual([], self.failures(row))
        row["ReceiverExpectedCSIPart2BitCount"] = "1"
        self.assertIn("successful_pucch_has_complete_payload", self.failures(row))
        del row["ReceiverExpectedCSIPart2BitCount"]
        self.assertIn("successful_pucch_has_complete_payload", self.failures(row))

    def test_union_schema_unavailable_counts_are_not_zero_or_measured_counts(self):
        row = self.receiver_only()
        row.update(ExpectedBitCount="NaN", DecodedBitCount="NaN",
                   PUCCHExpectedBitCount="NaN", PUCCHDecodedBitCount="NaN")
        self.assertEqual([], self.failures(row))
        row["DecodedBitCount"] = "10"
        self.assertIn("DecodedBitCount_closure", self.failures(row))
        row["DecodedBitCount"] = "malformed"
        self.assertIn("DecodedBitCount_closure", self.failures(row))

    def test_receiver_only_cannot_hide_contradictory_receiver_flags(self):
        row = self.receiver_only()
        row["ReceiverUsable"] = "0"
        self.assertIn("successful_pucch_receiver_flags", self.failures(row))
        row.update(ReceiverUsable="1", DTXFlag="1")
        self.assertIn("successful_pucch_receiver_flags", self.failures(row))

    def receiver_context(self):
        row = self.receiver_only()
        row.update(ReceiverExpectedBitCount="11",
                   ReceiverExpectedBitCountSource="receiver_length_context",
                   ReceiverContextDigest="metadata_fixture_context_not_rf_qualification")
        return row

    def test_receiver_context_total_must_match_all_independent_fields(self):
        row = self.receiver_context()
        self.assertEqual([], self.failures(row))
        for value in ("10", "11.5", "malformed", "NaN"):
            row["ReceiverExpectedBitCount"] = value
            self.assertIn("receiver_context_width_closure", self.failures(row))

    def test_receiver_context_requires_source_and_digest(self):
        for field, value in (("ReceiverExpectedBitCountSource", "transmitted_payload"),
                             ("ReceiverContextDigest", ""),
                             ("ReceiverContextDigest", "NaN")):
            row = self.receiver_context()
            row[field] = value
            self.assertIn("receiver_context_provenance", self.failures(row))

    def test_receiver_only_cannot_invent_transmitted_reference_or_success(self):
        for field, value in (("UCIExpectedBitVector", "10110110100"),
                             ("UCIBitErrorVector", "00000000000"),
                             ("SuccessFlag", "1")):
            row = self.receiver_context()
            row[field] = value
            self.assertIn("receiver_only_no_transmission_claim", self.failures(row))

    def test_dtx_still_requires_consistent_installed_receiver_context(self):
        row = self.receiver_context()
        row.update(PUCCHDecodeOk="0", ReceiverUsable="0", DTXFlag="1",
                   UCIDecodedBitVector="", DecodedBitCount="0")
        self.assertEqual([], self.failures(row))
        row["ReceiverExpectedCSIPart2BitCount"] = "1"
        self.assertIn("receiver_context_width_closure", self.failures(row))

    def test_missing_expected_bits_for_transmitted_trial_still_fails(self):
        row = self.receiver_only()
        row["PUCCHTransmissionPrepared"] = "1"
        self.assertIn("successful_pucch_has_complete_payload", self.failures(row))

    def test_malformed_bits_are_not_unavailable_markers(self):
        for value in ("10X01", "not_applicable_typo", "not_applicable_for_active_pucch_runtime101"):
            row = dict(PUCCHDecodeOk="0", UCIDecodedBitVector=value)
            self.assertIn("uci_binary_vectors", self.failures(row))

    def test_no_producer_detection_is_retained_not_qualified(self):
        row = self.receiver_only()
        row["Slot"] = "24"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root / "air_interface/csv/pucch_trials.csv"
            target.parent.mkdir(parents=True)
            with target.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(row))
                writer.writeheader()
                writer.writerow(row)
            receipt = AUDIT.audit_run(root)
        self.assertEqual(0, receipt["FailedChecks"])
        self.assertEqual("observed_uplink_evidence_consistency_not_phy_qualification", receipt["Scope"])
        self.assertEqual(1, len(receipt["ReceiverOnlyNoProducerDetections"]))
        self.assertEqual("24", receipt["ReceiverOnlyNoProducerDetections"][0]["Slot"])
        self.assertEqual(row["UCIDecodedBitVector"], receipt["ReceiverOnlyNoProducerDetections"][0]["DecodedBits"])


class DataFeedbackBindingTest(unittest.TestCase):
    """Declared metadata fixtures, never physical qualification evidence."""

    def pair(self):
        identity = dict(UEIndex="1", RNTI="7", ServingCell="1")
        raw = dict(identity, Slot="35", ConfiguredSNR_dB="20", PostEqSINR_dB="21.5",
                   PostEqSINRSource="receiver_post_equalization_data",
                   PostEqSINRValueRole="measured_post_equalization_scheduling_input",
                   PostEqSINRValueStatus="OK", ReceiverHestSINR_dB="19.7")
        report = dict(identity, Direction="UL", SourceSlot="35", DeliveredSlot="36",
                      SourceSignal="PUSCH-DMRS", SINR_dB="21.5",
                      SINRSource=raw["PostEqSINRSource"],
                      SINRValueRole=raw["PostEqSINRValueRole"], SINRValueStatus="OK",
                      SchedulerAdjustedSINR_dB="20", SchedulerSINRBackoff_dB="1")
        # The reported adjustment may also contain directional backoff. The
        # audit checks the frozen decision, not an invented aging formula.
        grant = dict(identity, Slot="40", SchedulerCQISource="runtime_reported_cqi",
                     LinkAdaptationAppliedFeedbackSourceSlot="35",
                     LinkAdaptationAppliedFeedbackAgeSlots="5",
                     SchedulerAdjustedSINR_dB="20", SchedulerSINRBackoff_dB="1")
        return raw, report, grant

    def failures(self, rows, reports):
        return [c["Check"] for c in AUDIT.audit_data_feedback_binding(rows, reports)
                if not c["Passed"]]

    def test_preserves_source_plane_and_frozen_grant_decision(self):
        raw, report, grant = self.pair()
        self.assertEqual([], self.failures([raw, grant], [report]))

    def test_rejects_reference_plane_substitution_and_provenance_laundering(self):
        for field, value in [("SINR_dB", "19.7"), ("SINRSource", "conservative_min_pilot"),
                             ("SINRValueRole", "estimated"), ("SINRValueStatus", "failed")]:
            raw, report, grant = self.pair()
            report[field] = value
            self.assertIn("data_feedback_receiver_plane_binding",
                          self.failures([raw, grant], [report]), field)

    def test_rejects_missing_ambiguous_and_wrong_receiver_identity(self):
        raw, report, grant = self.pair()
        for rows in ([grant], [raw, raw, grant], [dict(raw, RNTI="99"), grant]):
            self.assertIn("data_feedback_unique_receiver_source", self.failures(rows, [report]))
        for reports in ([], [report, report], [dict(report, ServingCell="99")]):
            self.assertIn("data_grant_unique_feedback_source", self.failures([raw, grant], reports))

    def test_rejects_stale_future_or_changed_frozen_decision(self):
        for field, value, expected in [
            ("LinkAdaptationAppliedFeedbackAgeSlots", "4", "data_grant_source_age"),
            ("Slot", "34", "data_grant_source_age"),
            ("SchedulerAdjustedSINR_dB", "19.7", "data_grant_decision_binding"),
            ("SchedulerSINRBackoff_dB", "0", "data_grant_decision_binding")]:
            raw, report, grant = self.pair()
            grant[field] = value
            self.assertIn(expected, self.failures([raw, grant], [report]))
        raw, report, grant = self.pair()
        report["DeliveredSlot"] = "41"
        self.assertIn("data_grant_report_delivery_clock", self.failures([raw, grant], [report]))

    def test_does_not_apply_data_rule_to_srs_or_dl_payload(self):
        raw, report, grant = self.pair()
        grant["SchedulerCQISource"] = "ul_srs_power_plane_calibrated_selected_ri_tpmi_minimum_layer_post_equalization"
        report["Direction"] = "DL"
        self.assertEqual([], AUDIT.audit_data_feedback_binding([raw, grant], [report]))

    def test_matching_but_untrusted_provenance_still_fails(self):
        for role in ("", "estimated_post_equalization", "diagnostic_post_equalization"):
            raw, report, grant = self.pair()
            raw["PostEqSINRValueRole"] = report["SINRValueRole"] = role
            self.assertIn("data_feedback_receiver_plane_binding", self.failures([raw, grant], [report]))

    def test_run_entrypoint_checks_saved_feedback_bytes(self):
        raw, report, grant = self.pair()
        report["SINR_dB"] = "19.7"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            directory = root / "air_interface/csv"
            directory.mkdir(parents=True)
            for name, rows in (("ul_pusch_trials.csv", [raw, grant]),
                               ("csi_feedback_reports.csv", [report])):
                fields = sorted({key for row in rows for key in row})
                with (directory / name).open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.DictWriter(handle, fieldnames=fields)
                    writer.writeheader()
                    writer.writerows(rows)
            receipt = AUDIT.audit_run(root)
        self.assertEqual(["data_feedback_receiver_plane_binding"],
                         [c["Check"] for c in receipt["Checks"] if not c["Passed"]])
        self.assertEqual(1, receipt["Coverage"]["CSIFeedback"]["Rows"])
        self.assertEqual(2, len(receipt["Sources"]))


class ReceivedCSIBindingTest(unittest.TestCase):
    """Metadata consistency only; not a waveform detection campaign."""

    def pair(self):
        identity = dict(UEIndex="1", RNTI="7", ServingCell="1",
                        ReceiverContextDigest="independent_context_fixture")
        trial = dict(identity, Slot="24", PUCCHDecodeOk="1", ReceiverUsable="1",
                     DTXFlag="0", RuntimeStateUpdated="1", ControlStateChanged="1",
                     StateChangeApplied="1", ReceiverOnlyAssignment="1",
                     PUCCHTransmissionPrepared="0", SuccessFlag="0")
        report = dict(identity, DueSlot="24", CSIUCIChannel="PUCCH",
                      CSIUCIDecodeOk="1", DeliveryStatus="delivered_to_runtime_scheduler")
        return trial, report

    def failures(self, trials, reports):
        return [c["Check"] for c in AUDIT.audit_received_csi_binding(trials, reports)
                if not c["Passed"]]

    def test_receiver_only_delivery_is_not_hidden_or_promoted_to_transmission(self):
        trial, report = self.pair()
        self.assertEqual([], self.failures([trial], [report]))
        self.assertEqual("0", trial["PUCCHTransmissionPrepared"])
        self.assertEqual("0", trial["SuccessFlag"])
        for field in ("RuntimeStateUpdated", "ControlStateChanged", "StateChangeApplied"):
            broken = dict(trial, **{field: "0"})
            self.assertIn("received_csi_delivery_state_change_visible", self.failures([broken], [report]))

    def test_join_rejects_missing_duplicate_or_other_ue_context(self):
        trial, report = self.pair()
        for rows in ([], [trial, trial], [dict(trial, RNTI="9")],
                     [dict(trial, Slot="29")], [dict(trial, ReceiverContextDigest="other")]):
            self.assertIn("received_csi_unique_pucch_context", self.failures(rows, [report]))
        for field in ("ReceiverContextDigest", "UEIndex", "DueSlot"):
            broken = dict(report, **{field: ""})
            self.assertIn("received_csi_unique_pucch_context", self.failures([trial], [broken]))

    def test_delivered_report_requires_actual_usable_decode(self):
        trial, report = self.pair()
        for field, value in (("DTXFlag", "1"), ("ReceiverUsable", "0"), ("PUCCHDecodeOk", "0")):
            self.assertIn("received_csi_delivery_requires_decode",
                          self.failures([dict(trial, **{field: value})], [report]))
        self.assertIn("received_csi_delivery_requires_decode",
                      self.failures([trial], [dict(report, CSIUCIDecodeOk="0")]))

    def test_prepared_cell_identity_alias_is_explicit_and_cannot_conflict(self):
        trial, report = self.pair()
        trial.update(ServingCell="NaN", BaseStationID="1")
        self.assertEqual([], self.failures([trial], [report]))
        for cell, base in (("1", "2"), ("NaN", "2"), ("NaN", "NaN")):
            trial.update(ServingCell=cell, BaseStationID=base)
            self.assertIn("received_csi_unique_pucch_context", self.failures([trial], [report]))

    def test_failed_or_stale_csi_does_not_erase_other_uci_state_changes(self):
        trial, report = self.pair()
        for status in ("receiver_csi_unavailable_not_delivered", "stale_received_csi_ignored"):
            report.update(DeliveryStatus=status, CSIUCIDecodeOk="0")
            self.assertEqual([], self.failures([trial], [report]))
        report["CSIUCIChannel"] = "PUSCH"
        self.assertEqual([], AUDIT.audit_received_csi_binding([], [report]))

    def test_entrypoint_hashes_received_report_and_checks_state_change(self):
        trial, report = self.pair()
        trial["StateChangeApplied"] = "0"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            directory = root / "air_interface/csv"
            directory.mkdir(parents=True)
            for name, row in (("pucch_trials.csv", trial), ("received_csi_reports.csv", report)):
                with (directory / name).open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.DictWriter(handle, fieldnames=list(row))
                    writer.writeheader()
                    writer.writerow(row)
            receipt = AUDIT.audit_run(root)
        self.assertIn("received_csi_delivery_state_change_visible",
                      [c["Check"] for c in receipt["Checks"] if not c["Passed"]])
        self.assertEqual(1, receipt["Coverage"]["ReceivedCSI"]["Rows"])
        self.assertEqual(2, len(receipt["Sources"]))


class ReceivedSRBindingTest(unittest.TestCase):
    """Declared export fixtures, not physical SR or detector qualification."""
    def pair(self, tx=False, detected=False):
        report = dict(UEIndex=1, RNTI=7, ServingCell=1, Slot=4,
                      ReceiverAssignmentDigest="assignment4", ReceiverContextDigest="context4",
                      ObservationStartSample=1000, ObservationEndSampleExclusive=2000,
                      ObservationSampleRateHz=1000000, AvailableAtSample=2000,
                      UETransmissionExecuted=tx, PositiveSRDetected=detected,
                      ReceiverUsable=detected, DTXFlag=not detected,
                      FalseSRDetection=not tx and detected, MissedSRDetection=tx and not detected)
        trial = dict(report, UCIType="standalone_sr", ReceiverExpectedHARQBitCount=0,
                     ReceiverExpectedSRBitCount=1, ReceiverExpectedCSIPart1BitCount=0,
                     ReceiverExpectedCSIPart2BitCount=0, ReceiverExpectedBitCount=1,
                     ReceiverExpectedBitCountSource="receiver_length_context",
                     PUCCHTransmissionPrepared=tx, ReceiverOnlyAssignment=not tx,
                     PUCCHDecodeOk=detected, SuccessFlag=tx and detected, FailureFlag=tx != detected,
                     Status="PASS" if tx and detected else "NA" if not tx and not detected else "FAIL",
                     UCIContentMatch=int(detected) if tx else "NaN")
        return trial, report

    def failures(self, trials, reports):
        return [item["Check"] for item in AUDIT.audit_received_sr_binding(trials, reports) if not item["Passed"]]

    def test_all_four_truthful_outcomes_are_consistent_not_qualified(self):
        for tx in (False, True):
            for detected in (False, True):
                trial, report = self.pair(tx, detected)
                self.assertEqual([], self.failures([trial], [report]))

    def test_quiet_sr_cannot_be_decode_success_or_failure(self):
        for key, value in (("SuccessFlag", True), ("FailureFlag", True),
                           ("UCIContentMatch", 0), ("Status", "FAIL"), ("PUCCHDecodeOk", True)):
            trial, report = self.pair()
            trial[key] = value
            self.assertTrue(self.failures([trial], [report]), key)

    def test_false_and_missed_detections_cannot_be_hidden(self):
        for tx, detected in ((False, True), (True, False)):
            trial, report = self.pair(tx, detected)
            trial["FailureFlag"] = False
            self.assertIn("received_sr_outcome_scoring", self.failures([trial], [report]))

    def test_missing_duplicate_and_wrong_context(self):
        trial, report = self.pair()
        self.assertTrue(self.failures([trial], []))
        self.assertTrue(self.failures([], [report]))
        self.assertTrue(self.failures([trial, trial], [report]))
        self.assertTrue(self.failures([trial], [report, report]))
        for key, value in (("UEIndex", 2), ("RNTI", 8), ("ServingCell", 2), ("Slot", 9),
                           ("ReceiverContextDigest", "other"), ("ReceiverAssignmentDigest", "")):
            self.assertTrue(self.failures([trial], [dict(report, **{key: value})]), key)

    def test_clock_and_field_ownership_must_remain_exact(self):
        trial, report = self.pair()
        self.assertIn("received_sr_completed_clock", self.failures([trial], [dict(report, AvailableAtSample=1999)]))
        trial["ReceiverExpectedCSIPart1BitCount"] = 10
        self.assertIn("received_sr_field_ownership", self.failures([trial], [report]))

    def test_entrypoint_reads_control_sidecar_and_hashes_exact_bytes(self):
        trial, report = self.pair()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for relative, row in (("air_interface/csv/pucch_trials.csv", trial),
                                  ("control/csv/received_sr_observations.csv", report)):
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.DictWriter(handle, fieldnames=list(row))
                    writer.writeheader()
                    writer.writerow(row)
            receipt = AUDIT.audit_run(root)
        self.assertEqual(0, receipt["FailedChecks"])
        self.assertEqual(1, receipt["Coverage"]["ReceivedSR"]["Rows"])
        self.assertEqual(2, len(receipt["Sources"]))
        self.assertTrue(any(source["Path"] == "control/csv/received_sr_observations.csv" and
                            len(source["SHA256"]) == 64 for source in receipt["Sources"]))


class PUCCHHARQBindingAuditTest(unittest.TestCase):
    def pair(self):
        # Declared metadata fixture: no radio execution or qualification.
        trial = dict(UEIndex=1, RNTI=7, Slot=34, GNBHARQMappingDigest="a" * 64,
                     ObservationStartSample=1000, ObservationEndSampleExclusive=2000,
                     ObservationSampleRateHz=1000000, ReceiverExpectedHARQBitCount=2,
                     ReceiverExpectedBitCount=3, UCIDecodedBitVector="101",
                     PUCCHDecodeOk=1, DTXFlag=0, ReceiverUsable=1,
                     HARQFeedbackAppliedCount=2, StaleHARQFeedbackCount=0)
        reports = [dict(UCITransport="PUCCH", UEIndex=1, RNTI=7, TargetSlot=34,
                        MappingDigest="a" * 64, ObservationStartSample=1000,
                        ObservationEndSampleExclusive=2000, ObservationSampleRateHz=1000000,
                        AvailableAtSample=2000, BitIndex=i + 1, ReceiverUsable=1,
                        ReceiverVectorLengthMatches=1, FeedbackOutcome=outcome,
                        ObservedAck=int(outcome == "ACK"), StaleFeedbackIgnored=0,
                        HARQFeedbackApplied=1, StateChangeApplied=1)
                   for i, outcome in enumerate(("ACK", "NACK"))]
        return trial, reports

    def failures(self, trials, reports):
        return [c["Check"] for c in AUDIT.audit_pucch_harq_binding(trials, reports) if not c["Passed"]]

    def test_bound_ack_and_nack(self):
        trial, reports = self.pair()
        self.assertEqual([], self.failures([trial], reports))

    def test_missing_duplicate_wrong_identity_or_clock(self):
        trial, reports = self.pair()
        self.assertIn("harq_complete_unique_dispositions", self.failures([trial], reports[:1]))
        self.assertIn("harq_complete_unique_dispositions", self.failures([trial], reports + reports[:1]))
        self.assertIn("harq_unique_pucch_binding", self.failures([trial, trial], reports))
        for field, value in (("UEIndex", 2), ("RNTI", 9), ("TargetSlot", 35),
                             ("MappingDigest", "b" * 64), ("BitIndex", 2),
                             ("ObservationStartSample", 999), ("AvailableAtSample", 1999)):
            changed = [dict(reports[0], **{field: value}), reports[1]]
            self.assertTrue(self.failures([trial], changed), field)

    def test_bit_outcome_not_transmitter_scoring(self):
        trial, reports = self.pair()
        trial.update(PUCCHTransmissionPrepared=0, UCIExpectedBitVector="")
        self.assertEqual([], self.failures([trial], reports))  # Genuine false detection stays visible.
        reports[0].update(FeedbackOutcome="NACK", ObservedAck=0)
        self.assertIn("harq_decoded_bit_outcome", self.failures([trial], reports))

    def test_dtx_and_stale_counts(self):
        trial, reports = self.pair()
        trial.update(DTXFlag=1, PUCCHDecodeOk=0, ReceiverUsable=0,
                     UCIDecodedBitVector="", HARQFeedbackAppliedCount=1, StaleHARQFeedbackCount=1)
        for report in reports:
            report.update(ReceiverUsable=0, ReceiverVectorLengthMatches=0,
                          FeedbackOutcome="DTX", ObservedAck=0)
        reports[1].update(StaleFeedbackIgnored=1, HARQFeedbackApplied=0, StateChangeApplied=0)
        self.assertEqual([], self.failures([trial], reports))
        reports[1]["HARQFeedbackApplied"] = 1
        self.assertIn("harq_stale_application_consistency", self.failures([trial], reports))

    def test_no_ack_from_unusable_or_malformed_decoder(self):
        trial, reports = self.pair()
        reports[0]["ReceiverUsable"] = 0
        self.assertIn("harq_unusable_is_dtx", self.failures([trial], reports))
        reports[0]["ReceiverUsable"] = 1
        for value in ("10", "1x1", "", "NaN"):
            self.assertIn("harq_decoded_bit_outcome", self.failures([dict(trial, UCIDecodedBitVector=value)], reports))

    def test_pusch_is_not_misbound_to_pucch(self):
        _, reports = self.pair()
        self.assertEqual([], self.failures([], [dict(r, UCITransport="PUSCH") for r in reports]))

    def test_false_dtx_cannot_hide_a_usable_receiver(self):
        trial, reports = self.pair()
        reports[0].update(ReceiverUsable=0, FeedbackOutcome="DTX", ObservedAck=0)
        self.assertIn("harq_receiver_usability_binding", self.failures([trial], reports))

    def test_entrypoint_reads_harq_sidecar(self):
        trial, reports = self.pair()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for relative, rows in (("air_interface/csv/pucch_trials.csv", [trial]),
                                   ("control/csv/gnb_harq_feedback_observations.csv", reports)):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
                    writer.writeheader()
                    writer.writerows(rows)
            receipt = AUDIT.audit_run(root)
        self.assertEqual(2, receipt["Coverage"]["ReceivedHARQ"]["Rows"])
        self.assertEqual("PUCCH_only_PUSCH_not_checked", receipt["HARQBindingScope"])
        self.assertEqual(2, len(receipt["Sources"]))
        harq_checks = [c for c in receipt["Checks"] if c["Check"].startswith("harq_")]
        self.assertTrue(harq_checks)
        self.assertTrue(all(c["Passed"] for c in harq_checks))


if __name__ == "__main__":
    unittest.main()
