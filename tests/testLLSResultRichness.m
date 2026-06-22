function ok = testLLSResultRichness()
%TESTLLSRESULTRICHNESS Keep waveform LLS outputs analysis-friendly and non-flat.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml");
scenarioPath = fullfile(tmp, "lls_richness_smoke.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_richness_smoke","description":"richness smoke","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"n_frames":4,"n_slots":4,"monte_carlo_iterations":2,"snr_sweep_offsets_db":[-12,0],"random_seed":17},' ...
    '"channels":{"doppler_hz":30},' ...
    '"reference_signals":{"trs_enabled":true},' ...
    '"impairments":{"cfo_hz":40,"timing_offset_samples":16},' ...
    '"output":{"profile":"lls_richness_smoke","save_figures":true,"save_mat":false}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, "results", "smoke");
assert(out.Ok, "Waveform bundle richness smoke should complete.");

runFolder = char(string(out.RunFolder));
assert(exist(fullfile(runFolder, "fig"), "dir") ~= 7, "Run root must not create a legacy fig folder.");
assert(exist(fullfile(runFolder, "csv"), "dir") ~= 7, "Run root must not create a legacy csv folder.");
assert(exist(fullfile(runFolder, "air_interface", "fig"), "dir") ~= 7, "air_interface must not create a legacy fig folder.");
assert(exist(fullfile(runFolder, "air_interface", "image", "csv"), "dir") ~= 7, "image folder must not recurse into csv.");
assert(exist(fullfile(runFolder, "reports", "image", "fig"), "dir") ~= 7, "report image folder must not recurse into fig.");

dlFile = fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv");
ulFile = fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv");
beamFile = fullfile(runFolder, "beamforming", "csv", "probe_beam_mimo.csv");
beamMgmtFile = fullfile(runFolder, "beamforming", "csv", "probe_beam_management.csv");
dlConstFile = fullfile(runFolder, "air_interface", "csv", "dl_constellation_samples.csv");
ulConstFile = fullfile(runFolder, "air_interface", "csv", "ul_constellation_samples.csv");
pdcchFile = fullfile(runFolder, "air_interface", "csv", "pdcch_trials.csv");
pucchFile = fullfile(runFolder, "air_interface", "csv", "pucch_trials.csv");
srsFile = fullfile(runFolder, "air_interface", "csv", "srs_trials.csv");
trsFile = fullfile(runFolder, "air_interface", "csv", "trs_trials.csv");
cellSearchFile = fullfile(runFolder, "control", "csv", "cell_search_trials.csv");
pbchRecoveryFile = fullfile(runFolder, "control", "csv", "pbch_recovery_trials.csv");
prachCtrlFile = fullfile(runFolder, "control", "csv", "prach_trials.csv");
runtimeModeFile = fullfile(runFolder, "reports", "csv", "runtime_operating_mode.csv");
cqiRefFile = fullfile(runFolder, "reports", "csv", "cqi_table_reference.csv");
mcsRefFile = fullfile(runFolder, "reports", "csv", "mcs_table_reference.csv");
layoutRefFile = fullfile(runFolder, "reports", "csv", "deployment_layout_reference.csv");
assert(exist(dlFile, "file") == 2, "Missing DL trial CSV.");
assert(exist(ulFile, "file") == 2, "Missing UL trial CSV.");
assert(exist(beamFile, "file") == 2, "Missing beamforming diagnostics CSV.");
assert(exist(beamMgmtFile, "file") == 2, "Missing beam-management diagnostics CSV.");
assert(exist(dlConstFile, "file") == 2, "Missing DL constellation CSV.");
assert(exist(ulConstFile, "file") == 2, "Missing UL constellation CSV.");
assert(exist(pdcchFile, "file") == 2, "Missing PDCCH trial CSV.");
assert(exist(pucchFile, "file") == 2, "Missing PUCCH trial CSV.");
assert(exist(srsFile, "file") == 2, "Missing SRS trial CSV.");
assert(exist(trsFile, "file") == 2, "Missing TRS trial CSV.");
assert(exist(cellSearchFile, "file") == 2, "Missing cell-search diagnostics CSV.");
assert(exist(pbchRecoveryFile, "file") == 2, "Missing PBCH-recovery diagnostics CSV.");
assert(exist(prachCtrlFile, "file") == 2, "Missing PRACH control diagnostics CSV.");
assert(exist(runtimeModeFile, "file") == 2, "Missing runtime operating-mode reference CSV.");
assert(exist(cqiRefFile, "file") == 2, "Missing CQI reference CSV.");
assert(exist(mcsRefFile, "file") == 2, "Missing MCS reference CSV.");
assert(exist(layoutRefFile, "file") == 2, "Missing deployment-layout reference CSV.");

dl = readtable(dlFile, "VariableNamingRule", "preserve");
ul = readtable(ulFile, "VariableNamingRule", "preserve");
dlConst = readtable(dlConstFile, "VariableNamingRule", "preserve");
ulConst = readtable(ulConstFile, "VariableNamingRule", "preserve");
beam = readtable(beamFile, "VariableNamingRule", "preserve");
beamMgmt = readtable(beamMgmtFile, "VariableNamingRule", "preserve");
pdcch = readtable(pdcchFile, "VariableNamingRule", "preserve");
pucch = readtable(pucchFile, "VariableNamingRule", "preserve");
srs = readtable(srsFile, "VariableNamingRule", "preserve");
trs = readtable(trsFile, "VariableNamingRule", "preserve");
cellSearch = readtable(cellSearchFile, "VariableNamingRule", "preserve");
pbchRecovery = readtable(pbchRecoveryFile, "VariableNamingRule", "preserve");
prachCtrl = readtable(prachCtrlFile, "VariableNamingRule", "preserve");
runtimeMode = readtable(runtimeModeFile, "VariableNamingRule", "preserve");
cqiRef = readtable(cqiRefFile, "VariableNamingRule", "preserve");
mcsRef = readtable(mcsRefFile, "VariableNamingRule", "preserve");
layoutRef = readtable(layoutRefFile, "VariableNamingRule", "preserve");

assert(ismember("MeasuredSINR_dB", string(dl.Properties.VariableNames)), "DL trials must export measured SINR.");
assert(ismember("MeasuredSINR_dB", string(ul.Properties.VariableNames)), "UL trials must export measured SINR.");
assert(ismember("CRI", string(dl.Properties.VariableNames)), "DL trials must export CRI.");
assert(ismember("CRI", string(ul.Properties.VariableNames)), "UL trials must export CRI.");
assert(ismember("CSIPayloadBitLength", string(dl.Properties.VariableNames)), "DL trials must export CSI payload length.");
assert(all(ismember(["CQIDerivedMCS","CQIDerivedModulation","CQIDerivedTargetCodeRate","LinkAdaptationMode","ActualMCSSelectionMode","CQITable","MCSTable"], ...
    string(dl.Properties.VariableNames))), "DL trials must preserve CQI-derived AMC columns through the waveform bundle.");
assert(ismember("LinkAdaptationScheduled", string(dl.Properties.VariableNames)), "DL trials must export link-adaptation state.");
assert(ismember("Goodput_Mbps", string(dl.Properties.VariableNames)), "DL trials must export goodput.");
assert(ismember("OfferedThroughput_Mbps", string(dl.Properties.VariableNames)), "DL trials must export offered throughput.");
assert(ismember("ComputeLatency_ms", string(dl.Properties.VariableNames)), "DL trials must export compute latency.");
assert(ismember("ProcedureDelay_ms", string(dl.Properties.VariableNames)), "DL trials must export procedure delay.");
assert(ismember("AirInterfaceTTI_ms", string(dl.Properties.VariableNames)), "DL trials must export radio-time TTI.");
assert(all(ismember(["InjectedCFO_Hz","EstimatedCFO_PreCorrection_Hz","ResidualCFO_PostCorrection_Hz", ...
    "EstimatedCFO_Hz","TrueCFO_Hz","CFOError_Hz","InjectedTimingOffset_samples", ...
    "RawTimingEstimate_samples","AppliedTimingCorrection_samples","TimingEstimateApplicationPolicy","TimingEstimateStatus","TimingEstimateWasClipped", ...
    "EstimatedTimingOffset_PreCorrection_samples","ResidualTimingError_PostCorrection_samples", ...
    "TrueTimingOffset_samples","TimingError_samples"], string(dl.Properties.VariableNames))), ...
    "DL trials must export explicit CFO and timing provenance columns.");
assert(ismember("DecodeLatency_ms", string(dl.Properties.VariableNames)), "DL trials must export decode latency.");
assert(ismember("CodeBlockBLER", string(dl.Properties.VariableNames)), "DL trials must export code-block BLER.");
assert(ismember("PAPR_dB", string(dl.Properties.VariableNames)), "DL trials must export PAPR.");
assert(ismember("SymbolErrorRate", string(dl.Properties.VariableNames)), "DL trials must export symbol error rate.");
assert(ismember("ResidualInterferencePower_dB", string(dl.Properties.VariableNames)), "DL trials must export residual interference power.");
assert(ismember("DetectorComplexityUnits_Modulation", string(dl.Properties.VariableNames)), "DL trials must export detector complexity.");
assert(ismember("DataRECount", string(dl.Properties.VariableNames)), "DL trials must export data RE count.");
assert(ismember("DMRSRECount", string(dl.Properties.VariableNames)), "DL trials must export DMRS RE count.");
assert(ismember("PTRSRECount", string(dl.Properties.VariableNames)), "DL trials must export PTRS RE count.");
assert(ismember("RSOverheadFraction", string(dl.Properties.VariableNames)), "DL trials must export RS overhead fraction.");
assert(ismember("LLRImbalance", string(dl.Properties.VariableNames)), "DL trials must export LLR imbalance.");
assert(ismember("EstimatedDopplerHz", string(dl.Properties.VariableNames)), "DL trials must export estimated Doppler.");
assert(ismember("PhaseTrackingError_deg", string(dl.Properties.VariableNames)), "DL trials must export phase-tracking error.");
assert(ismember("QCLAccuracy", string(dl.Properties.VariableNames)), "DL trials must export QCL accuracy.");
assert(ismember("InterpolationLoss_dB", string(dl.Properties.VariableNames)), "DL trials must export interpolation loss.");
assert(ismember("MismatchSensitivity_dB", string(dl.Properties.VariableNames)), "DL trials must export mismatch sensitivity.");
assert(ismember("EarlyStopRate", string(ul.Properties.VariableNames)), "UL trials must export early-stop rate.");
assert(ismember("DecoderComplexityUnits", string(ul.Properties.VariableNames)), "UL trials must export decoder complexity.");
assert(ismember("PAPR_dB", string(ul.Properties.VariableNames)), "UL trials must export PAPR.");
assert(ismember("SymbolErrorRate", string(ul.Properties.VariableNames)), "UL trials must export symbol error rate.");
assert(ismember("ComputeLatency_ms", string(ul.Properties.VariableNames)), "UL trials must export compute latency.");
assert(ismember("ProcedureDelay_ms", string(ul.Properties.VariableNames)), "UL trials must export procedure delay.");
assert(ismember("AirInterfaceTTI_ms", string(ul.Properties.VariableNames)), "UL trials must export radio-time TTI.");
assert(all(ismember(["CQIDerivedMCS","CQIDerivedModulation","CQIDerivedTargetCodeRate","LinkAdaptationMode","ActualMCSSelectionMode","CQITable","MCSTable"], ...
    string(ul.Properties.VariableNames))), "UL trials must preserve CQI-derived AMC columns through the waveform bundle.");
assert(all(ismember(["InjectedCFO_Hz","EstimatedCFO_PreCorrection_Hz","ResidualCFO_PostCorrection_Hz", ...
    "EstimatedCFO_Hz","TrueCFO_Hz","CFOError_Hz","InjectedTimingOffset_samples", ...
    "RawTimingEstimate_samples","AppliedTimingCorrection_samples","TimingEstimateApplicationPolicy","TimingEstimateStatus","TimingEstimateWasClipped", ...
    "EstimatedTimingOffset_PreCorrection_samples","ResidualTimingError_PostCorrection_samples", ...
    "TrueTimingOffset_samples","TimingError_samples"], string(ul.Properties.VariableNames))), ...
    "UL trials must export explicit CFO and timing provenance columns.");
assert(all(ismember(["ReferenceSymbolReal","ReferenceSymbolImag","EqualizedReal","EqualizedImag","HardDecisionReal","HardDecisionImag","DecisionReal","DecisionImag"], string(dlConst.Properties.VariableNames))), ...
    "DL constellation CSV must distinguish reference, equalized, and hard-decision symbols.");
assert(all(ismember(["ReferenceSymbolReal","ReferenceSymbolImag","EqualizedReal","EqualizedImag","HardDecisionReal","HardDecisionImag","DecisionReal","DecisionImag"], string(ulConst.Properties.VariableNames))), ...
    "UL constellation CSV must distinguish reference, equalized, and hard-decision symbols.");
requiredConstellationLineage = ["direction","ue_id","slot","tb_id","layer","modulation","mcs_index","snr_db", ...
    "posteq_sinr_db","symbol_index","reference_symbol_i","reference_symbol_q","equalized_i","equalized_q", ...
    "evm_rms_pct","evm_db","normalization","truth_status"];
assert(all(ismember(requiredConstellationLineage, string(dlConst.Properties.VariableNames))), ...
    "DL constellation CSV must export canonical modulation/layer/SNR lineage columns.");
assert(all(ismember(requiredConstellationLineage, string(ulConst.Properties.VariableNames))), ...
    "UL constellation CSV must export canonical modulation/layer/SNR lineage columns.");
assert(ismember("LLRImbalance", string(ul.Properties.VariableNames)), "UL trials must export LLR imbalance.");
assert(ismember("EstimatedDopplerHz", string(ul.Properties.VariableNames)), "UL trials must export estimated Doppler.");
assert(ismember("PhaseTrackingError_deg", string(ul.Properties.VariableNames)), "UL trials must export phase-tracking error.");
assert(ismember("QCLAccuracy", string(ul.Properties.VariableNames)), "UL trials must export QCL accuracy.");
assert(ismember("InterpolationLoss_dB", string(ul.Properties.VariableNames)), "UL trials must export interpolation loss.");
assert(ismember("MismatchSensitivity_dB", string(ul.Properties.VariableNames)), "UL trials must export mismatch sensitivity.");
assert(ismember("LinkAdaptationApplied", string(ul.Properties.VariableNames)), "UL trials must export link-adaptation applied state.");
assert(ismember("ConfiguredPMI", string(ul.Properties.VariableNames)), "UL trials must export configured PMI.");
assert(ismember("AcquisitionTime_ms", string(ul.Properties.VariableNames)), "UL trials must export acquisition time.");
assert(ismember("TrackingFailureProbability", string(ul.Properties.VariableNames)), "UL trials must export tracking-failure probability.");
assert(localHasVariation(dl.MeasuredSINR_dB), "DL measured SINR should vary across fading trials.");
assert(localHasVariation(ul.MeasuredSINR_dB), "UL measured SINR should vary across fading trials.");
assert(any(isfinite(double(dl.Goodput_Mbps))), "DL trials must contain finite goodput samples.");
assert(any(isfinite(double(dl.ComputeLatency_ms))), "DL trials must contain finite compute-latency samples.");
assert(any(isfinite(double(dl.InjectedCFO_Hz))), "DL trials must contain finite injected CFO samples when CFO impairment is configured.");
assert(any(isfinite(double(dl.EstimatedCFO_PreCorrection_Hz))), "DL trials must contain finite estimated CFO samples when CFO impairment is configured.");
assert(any(isfinite(double(dl.ResidualTimingError_PostCorrection_samples))), "DL trials must contain finite residual timing samples when timing impairment is configured.");
assert(all(~isfinite(double(dl.Latency_ms))), "DL trials must leave the generic latency alias unavailable so wall-clock runtime is not mislabeled as radio latency.");
assert(localAliasMatches(dl, "DecodeLatency_ms", "ComputeLatency_ms"), "DL decode-latency alias must mirror compute latency when populated.");
assert(localAliasMatches(ul, "DecodeLatency_ms", "ComputeLatency_ms"), "UL decode-latency alias must mirror compute latency when populated.");
assert(all(~isfinite(double(ul.Latency_ms))), "UL trials must leave the generic latency alias unavailable so wall-clock runtime is not mislabeled as radio latency.");
assert(any(isfinite(double(ul.ComputeLatency_ms))), "UL trials must contain finite compute-latency samples.");
assert(any(isfinite(double(ul.InjectedCFO_Hz))), "UL trials must contain finite injected CFO samples when CFO impairment is configured.");
assert(any(isfinite(double(ul.EstimatedCFO_PreCorrection_Hz))), "UL trials must contain finite estimated CFO samples when CFO impairment is configured.");
assert(any(isfinite(double(ul.ResidualTimingError_PostCorrection_samples))), "UL trials must contain finite residual timing samples when timing impairment is configured.");
assert(any(isfinite(double(dl.PAPR_dB))), "DL trials must contain finite PAPR samples.");
assert(any(isfinite(double(ul.SymbolErrorRate))), "UL trials must contain finite symbol-error-rate samples.");
assert(any(isfinite(double(ul.EVM_rms)) & double(ul.EVM_rms) > 0), "UL trials must contain nonzero EVM samples from actual equalized-symbol mismatch.");
assert(~isempty(dlConst), "DL constellation samples must not be empty.");
assert(~isempty(ulConst), "UL constellation samples must not be empty.");
assert(all(abs(double(dlConst.DecisionReal) - double(dlConst.HardDecisionReal)) < 1e-12 | ...
    (~isfinite(double(dlConst.DecisionReal)) & ~isfinite(double(dlConst.HardDecisionReal)))), ...
    "DL decision compatibility columns must mirror hard-decision symbols.");
assert(all(abs(double(ulConst.DecisionReal) - double(ulConst.HardDecisionReal)) < 1e-12 | ...
    (~isfinite(double(ulConst.DecisionReal)) & ~isfinite(double(ulConst.HardDecisionReal)))), ...
    "UL decision compatibility columns must mirror hard-decision symbols.");
assert(localHardDecisionAlphabetValid(dlConst), "DL hard-decision symbols must lie on the legal modulation alphabet.");
assert(localHardDecisionAlphabetValid(ulConst), "UL hard-decision symbols must lie on the legal modulation alphabet.");
assert(localPassRowsHaveLowSER(dl), "DL PASS rows at the high-SNR end must show low symbol error rate.");
assert(localPassRowsHaveLowSER(ul), "UL PASS rows at the high-SNR end must show low symbol error rate.");
assert(any(isfinite(double(dl.PhaseTrackingError_deg))), "DL trials must contain finite phase-tracking samples.");
assert(any(isfinite(double(ul.InterpolationLoss_dB))), "UL trials must contain finite interpolation-loss samples.");
assert(ismember("ConditionNumber_dB", string(beam.Properties.VariableNames)), "Beamforming diagnostics must export condition number.");
assert(ismember("MetricKey", string(beamMgmt.Properties.VariableNames)), "Beam-management diagnostics must export metric keys.");
assert(ismember("FalseAlarmFlag", string(pdcch.Properties.VariableNames)), "PDCCH trials must export false-alarm flags.");
assert(ismember("BlockingFlag", string(pdcch.Properties.VariableNames)), "PDCCH trials must export blocking flags.");
assert(ismember("BlindDecodeCount", string(pdcch.Properties.VariableNames)), "PDCCH trials must export blind-decode count.");
assert(ismember("AggregationLevel", string(pdcch.Properties.VariableNames)), "PDCCH trials must export aggregation level.");
assert(ismember("DCISize_bits", string(pdcch.Properties.VariableNames)), "PDCCH trials must export DCI size.");
assert(ismember("NonOverlappedCCEUsage", string(pdcch.Properties.VariableNames)), "PDCCH trials must export non-overlapped CCE usage.");
assert(ismember("ControlCapacityUtilization", string(pdcch.Properties.VariableNames)), "PDCCH trials must export control-capacity utilization.");
assert(ismember("CORESETUtilization", string(pdcch.Properties.VariableNames)), "PDCCH trials must export CORESET utilization.");
assert(ismember("ControlLatency_ms", string(pdcch.Properties.VariableNames)), "PDCCH trials must export control latency.");
assert(ismember("ComputeLatency_ms", string(pdcch.Properties.VariableNames)), "PDCCH trials must export compute latency.");
assert(ismember("AirInterfaceTTI_ms", string(pdcch.Properties.VariableNames)), "PDCCH trials must export radio-time TTI.");
assert(ismember("CRCPass", string(pucch.Properties.VariableNames)), "PUCCH trials must export CRC/pass state.");
assert(ismember("BitsCompared", string(pucch.Properties.VariableNames)), "PUCCH trials must export compared-bit counts.");
assert(ismember("ComputeLatency_ms", string(pucch.Properties.VariableNames)), "PUCCH trials must export compute latency.");
assert(ismember("AirInterfaceTTI_ms", string(pucch.Properties.VariableNames)), "PUCCH trials must export radio-time TTI.");
assert(ismember("NMSE_dB", string(srs.Properties.VariableNames)), "SRS trials must export NMSE.");
assert(ismember("NMSE_dB", string(trs.Properties.VariableNames)), "TRS trials must export NMSE.");
assert(all(ismember(["InjectedCFO_Hz","EstimatedCFO_PreCorrection_Hz","ResidualCFO_PostCorrection_Hz", ...
    "InjectedTimingOffset_samples","EstimatedTimingOffset_PreCorrection_samples","ResidualTimingError_PostCorrection_samples", ...
    "ComputeLatency_ms","ProcedureDelay_ms","AirInterfaceObservation_ms"], ...
    string(cellSearch.Properties.VariableNames))), "Cell-search trials must export explicit pre/post tracking semantics.");
assert(ismember("AcquisitionTime_ms", string(cellSearch.Properties.VariableNames)), "Cell-search trials must export acquisition time.");
assert(ismember("CRCPass", string(cellSearch.Properties.VariableNames)), "Cell-search trials must export pass state.");
assert(all(ismember(["ComputeLatency_ms","ProcedureDelay_ms","AirInterfaceObservation_ms","AcquisitionTime_ms"], ...
    string(pbchRecovery.Properties.VariableNames))), "PBCH-recovery trials must export compute/procedure/observation latency semantics.");
assert(ismember("CRCPass", string(pbchRecovery.Properties.VariableNames)), "PBCH-recovery trials must export pass state.");
assert(all(ismember(["ComputeLatency_ms","ProcedureDelay_ms","AirInterfaceObservation_ms","AcquisitionTime_ms"], ...
    string(prachCtrl.Properties.VariableNames))), "PRACH control trials must export compute/procedure/observation latency semantics.");
assert(ismember("CRCPass", string(prachCtrl.Properties.VariableNames)), "PRACH control trials must export pass state.");
assert(ismember("TrueTimingOffset_samples", string(prachCtrl.Properties.VariableNames)), "PRACH control trials must export true timing offset.");
assert(~isempty(beam), "Beamforming diagnostics must not be empty.");
assert(~isempty(beamMgmt), "Beam-management diagnostics must not be empty.");
assert(~isempty(pucch), "PUCCH diagnostics must not be empty.");
assert(any(isfinite(double(pucch.ComputeLatency_ms))), "PUCCH trials must contain finite compute-latency samples.");
assert(any(isfinite(double(pucch.AirInterfaceTTI_ms))), "PUCCH trials must contain finite radio-time TTI samples.");
assert(all(~isfinite(double(pucch.ProcedureDelay_ms))), "PUCCH trials must leave procedure delay unavailable when no protocol-timeline model exists.");
assert(~isempty(srs), "SRS diagnostics must not be empty.");
assert(~isempty(cellSearch), "Cell-search diagnostics must not be empty.");
assert(~isempty(pbchRecovery), "PBCH-recovery diagnostics must not be empty.");
assert(~isempty(prachCtrl), "PRACH control diagnostics must not be empty.");
assert(any(isfinite(double(dl.ResidualInterferencePower_dB))), "DL trials must contain finite residual-interference samples.");
assert(any(isfinite(double(dl.DetectorComplexityUnits_Modulation))), "DL trials must contain finite detector-complexity samples.");
assert(any(isfinite(double(dl.RSOverheadFraction))), "DL trials must contain finite RS-overhead samples.");
assert(any(isfinite(double(pdcch.BlindDecodeCount))), "PDCCH trials must contain finite blind-decode counts.");
assert(any(isfinite(double(pdcch.ControlLatency_ms))), "PDCCH trials must contain finite control-latency samples.");
assert(any(isfinite(double(pdcch.ComputeLatency_ms))), "PDCCH trials must contain finite compute-latency samples.");
assert(any(isfinite(double(pdcch.AirInterfaceTTI_ms))), "PDCCH trials must contain finite radio-time TTI samples.");
assert(localAliasMatches(pdcch, "ControlLatency_ms", "AirInterfaceTTI_ms"), "PDCCH control latency must mirror radio-time TTI rather than wall-clock compute runtime.");
assert(any(isfinite(double(srs.NMSE_dB))), "SRS trials must contain finite NMSE samples.");
assert(any(isfinite(double(trs.NMSE_dB))), "TRS trials must contain finite NMSE samples.");
assert(any(isfinite(double(cellSearch.AcquisitionTime_ms))), "Cell-search trials must contain finite acquisition-time samples.");
assert(any(isfinite(double(pbchRecovery.AcquisitionTime_ms))), "PBCH-recovery trials must contain finite acquisition-time samples.");
assert(any(isfinite(double(cellSearch.AirInterfaceObservation_ms))), "Cell-search trials must contain finite radio-time observation samples.");
assert(any(isfinite(double(pbchRecovery.AirInterfaceObservation_ms))), "PBCH-recovery trials must contain finite radio-time observation samples.");
assert(any(isfinite(double(prachCtrl.AirInterfaceObservation_ms))), "PRACH control trials must contain finite radio-time observation samples.");
assert(all(ismember(["Direction","ActualMCSSelectionMode","CQITable","MCSTable"], string(runtimeMode.Properties.VariableNames))), ...
    "Runtime operating-mode reference CSV must expose AMC interpretation metadata.");
assert(all(ismember(["Direction","CQITable","CQI","Modulation","TargetCodeRate"], string(cqiRef.Properties.VariableNames))), ...
    "CQI reference CSV must expose NR CQI rows.");
assert(all(ismember(["Direction","MCSTable","MCSIndex","Modulation","TargetCodeRate"], string(mcsRef.Properties.VariableNames))), ...
    "MCS reference CSV must expose NR MCS rows.");
assert(all(ismember(["NumSites","SectorsPerSite","NumCells","InterSiteDistance_m","MobilityEnabled"], string(layoutRef.Properties.VariableNames))), ...
    "Deployment-layout reference CSV must expose topology and mobility knobs.");
assert(localAliasMatches(cellSearch, "AcquisitionTime_ms", "AirInterfaceObservation_ms"), "Cell-search acquisition time must mirror radio-time observation, not compute runtime.");
assert(localAliasMatches(pbchRecovery, "AcquisitionTime_ms", "AirInterfaceObservation_ms"), "PBCH-recovery acquisition time must mirror radio-time observation, not compute runtime.");
assert(localAliasMatches(prachCtrl, "AcquisitionTime_ms", "AirInterfaceObservation_ms"), "PRACH control acquisition time must mirror radio-time observation, not compute runtime.");
assert(all(~isfinite(double(cellSearch.ProcedureDelay_ms))), "Cell-search trials must leave procedure delay unavailable when the LLS path does not model it.");
assert(all(~isfinite(double(pbchRecovery.ProcedureDelay_ms))), "PBCH-recovery trials must leave procedure delay unavailable when the LLS path does not model it.");
assert(all(~isfinite(double(prachCtrl.ProcedureDelay_ms))), "PRACH control trials must leave procedure delay unavailable when the LLS path does not model it.");
assert(localResidualSemanticValid(cellSearch), "Cell-search tracking columns must satisfy the explicit residual semantics.");
assert(localResidualSemanticValid(pbchRecovery), "PBCH-recovery tracking columns must satisfy the explicit residual semantics.");
assert(any(isfinite(double(trs.EstimatedDopplerHz))), "TRS trials must contain finite Doppler estimates.");
assert(localInjectedDopplerConsistency(trs), "TRS Doppler estimates must stay reasonably close to the injected Doppler.");
assert(localTrackingNmseConsistency(srs, trs), "SRS and TRS NMSE normalization must stay in a comparable range.");

pngs = dir(fullfile(runFolder, "air_interface", "image", "*.png"));
assert(~isempty(pngs), "LLS waveform bundle should generate analysis PNGs.");
assert(exist(fullfile(runFolder, "air_interface", "image", "dl_constellation_scatter.png"), "file") == 2, ...
    "DL constellation scatter must be exported.");
assert(exist(fullfile(runFolder, "air_interface", "image", "ul_constellation_scatter.png"), "file") == 2, ...
    "UL constellation scatter must be exported.");

ok = true;
end

function tf = localHasVariation(x)
x = double(x(:));
x = x(isfinite(x));
if numel(x) < 2
    tf = false;
    return;
end
tf = (max(x) - min(x)) > 1e-6;
end

function tf = localAliasMatches(T, aliasName, sourceName)
tf = false;
need = [string(aliasName), string(sourceName)];
if ~(istable(T) && all(ismember(need, string(T.Properties.VariableNames))))
    return;
end
aliasVals = double(T.(aliasName));
sourceVals = double(T.(sourceName));
mask = isfinite(aliasVals) | isfinite(sourceVals);
if ~any(mask)
    tf = true;
    return;
end
tf = all(abs(aliasVals(mask) - sourceVals(mask)) <= 1e-9 | ...
    (~isfinite(aliasVals(mask)) & ~isfinite(sourceVals(mask))));
end

function tf = localPassRowsHaveLowSER(T)
tf = false;
if ~(istable(T) && ~isempty(T) && all(ismember(["Status","SNR_dB","SymbolErrorRate"], string(T.Properties.VariableNames))))
    return;
end
status = upper(strtrim(string(T.Status)));
snr = double(T.SNR_dB);
ser = double(T.SymbolErrorRate);
snr = snr(isfinite(snr));
if isempty(snr)
    return;
end
highCut = max(snr) - 1e-9;
mask = status == "PASS" & isfinite(ser) & isfinite(double(T.SNR_dB)) & double(T.SNR_dB) >= highCut;
if ~any(mask)
    return;
end
tf = median(ser(mask), "omitnan") < 0.25 && any(ser(mask) < 0.1);
end

function tf = localHardDecisionAlphabetValid(T)
tf = false;
need = ["Modulation","HardDecisionReal","HardDecisionImag"];
if ~(istable(T) && ~isempty(T) && all(ismember(need, string(T.Properties.VariableNames))))
    return;
end
modulation = string(T.Modulation);
hardSym = complex(double(T.HardDecisionReal), double(T.HardDecisionImag));
mask = isfinite(real(hardSym)) & isfinite(imag(hardSym)) & strlength(modulation) > 0;
if ~any(mask)
    return;
end
mods = unique(modulation(mask), "stable");
tol = 1e-8;
for i = 1:numel(mods)
    modMask = mask & modulation == mods(i);
    alphabet = localConstellationAlphabet(mods(i));
    if isempty(alphabet)
        tf = false;
        return;
    end
    dist = abs(hardSym(modMask) - reshape(alphabet, 1, []));
    if any(min(dist, [], 2) > tol)
        tf = false;
        return;
    end
end
tf = true;
end

function tf = localResidualSemanticValid(T)
tf = false;
need = ["InjectedCFO_Hz","EstimatedCFO_PreCorrection_Hz","ResidualCFO_PostCorrection_Hz", ...
    "InjectedTimingOffset_samples","EstimatedTimingOffset_PreCorrection_samples","ResidualTimingError_PostCorrection_samples"];
if ~(istable(T) && ~isempty(T) && all(ismember(need, string(T.Properties.VariableNames))))
    return;
end
cfoMask = isfinite(double(T.InjectedCFO_Hz)) & isfinite(double(T.EstimatedCFO_PreCorrection_Hz)) & ...
    isfinite(double(T.ResidualCFO_PostCorrection_Hz));
timingMask = isfinite(double(T.EstimatedTimingOffset_PreCorrection_samples)) & ...
    isfinite(double(T.ResidualTimingError_PostCorrection_samples));
if ~(any(cfoMask) && any(timingMask))
    return;
end
legacyOk = true;
if all(ismember(["TrueCFO_Hz","CFOError_Hz","TrueTimingOffset_samples","TimingError_samples"], string(T.Properties.VariableNames)))
    legacyOk = ...
        all(abs(double(T.TrueCFO_Hz(cfoMask)) - double(T.InjectedCFO_Hz(cfoMask))) < 1e-9) && ...
        all(abs(double(T.CFOError_Hz(cfoMask)) - double(T.ResidualCFO_PostCorrection_Hz(cfoMask))) < 1e-9) && ...
        all(abs(double(T.TrueTimingOffset_samples(timingMask)) - double(T.InjectedTimingOffset_samples(timingMask))) < 1e-9) && ...
        all(abs(double(T.TimingError_samples(timingMask)) - double(T.ResidualTimingError_PostCorrection_samples(timingMask))) < 1e-9);
end
cfoResidual = abs(double(T.ResidualCFO_PostCorrection_Hz(cfoMask)));
cfoPreError = abs(double(T.InjectedCFO_Hz(cfoMask)) - double(T.EstimatedCFO_PreCorrection_Hz(cfoMask)));
timingResidual = abs(double(T.ResidualTimingError_PostCorrection_samples(timingMask)));
timingPre = abs(double(T.EstimatedTimingOffset_PreCorrection_samples(timingMask)));
tf = legacyOk && ...
    median(cfoResidual, "omitnan") <= max(median(cfoPreError, "omitnan"), 1) && ...
    median(timingResidual, "omitnan") < median(timingPre, "omitnan");
end

function tf = localInjectedDopplerConsistency(T)
tf = false;
need = ["InjectedDoppler_Hz","EstimatedDopplerHz"];
if ~(istable(T) && ~isempty(T) && all(ismember(need, string(T.Properties.VariableNames))))
    return;
end
mask = isfinite(double(T.InjectedDoppler_Hz)) & isfinite(double(T.EstimatedDopplerHz));
if ~any(mask)
    if ~any(isfinite(double(T.EstimatedDopplerHz)))
        return;
    end
    channelModel = upper(strtrim(string(localTableColumnOrDefault(T, "ChannelModel", repmat("", height(T), 1)))));
    channelModelApplied = upper(strtrim(string(localTableColumnOrDefault(T, "ChannelModelApplied", repmat("", height(T), 1)))));
    fadingApplied = logical(localTableColumnOrDefault(T, "ChannelFadingApplied", false(height(T), 1)));
    fadingTRS = fadingApplied | startsWith(channelModel, "TDL") | startsWith(channelModel, "CDL") | ...
        startsWith(channelModelApplied, "TDL") | startsWith(channelModelApplied, "CDL");
    tf = any(fadingTRS) && all(~isfinite(double(T.InjectedDoppler_Hz))) && ...
        all(~isfinite(double(T.DopplerError_Hz)));
    return;
end
delta = abs(double(T.EstimatedDopplerHz(mask)) - double(T.InjectedDoppler_Hz(mask)));
tf = median(delta, "omitnan") < 20;
end

function values = localTableColumnOrDefault(T, name, defaultValue)
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    values = T.(char(name));
else
    values = defaultValue;
end
end

function tf = localTrackingNmseConsistency(srs, trs)
tf = false;
if ~(istable(srs) && istable(trs) && ~isempty(srs) && ~isempty(trs))
    return;
end
srsNmse = double(srs.NMSE_dB);
trsNmse = double(trs.NMSE_dB);
srsNmse = srsNmse(isfinite(srsNmse));
trsNmse = trsNmse(isfinite(trsNmse));
if isempty(srsNmse) || isempty(trsNmse)
    return;
end
tf = abs(median(srsNmse, "omitnan") - median(trsNmse, "omitnan")) < 25;
end

function alphabet = localConstellationAlphabet(modulation)
alphabet = [];
token = upper(char(string(modulation)));
switch token
    case 'BPSK'
        alphabet = [-1; 1];
    case 'QPSK'
        alphabet = (1/sqrt(2)) * [1+1j; -1+1j; -1-1j; 1-1j];
    case {'16QAM','64QAM','256QAM','1024QAM','4096QAM'}
        qm = localQm(token);
        M = 2^qm;
        try
            alphabet = qammod((0:M-1).', M, "gray", "UnitAveragePower", true);
        catch
            alphabet = [];
        end
    otherwise
        alphabet = [];
end
end

function qm = localQm(modulation)
switch upper(char(string(modulation)))
    case 'QPSK'
        qm = 2;
    case '16QAM'
        qm = 4;
    case '64QAM'
        qm = 6;
    case '256QAM'
        qm = 8;
    case '1024QAM'
        qm = 10;
    case '4096QAM'
        qm = 12;
    otherwise
        qm = NaN;
end
end
