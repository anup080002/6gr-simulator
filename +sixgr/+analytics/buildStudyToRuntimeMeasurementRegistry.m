function T = buildStudyToRuntimeMeasurementRegistry()
%BUILDSTUDYTORUNTIMEMEASUREMENTREGISTRY Separate study vectors from truth.
%
% The study suites define useful questions, figure contracts, and negative
% cases.  They are never runtime data authorities.  Each row below binds a
% study measurement family to the canonical production evidence that may
% answer that question after an actual waveform run.  Absence of the source
% artifact means unavailable evidence; configured values or study vectors
% must not be substituted.

StudyNamespace = [
    "sixgr.phy.ia.c0.campaigns"
    "sixgr.rach.tdoc10512"
    "sixgr.phy.pdcch.tdoc"
    "sixgr.csi"
    "sixgr.tdoc.ul10523"
    "sixgr.tdoc.ul10523"];
MeasurementFamily = [
    "ssb_pbch_mib_sib1_initial_access"
    "prach_detection_false_alarm_timing_advance"
    "pdcch_coreset_search_space_dci_decode"
    "csi_rs_srs_cqi_ri_pmi_beam_channel_measurement"
    "pusch_pucch_srs_harq_uplink_reliability"
    "uplink_throughput_goodput_spectral_efficiency"];
CanonicalRuntimeProducer = [
    "sixgr.truth.exportControlPlaneTraces"
    "sixgr.truth.exportControlPlaneTraces"
    "sixgr.truth.exportControlPlaneTraces"
    "sixgr.truth.exportLLSOutputCoverageArtifacts"
    "sixgr.truth.exportSystemLevelCanonicalArtifacts"
    "sixgr.truth.exportLLSReportingBundle"];
RequiredMeasuredArtifact = [
    "air_interface/csv/pbch_trials.csv|control/csv/initial_access_procedure_trace.csv"
    "air_interface/csv/prach_trials.csv"
    "air_interface/csv/pdcch_trials.csv"
    "air_interface/csv/csi_rs_trials.csv|air_interface/csv/srs_trials.csv|reports/csv/live_beam_measurement_trace.csv"
    "air_interface/csv/ul_pusch_trials.csv|air_interface/csv/pucch_trials.csv|air_interface/csv/srs_trials.csv"
    "air_interface/csv/ul_pusch_trials.csv|reports/csv/fixed_snr_sweep_curve_summary.csv"];
RuntimeFieldSet = [
    "PSSMetric|SSSMetric|SSSMetricMargin|PBCHDMRSMetric|PSSSearchSamples|PSSTimingLagsEvaluated|PSSSequences|PSSCorrelationVectors|SSSSequenceHypotheses|PBCHDMRSHypothesesTested|CFOError_Hz|TimingError_samples|BCHCrcPass|MIBDecoded"
    "DetectionMetric|DetectionSuccess|MissedDetection|FalseAlarm|TimingOffset_samples|TimingAdvance_samples|TimingAdvance_us|PRACHDetectedPreambleIndex|PRACHExpectedPreambleIndex"
    "PDCCHCandidateSINRVector_dB|PDCCHCandidatesAttempted|PDCCHSelectedAggregationLevel|PDCCHSelectedCCEIndex|DCICrcPass|PDCCHPayloadMatch|PDCCHCausalGrantDecodeOk"
    "CQI|RI|PMI|CRI|MeasurementRSRP_dB|SINR_dB|PilotResidualNMSE_dB|HestDimensions|HestRxPorts|HestTxPorts|SelectedBeamIndex|BestBeamIndex|BeamGainGap_dB"
    "CRCPass|BitErrors|BitsCompared|PostEqSINR_dB|ReceiverHestSINR_dB|HARQRound|RV|Goodput_Mbps"
    "OfferedBits|GoodBits|Throughput_Mbps|Goodput_Mbps|BLER|BER|AllocatedPRBCount|NumLayers|Modulation|TargetCodeRate"];
RuntimePromotionPolicy = repmat( ...
    "measured_runtime_rows_only_no_study_vector_substitution", ...
    numel(StudyNamespace), 1);
MissingEvidencePolicy = repmat( ...
    "leave_unavailable_or_fail_required_gate", numel(StudyNamespace), 1);
StudyInputMaySupplyRuntimeDefaults = false(numel(StudyNamespace), 1);
T = table(StudyNamespace, MeasurementFamily, CanonicalRuntimeProducer, ...
    RequiredMeasuredArtifact, RuntimeFieldSet, RuntimePromotionPolicy, ...
    MissingEvidencePolicy, StudyInputMaySupplyRuntimeDefaults);
end
