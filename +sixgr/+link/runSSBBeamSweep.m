function out = runSSBBeamSweep(cfg, varargin)
%RUNSSBBEAMSWEEP Execute SSB/PBCH/MIB/SIB1 acquisition for each SSB beam.
%
% The rows are produced by real cell-search / PBCH / SIB1 processing, one
% configured SSB index at a time. Missing measurements remain NaN/blank.

p = inputParser;
p.addParameter("SNR_dB", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("NumSubframes", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
p.addParameter("MaxBeams", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
p.addParameter("OutputPath", "", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
opt = p.Results;

beamCount = localResolveSSBBeamCount(cfg);
if ~isempty(opt.MaxBeams)
    beamCount = min(beamCount, max(1, round(double(opt.MaxBeams))));
end

configuredSSB = logical(sixgr.util.structGet(cfg, "phy.ssb.enable", false));
configuredBeamSweep = logical(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.enabled", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "ssb", configuredSSB, ...
    "runSSBBeamSweep.SSB");
sixgr.config.assertRuntimeFeatureUse(cfg, "beam_sweep", configuredBeamSweep, ...
    "runSSBBeamSweep.beam_sweep");
if ~(configuredSSB && configuredBeamSweep) || beamCount < 1
    T = localEmptyTable();
    out = struct("Ok", true, "TrialTable", T, "BeamCount", double(beamCount), ...
        "OutputPath", string(opt.OutputPath));
    return;
end

numSubframes = double(opt.NumSubframes);
if isempty(numSubframes) || ~(isfinite(numSubframes) && numSubframes >= 1)
    numSubframes = localResolvePBCHObservationSubframes(cfg);
end
numSubframes = max(1, round(numSubframes));

snr_dB = double(opt.SNR_dB);
if isempty(snr_dB) || ~(isscalar(snr_dB) && isfinite(snr_dB))
    snr_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", NaN));
end

rows = repmat(localRowTemplate(cfg, snr_dB), beamCount, 1);
for ssbIdx = 0:(beamCount - 1)
    cfgBeam = sixgr.util.structSet(cfg, "phy.ssb.runtimeSSBIndex", double(ssbIdx));
    cfgBeam = sixgr.util.structSet(cfgBeam, "phy.ssb.SSBIndex", double(ssbIdx));
    % SNR_dB is an execution input, not report metadata.  Bind it into the
    % exact resolved configuration consumed by the waveform generator and
    % runtime channel before starting the targeted beam trial.
    cfgBeam = sixgr.util.structSet(cfgBeam, "channel.snr_dB", double(snr_dB));
    % A targeted beam trial transmits exactly the requested SSB index.
    % Override the inherited burst bitmap as trial stimulus; otherwise an
    % explicit master bitmap (for example 10000000) silently keeps every
    % sweep row on beam zero.
    lmax = round(double(sixgr.util.structGet(cfgBeam, "phy.ssb.Lmax", 0)));
    if ~(isscalar(lmax) && isfinite(lmax) && lmax >= beamCount && ssbIdx < lmax)
        error("sixgr:link:InvalidSSBBeamSweep", ...
            "SSB beam %d cannot be materialized for configured Lmax=%g.", ...
            ssbIdx, lmax);
    end
    trialBitmap = false(1, lmax);
    trialBitmap(ssbIdx + 1) = true;
    cfgBeam = sixgr.util.structSet( ...
        cfgBeam, "phy.ssb.activeBitmap", trialBitmap);
    cfgBeam = sixgr.util.structSet( ...
        cfgBeam, "phy.ssb.positionsInBurst", char('0' + trialBitmap));
    row = localRowTemplate(cfgBeam, snr_dB);
    row.SSBIndex = double(ssbIdx);
    row.BeamIndex = double(ssbIdx + 1);
    try
        acq = sixgr.link.runCellSearch_MIB_SIB1(cfgBeam, ...
            "NumSubframes", numSubframes, ...
            "SSBIndex", double(ssbIdx), ...
            "UseRuntimeChannel", true);
        row = localApplyAcquisition(row, acq);
    catch ME
        if logical(sixgr.util.structGet(cfg, "run.strictMode", false))
            rethrow(ME);
        end
        row.Ok = false;
        row.Crash = true;
        row.Status = "CRASH";
        row.FailureReason = string(ME.identifier);
        row.Notes = string(ME.message);
    end
    rows(ssbIdx + 1) = row;
end

T = struct2table(rows, "AsArray", true);
[T, selection] = localSelectMeasuredBeam(T);
outputPath = string(opt.OutputPath);
if strlength(strtrim(outputPath)) > 0
    [folder, ~, ~] = fileparts(char(outputPath));
    if strlength(string(folder)) > 0
        sixgr.util.ensureFolder(folder);
    end
    sixgr.util.csvWriteTable(char(outputPath), T);
end

out = struct();
out.Ok = all(logical(T.Ok) | logical(T.Skipped));
out.TrialTable = T;
out.BeamCount = double(beamCount);
out.SelectedSSBIndex = double(selection.SelectedSSBIndex);
out.SelectedBeamIndex = double(selection.SelectedBeamIndex);
out.SelectionMetric = string(selection.SelectionMetric);
out.SelectionMetricValue_dB = double(selection.SelectionMetricValue_dB);
out.SelectionSource = string(selection.SelectionSource);
out.SelectionStatus = string(selection.SelectionStatus);
out.OutputPath = outputPath;
end

function row = localRowTemplate(cfg, snr_dB)
row = struct();
row.SSBIndex = NaN;
row.BeamIndex = NaN;
row.RecoveredSSBIndex = NaN;
row.SSBIndexMatch = false;
row.BeamManagementProcedure = "P1_SSB_beam_sweep";
row.SNR_dB = double(snr_dB);
row.NCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", NaN));
row.CarrierSCS_kHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", NaN)));
row.SSBSCS_kHz = double(sixgr.util.structGet(cfg, "phy.ssb.scs_kHz", row.CarrierSCS_kHz));
row.SSBBlockPattern = string(sixgr.util.structGet(cfg, "phy.ssb.blockPattern", ""));
row.SSBLmax = double(sixgr.util.structGet(cfg, "phy.ssb.Lmax", NaN));
row.ConfiguredSSBBeamCount = double(localResolveSSBBeamCount(cfg));
row.SSBPeriodicity_ms = double(sixgr.util.structGet(cfg, "phy.ssb.periodicity_ms", ...
    sixgr.util.structGet(cfg, "reference_signals.ssb_periodicity_ms", NaN)));
row.ConfiguredSNR_dB = double(snr_dB);
row.ConfiguredSNRSource = "runSSBBeamSweep.channel.snr_dB";
row.RuntimeChannelStateUsed = false;
row.RuntimeChannelLinkKey = "";
row.RuntimeChannelSeed = NaN;
row.RuntimeChannelStartSample = NaN;
row.RuntimeChannelEndSample = NaN;
row.RuntimeChannelInputWaveformSHA256 = "";
row.RuntimeChannelOutputWaveformSHA256 = "";
row.RuntimeChannelPathGainsSHA256 = "";
row.RuntimeChannelPathGainElementCount = 0;
row.RuntimeChannelPathGainDimensions = "";
row.InjectedNoiseVariance = NaN;
row.SSBBurstConfiguredBeamCount = NaN;
row.SSBBurstExecutedBeamCount = NaN;
row.SSBBurstActiveIndices0Based = "";
row.SSBBurstPrecoderID = "";
row.SSBBurstPrecoderMatrixSHA256 = "";
row.SSBBurstPlanSHA256 = "";
row.SSBWaveformDomain = "";
row.SSBWaveformPorts = NaN;
row.SSBPhysicalTransmitAntennaElements = NaN;
row.SSBTxEvidenceSource = "";
row.ExplicitBeamWeightsApplied = false;
row.BeamformingApplied = false;
row.SelectedBeamFlag = false;
row.SelectedSSBIndex = NaN;
row.SelectedBeamIndex = NaN;
row.SelectionMetric = "";
row.SelectionMetricValue_dB = NaN;
row.SelectionSource = "";
row.SelectionStatus = "not_evaluated";
row.Ok = false;
row.Skipped = false;
row.Crash = false;
    row.BCHCrcPass = false;
    row.MIBDecoded = false;
    row.PSSDetected = false;
    row.SSSDetected = false;
    row.NCellIDRecovered = false;
    row.PSSDetectionSource = "";
    row.SSSDetectionSource = "";
row.SIB1StrictOk = false;
row.SIB1TreeEqual = false;
row.SIB1DCICrcPass = false;
row.SIB1DLSCHCrcPass = false;
row.SIB1ASN1DecodeOk = false;
row.DetectionSuccess = false;
row.DetectionOutcome = "";
row.SSBReceivedPower_dB = NaN;
row.SS_RSRP_dBm = NaN;
row.SS_RSRPPerReceiveAntenna_dBm = "";
row.SS_RSRPRawObserved_dBm = NaN;
row.SS_RSRPRawObservedPerReceiveAntenna_dBm = "";
row.SS_SINR_dB = NaN;
row.SS_SINRPerReceiveAntenna_dB = "";
row.SSMeasurementSource = "";
row.SSSINRMeasurementMethod = "";
row.SSSINRReferencePlane = "";
row.SSSINRNoiseInterferencePowerPerReceiveAntenna_W = "";
row.SSSINRDesiredPowerPerReceiveAntenna_W = "";
row.SSSINRNoiseInterferenceRECount = NaN;
row.SSPhysicalMeasurementStatus = "unavailable";
row.SSSINRFailureReason = "";
row.ReferenceSignalId = NaN;
row.ReferenceSignalTxEPRE_dBm = NaN;
row.ReferenceSignalTxEPREPerAntenna_dBm = "";
row.ReferenceSignalTxMeasurementSource = "";
row.MeasuredReferenceSignalPathloss_dB = NaN;
row.MeasuredReferenceSignalPathlossSource = "";
row.PathlossReferenceRS = "";
row.PowerReferencePlane = "";
row.PBCHDMRSMetric = NaN;
row.PBCHNoiseVar = NaN;
row.PreEqualizationNoiseVariance = NaN;
row.PreEqualizationNoiseVarianceDomain = "";
row.PreEqualizationNoiseVarianceSource = "";
row.ChannelEstimateAvailable = false;
row.ChannelEstimateSource = "";
row.EqualizationAvailable = false;
row.EqualizerType = "";
row.ReceiverHestSINR_dB = NaN;
row.ReceiverHestSINRSource = "";
row.ReceiverHestSINRValueRole = "";
row.ReceiverHestSINRValueStatus = "";
row.ReceiverHestSINRNAReason = "";
row.MeasuredTrialSINR_dB = NaN;
row.MeasuredTrialSINRSource = "";
row.MeasuredTrialSINRValueRole = "";
row.MeasuredTrialSINRValueStatus = "";
row.MeasuredTrialSINRNAReason = "";
row.PostEqSINR_dB = NaN;
row.PostEqSINRAvailable = false;
row.PostEqSINRSource = "";
row.PostEqSINRValueRole = "";
row.PostEqSINRValueStatus = "";
row.PostEqSINRNAReason = "";
row.PostEqualizationNoiseVariance = NaN;
row.PostEqualizationNoiseVarianceDomain = "";
row.PostEqualizationNoiseVarianceSource = "";
row.StrictReceiverEvidenceOk = false;
row.SIB1PDSCHChannelEstimateAvailable = false;
row.SIB1PDSCHEqualizationAvailable = false;
row.SIB1PDSCHReceiverHestSINR_dB = NaN;
row.SIB1PDSCHReceiverHestSINRSource = "";
row.SIB1PDSCHStrictReceiverEvidenceOk = false;
row.TimingOffset_samples = NaN;
row.RawTimingEstimate_samples = NaN;
row.EstimatedTimingOffset_PreCorrection_samples = NaN;
row.AppliedTimingCorrection_samples = NaN;
row.ResidualTimingError_PostCorrection_samples = NaN;
row.TrueTimingOffset_samples = NaN;
row.TimingError_samples = NaN;
row.TimingEstimateStatus = "";
row.TimingEstimateApplicationPolicy = "";
row.TimingEstimateWasClipped = false;
row.FrequencyOffsetHz = NaN;
row.InjectedCFO_Hz = NaN;
row.EstimatedCFO_PreCorrection_Hz = NaN;
row.ResidualCFO_PostCorrection_Hz = NaN;
row.TrueCFO_Hz = NaN;
row.CFOError_Hz = NaN;
row.AirInterfaceObservation_ms = NaN;
row.AcquisitionTime_ms = NaN;
row.ComputeLatency_ms = NaN;
row.Status = "NOT_RUN";
row.FailureReason = "";
row.Notes = "";
end

function row = localApplyAcquisition(row, acq)
pbch = sixgr.util.structGet(acq, "PBCH", struct());
sib1 = sixgr.util.structGet(acq, "SIB1", struct());

row.Ok = logical(sixgr.util.structGet(acq, "Ok", false));
row.Skipped = logical(sixgr.util.structGet(acq, "Skipped", false));
row.NCellID = double(sixgr.util.structGet(pbch, "NCellID", sixgr.util.structGet(acq, "Sync.NCellID", row.NCellID)));
row.RecoveredSSBIndex = double(sixgr.util.structGet(acq, "SSBIndex", NaN));
row.SSBIndexMatch = isfinite(row.RecoveredSSBIndex) && ...
    row.RecoveredSSBIndex == row.SSBIndex;
runtimeReplay = sixgr.util.structGet(acq, "RuntimeChannelReplay", struct());
row.RuntimeChannelStateUsed = logical(sixgr.util.structGet( ...
    acq, "RuntimeChannelStateUsed", false));
row.RuntimeChannelLinkKey = string(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelLinkKey", ""));
row.RuntimeChannelSeed = double(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelSeed", NaN));
row.RuntimeChannelStartSample = double(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelStartSample", NaN));
row.RuntimeChannelEndSample = double(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelEndSample", NaN));
row.RuntimeChannelInputWaveformSHA256 = string(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelInputWaveformSHA256", ""));
row.RuntimeChannelOutputWaveformSHA256 = string(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelOutputWaveformSHA256", ""));
row.RuntimeChannelPathGainsSHA256 = string(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelPathGainsSHA256", ""));
row.RuntimeChannelPathGainElementCount = double(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelPathGainElementCount", 0));
row.RuntimeChannelPathGainDimensions = string(sixgr.util.structGet( ...
    runtimeReplay, "RuntimeChannelPathGainDimensions", ""));
row.InjectedNoiseVariance = double(sixgr.util.structGet( ...
    runtimeReplay, "InjectedNoiseVariance", NaN));
ssbTx = sixgr.util.structGet(acq, "SSBTxEvidence", struct());
row.SSBBurstConfiguredBeamCount = double(sixgr.util.structGet( ...
    ssbTx, "ConfiguredBeamCount", NaN));
row.SSBBurstExecutedBeamCount = double(sixgr.util.structGet( ...
    ssbTx, "ExecutedBeamCount", NaN));
activeIndices = double(sixgr.util.structGet( ...
    ssbTx, "ActiveSSBIndices0Based", []));
activeIndices = activeIndices(isfinite(activeIndices));
row.SSBBurstActiveIndices0Based = strjoin(string(activeIndices), "|");
precoderIDs = string(sixgr.util.structGet(ssbTx, "PrecoderIDs", strings(0, 1)));
precoderHashes = string(sixgr.util.structGet( ...
    ssbTx, "PrecoderMatrixSHA256", strings(0, 1)));
% PrecoderIDs/PrecoderMatrixSHA256 are indexed by the absolute zero-based
% SSB index in the Lmax-sized burst plan, not by the ordinal within the
% active bitmap.  A targeted one-hot trial for SSB 3 therefore consumes
% entry 4 even though it is the first (and only) active row.
precoderOrdinal = round(double(row.SSBIndex)) + 1;
if isfinite(precoderOrdinal) && precoderOrdinal >= 1 && ...
        precoderOrdinal <= numel(precoderIDs)
    row.SSBBurstPrecoderID = precoderIDs(precoderOrdinal);
end
if isfinite(precoderOrdinal) && precoderOrdinal >= 1 && ...
        precoderOrdinal <= numel(precoderHashes)
    row.SSBBurstPrecoderMatrixSHA256 = precoderHashes(precoderOrdinal);
end
row.SSBBurstPlanSHA256 = string(sixgr.util.structGet( ...
    ssbTx, "BurstPlanSHA256", ""));
row.SSBWaveformDomain = string(sixgr.util.structGet( ...
    ssbTx, "WaveformDomain", ""));
row.SSBWaveformPorts = double(sixgr.util.structGet( ...
    ssbTx, "WaveformPorts", NaN));
row.SSBPhysicalTransmitAntennaElements = double(sixgr.util.structGet( ...
    ssbTx, "PhysicalTransmitAntennaElements", NaN));
row.SSBTxEvidenceSource = string(sixgr.util.structGet(ssbTx, "Source", ""));
row.ExplicitBeamWeightsApplied = logical(sixgr.util.structGet( ...
    ssbTx, "ExplicitBeamWeightsApplied", false));
row.BeamformingApplied = logical(sixgr.util.structGet( ...
    ssbTx, "BeamformingApplied", false));
    row.BCHCrcPass = localStructLogical(sib1, "BCHCrcPass", localStructLogical(pbch, "Ok", false));
    row.MIBDecoded = localStructLogical(sib1, "MIBDecoded", row.BCHCrcPass);
    row.PSSDetected = logical(sixgr.util.structGet(acq, "PSSDetected", false));
    row.SSSDetected = logical(sixgr.util.structGet(acq, "SSSDetected", false));
    row.NCellIDRecovered = logical(sixgr.util.structGet(acq, "NCellIDRecovered", false));
    row.PSSDetectionSource = string(sixgr.util.structGet(acq, "PSSDetectionSource", ""));
    row.SSSDetectionSource = string(sixgr.util.structGet(acq, "SSSDetectionSource", ""));
row.SIB1StrictOk = localStructLogical(sib1, "StrictOk", row.Ok);
row.SIB1TreeEqual = localStructLogical(sib1, "SIB1TreeEqual", false);
row.SIB1DCICrcPass = localStructLogical(sib1, "DCICrcPass", false);
row.SIB1DLSCHCrcPass = localStructLogical(sib1, "DLSCHCrcPass", false);
row.SIB1ASN1DecodeOk = localStructLogical(sib1, "SIB1ASN1DecodeOk", false);
row.DetectionSuccess = logical(row.BCHCrcPass) && logical(row.MIBDecoded) && ~logical(row.Skipped);
if row.DetectionSuccess
    row.DetectionOutcome = "ssb_pbch_mib_acquired";
elseif row.Skipped
    row.DetectionOutcome = "skipped";
else
    row.DetectionOutcome = "not_acquired";
end
row.TimingOffset_samples = double(sixgr.util.structGet(acq, "TimingOffset_samples", NaN));
row.SSBReceivedPower_dB = double(sixgr.util.structGet(acq, "SSBReceivedPower_dB", NaN));
row.SS_RSRP_dBm = double(sixgr.util.structGet(acq, "SS_RSRP_dBm", NaN));
row.SS_RSRPPerReceiveAntenna_dBm = string(sixgr.util.structGet( ...
    acq, "SS_RSRPPerReceiveAntenna_dBm", ""));
row.SS_RSRPRawObserved_dBm = double(sixgr.util.structGet( ...
    acq, "SS_RSRPRawObserved_dBm", NaN));
row.SS_RSRPRawObservedPerReceiveAntenna_dBm = string(sixgr.util.structGet( ...
    acq, "SS_RSRPRawObservedPerReceiveAntenna_dBm", ""));
row.SS_SINR_dB = double(sixgr.util.structGet(acq, "SS_SINR_dB", NaN));
row.SS_SINRPerReceiveAntenna_dB = string(sixgr.util.structGet( ...
    acq, "SS_SINRPerReceiveAntenna_dB", ""));
row.SSMeasurementSource = string(sixgr.util.structGet( ...
    acq, "SSMeasurementSource", ""));
row.SSSINRMeasurementMethod = string(sixgr.util.structGet( ...
    acq, "SSSINRMeasurementMethod", ""));
row.SSSINRReferencePlane = string(sixgr.util.structGet( ...
    acq, "SSSINRReferencePlane", ""));
row.SSSINRNoiseInterferencePowerPerReceiveAntenna_W = string( ...
    sixgr.util.structGet(acq, ...
    "SSSINRNoiseInterferencePowerPerReceiveAntenna_W", ""));
row.SSSINRDesiredPowerPerReceiveAntenna_W = string(sixgr.util.structGet( ...
    acq, "SSSINRDesiredPowerPerReceiveAntenna_W", ""));
row.SSSINRNoiseInterferenceRECount = double(sixgr.util.structGet( ...
    acq, "SSSINRNoiseInterferenceRECount", NaN));
row.SSPhysicalMeasurementStatus = string(sixgr.util.structGet( ...
    acq, "SSPhysicalMeasurementStatus", "unavailable"));
row.SSSINRFailureReason = string(sixgr.util.structGet( ...
    acq, "SSSINRFailureReason", ""));
row.ReferenceSignalId = double(sixgr.util.structGet( ...
    acq, "ReferenceSignalId", row.SSBIndex));
row.ReferenceSignalTxEPRE_dBm = double(sixgr.util.structGet( ...
    acq, "ReferenceSignalTxEPRE_dBm", NaN));
row.ReferenceSignalTxEPREPerAntenna_dBm = string(sixgr.util.structGet( ...
    acq, "ReferenceSignalTxEPREPerAntenna_dBm", ""));
row.ReferenceSignalTxMeasurementSource = string(sixgr.util.structGet( ...
    acq, "ReferenceSignalTxMeasurementSource", ""));
row.MeasuredReferenceSignalPathloss_dB = double(sixgr.util.structGet( ...
    acq, "MeasuredReferenceSignalPathloss_dB", NaN));
row.MeasuredReferenceSignalPathlossSource = string(sixgr.util.structGet( ...
    acq, "MeasuredReferenceSignalPathlossSource", ""));
row.PathlossReferenceRS = string(sixgr.util.structGet( ...
    acq, "PathlossReferenceRS", ""));
row.PowerReferencePlane = string(sixgr.util.structGet( ...
    acq, "PowerReferencePlane", ""));
row.PBCHDMRSMetric = double(sixgr.util.structGet(acq, "PBCHDMRSMetric", NaN));
row.PBCHNoiseVar = double(sixgr.util.structGet(acq, "PBCHNoiseVar", NaN));
row.PreEqualizationNoiseVariance = double(sixgr.util.structGet(acq, "PreEqualizationNoiseVariance", NaN));
row.PreEqualizationNoiseVarianceDomain = string(sixgr.util.structGet(acq, "PreEqualizationNoiseVarianceDomain", ""));
row.PreEqualizationNoiseVarianceSource = string(sixgr.util.structGet(acq, "PreEqualizationNoiseVarianceSource", ""));
row.ChannelEstimateAvailable = logical(sixgr.util.structGet(acq, "ChannelEstimateAvailable", false));
row.ChannelEstimateSource = string(sixgr.util.structGet(acq, "ChannelEstimateSource", ""));
row.EqualizationAvailable = logical(sixgr.util.structGet(acq, "EqualizationAvailable", false));
row.EqualizerType = string(sixgr.util.structGet(acq, "EqualizerType", ""));
row.ReceiverHestSINR_dB = double(sixgr.util.structGet(acq, "ReceiverHestSINR_dB", NaN));
row.ReceiverHestSINRSource = string(sixgr.util.structGet(acq, "ReceiverHestSINRSource", ""));
row.ReceiverHestSINRValueRole = string(sixgr.util.structGet(acq, "ReceiverHestSINRValueRole", ""));
row.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(acq, "ReceiverHestSINRValueStatus", ""));
row.ReceiverHestSINRNAReason = string(sixgr.util.structGet(acq, "ReceiverHestSINRNAReason", ""));
row.MeasuredTrialSINR_dB = double(sixgr.util.structGet(acq, "MeasuredTrialSINR_dB", NaN));
row.MeasuredTrialSINRSource = string(sixgr.util.structGet(acq, "MeasuredTrialSINRSource", ""));
row.MeasuredTrialSINRValueRole = string(sixgr.util.structGet(acq, "MeasuredTrialSINRValueRole", ""));
row.MeasuredTrialSINRValueStatus = string(sixgr.util.structGet(acq, "MeasuredTrialSINRValueStatus", ""));
row.MeasuredTrialSINRNAReason = string(sixgr.util.structGet(acq, "MeasuredTrialSINRNAReason", ""));
row.PostEqSINR_dB = double(sixgr.util.structGet(acq, "PostEqSINR_dB", NaN));
row.PostEqSINRAvailable = logical(sixgr.util.structGet(acq, "PostEqSINRAvailable", false));
row.PostEqSINRSource = string(sixgr.util.structGet(acq, "PostEqSINRSource", ""));
row.PostEqSINRValueRole = string(sixgr.util.structGet(acq, "PostEqSINRValueRole", ""));
row.PostEqSINRValueStatus = string(sixgr.util.structGet(acq, "PostEqSINRValueStatus", ""));
row.PostEqSINRNAReason = string(sixgr.util.structGet(acq, "PostEqSINRNAReason", ""));
row.PostEqualizationNoiseVariance = double(sixgr.util.structGet(acq, "PostEqualizationNoiseVariance", NaN));
row.PostEqualizationNoiseVarianceDomain = string(sixgr.util.structGet(acq, "PostEqualizationNoiseVarianceDomain", ""));
row.PostEqualizationNoiseVarianceSource = string(sixgr.util.structGet(acq, "PostEqualizationNoiseVarianceSource", ""));
row.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(acq, "StrictReceiverEvidenceOk", false)) && ...
    row.ChannelEstimateAvailable && row.EqualizationAvailable && ...
    isfinite(row.ReceiverHestSINR_dB) && row.PostEqSINRAvailable && ...
    isfinite(row.PostEqSINR_dB);
row.SIB1PDSCHChannelEstimateAvailable = logical(sixgr.util.structGet(acq, "SIB1PDSCHChannelEstimateAvailable", false));
row.SIB1PDSCHEqualizationAvailable = logical(sixgr.util.structGet(acq, "SIB1PDSCHEqualizationAvailable", false));
row.SIB1PDSCHReceiverHestSINR_dB = double(sixgr.util.structGet(acq, "SIB1PDSCHReceiverHestSINR_dB", NaN));
row.SIB1PDSCHReceiverHestSINRSource = string(sixgr.util.structGet(acq, "SIB1PDSCHReceiverHestSINRSource", ""));
row.SIB1PDSCHStrictReceiverEvidenceOk = logical(sixgr.util.structGet(acq, "SIB1PDSCHStrictReceiverEvidenceOk", false));
row.RawTimingEstimate_samples = double(sixgr.util.structGet(acq, "RawTimingEstimate_samples", NaN));
row.EstimatedTimingOffset_PreCorrection_samples = double(sixgr.util.structGet(acq, "EstimatedTimingOffset_PreCorrection_samples", NaN));
row.AppliedTimingCorrection_samples = double(sixgr.util.structGet(acq, "AppliedTimingCorrection_samples", NaN));
row.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet(acq, "ResidualTimingError_PostCorrection_samples", NaN));
row.TrueTimingOffset_samples = double(sixgr.util.structGet(acq, "TrueTimingOffset_samples", NaN));
row.TimingError_samples = double(sixgr.util.structGet(acq, "TimingError_samples", NaN));
row.TimingEstimateStatus = string(sixgr.util.structGet(acq, "TimingEstimateStatus", ""));
row.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(acq, "TimingEstimateApplicationPolicy", ""));
row.TimingEstimateWasClipped = logical(sixgr.util.structGet(acq, "TimingEstimateWasClipped", false));
row.FrequencyOffsetHz = double(sixgr.util.structGet(acq, "FreqOffsetEstimate_Hz", NaN));
row.InjectedCFO_Hz = double(sixgr.util.structGet(acq, "InjectedCFO_Hz", NaN));
row.EstimatedCFO_PreCorrection_Hz = double(sixgr.util.structGet(acq, "EstimatedCFO_PreCorrection_Hz", NaN));
row.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet(acq, "ResidualCFO_PostCorrection_Hz", NaN));
row.TrueCFO_Hz = double(sixgr.util.structGet(acq, "TrueCFO_Hz", NaN));
row.CFOError_Hz = double(sixgr.util.structGet(acq, "CFOError_Hz", NaN));
row.AirInterfaceObservation_ms = double(sixgr.util.structGet(acq, "AirInterfaceObservation_ms", NaN));
row.AcquisitionTime_ms = double(sixgr.util.structGet(acq, "AcquisitionTime_ms", NaN));
row.ComputeLatency_ms = double(sixgr.util.structGet(acq, "ComputeLatency_ms", NaN));
if row.Ok
    row.Status = "PASS";
else
    row.Status = "FAIL";
end
row.FailureReason = string(sixgr.util.structGet(sib1, "FailureReason", ""));
row.Notes = string(sixgr.util.structGet(acq, "Notes", ""));
end

function [T, selection] = localSelectMeasuredBeam(T)
selection = struct( ...
    "SelectedSSBIndex", NaN, ...
    "SelectedBeamIndex", NaN, ...
    "SelectionMetric", "SS_RSRP_dBm", ...
    "SelectionMetricValue_dB", NaN, ...
    "SelectionSource", ...
        "receiver_measured_targeted_per_beam_ssb_pbch_waveform_trials", ...
    "SelectionStatus", "unavailable_no_successful_finite_measurement");
if ~(istable(T) && ~isempty(T))
    return;
end
measured = double(T.SS_RSRP_dBm);
eligible = logical(T.DetectionSuccess) & isfinite(measured) & ...
    logical(T.ChannelEstimateAvailable) & logical(T.EqualizationAvailable) & ...
    logical(T.StrictReceiverEvidenceOk);
if ~any(eligible)
    T.SelectionMetric(:) = string(selection.SelectionMetric);
    T.SelectionSource(:) = string(selection.SelectionSource);
    T.SelectionStatus(:) = string(selection.SelectionStatus);
    return;
end
eligibleRows = find(eligible);
[bestValue, relativeOrdinal] = max(measured(eligibleRows));
bestRow = eligibleRows(relativeOrdinal);
selection.SelectedSSBIndex = double(T.SSBIndex(bestRow));
selection.SelectedBeamIndex = double(T.BeamIndex(bestRow));
selection.SelectionMetricValue_dB = double(bestValue);
selection.SelectionStatus = "selected_from_successful_receiver_measurements";
T.SelectedBeamFlag(bestRow) = true;
T.SelectedSSBIndex(:) = double(selection.SelectedSSBIndex);
T.SelectedBeamIndex(:) = double(selection.SelectedBeamIndex);
T.SelectionMetric(:) = string(selection.SelectionMetric);
T.SelectionMetricValue_dB(:) = double(selection.SelectionMetricValue_dB);
T.SelectionSource(:) = string(selection.SelectionSource);
T.SelectionStatus(:) = string(selection.SelectionStatus);
end

function beamCount = localResolveSSBBeamCount(cfg)
beamCount = double(sixgr.util.structGet(cfg, "phy.ssb.beamCount", ...
    sixgr.util.structGet(cfg, "phy.ssb.nBeams", ...
    sixgr.util.structGet(cfg, "reference_signals.ssb_beam_count", ...
    sixgr.util.structGet(cfg, "random_access.ssb_beam_count", ...
    sixgr.util.structGet(cfg, "signals_and_channels_common.ssb.beam_count", ...
    sixgr.util.structGet(cfg, "mimo_and_beam_management.ssb_beam_count", ...
    sixgr.util.structGet(cfg, "phy.ssb.Lmax", 1))))))));
if ~(isfinite(beamCount) && beamCount >= 1)
    beamCount = 1;
end
lmax = double(sixgr.util.structGet(cfg, "phy.ssb.Lmax", beamCount));
if isfinite(lmax) && lmax >= 1
    beamCount = min(beamCount, round(lmax));
end
beamCount = max(1, round(double(beamCount)));
end

function numSubframes = localResolvePBCHObservationSubframes(cfg)
numSubframes = double(sixgr.util.structGet(cfg, ...
    "phy.ssb.pbchObservationSubframes", ...
    sixgr.util.structGet(cfg, "lls6g.control.pbchObservationSubframes", NaN)));
if ~(isfinite(numSubframes) && numSubframes >= 1)
    numSubframes = 5;
end
numSubframes = max(1, round(double(numSubframes)));
end

function tf = localStructLogical(s, fieldName, defaultValue)
raw = defaultValue;
if isstruct(s) && isfield(s, fieldName)
    raw = s.(fieldName);
end
if islogical(raw)
    tf = any(raw(:));
elseif isnumeric(raw)
    vals = double(raw(:));
    vals = vals(isfinite(vals));
    tf = ~isempty(vals) && vals(1) ~= 0;
elseif ischar(raw) || isstring(raw)
    token = lower(strtrim(string(raw)));
    tf = any(token == ["1", "true", "yes", "pass", "ok"]);
else
    tf = logical(defaultValue);
end
end

function value = localFiniteOrDefault(candidate, defaultValue)
value = double(defaultValue);
candidate = double(candidate);
if isscalar(candidate) && isfinite(candidate)
    value = candidate;
end
end

function T = localEmptyTable()
T = struct2table(localRowTemplate(struct(), NaN), "AsArray", true);
T = T([], :);
end
