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

if ~logical(sixgr.util.structGet(cfg, "phy.ssb.enable", true)) || beamCount < 1
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
    row = localRowTemplate(cfgBeam, snr_dB);
    row.SSBIndex = double(ssbIdx);
    row.BeamIndex = double(ssbIdx + 1);
    try
        acq = sixgr.link.runCellSearch_MIB_SIB1(cfgBeam, ...
            "NumSubframes", numSubframes, ...
            "SSBIndex", double(ssbIdx));
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
out.OutputPath = outputPath;
end

function row = localRowTemplate(cfg, snr_dB)
row = struct();
row.SSBIndex = NaN;
row.BeamIndex = NaN;
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
row.Ok = false;
row.Skipped = false;
row.Crash = false;
row.BCHCrcPass = false;
row.MIBDecoded = false;
row.SIB1StrictOk = false;
row.SIB1TreeEqual = false;
row.SIB1DCICrcPass = false;
row.SIB1DLSCHCrcPass = false;
row.SIB1ASN1DecodeOk = false;
row.DetectionSuccess = false;
row.DetectionOutcome = "";
row.SSBReceivedPower_dB = NaN;
row.PBCHDMRSMetric = NaN;
row.PBCHNoiseVar = NaN;
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
row.PostEqSINRSource = "";
row.PostEqSINRValueRole = "";
row.PostEqSINRValueStatus = "";
row.PostEqSINRNAReason = "";
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
row.SSBIndex = double(sixgr.util.structGet(acq, "SSBIndex", row.SSBIndex));
row.BeamIndex = double(sixgr.util.structGet(acq, "SSBBeamIndex", row.SSBIndex + 1));
row.BCHCrcPass = localStructLogical(sib1, "BCHCrcPass", localStructLogical(pbch, "Ok", false));
row.MIBDecoded = localStructLogical(sib1, "MIBDecoded", row.BCHCrcPass);
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
row.PBCHDMRSMetric = double(sixgr.util.structGet(acq, "PBCHDMRSMetric", NaN));
row.PBCHNoiseVar = double(sixgr.util.structGet(acq, "PBCHNoiseVar", NaN));
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
row.PostEqSINRSource = string(sixgr.util.structGet(acq, "PostEqSINRSource", ""));
row.PostEqSINRValueRole = string(sixgr.util.structGet(acq, "PostEqSINRValueRole", ""));
row.PostEqSINRValueStatus = string(sixgr.util.structGet(acq, "PostEqSINRValueStatus", ""));
row.PostEqSINRNAReason = string(sixgr.util.structGet(acq, "PostEqSINRNAReason", ""));
row.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(acq, "StrictReceiverEvidenceOk", false)) && ...
    row.ChannelEstimateAvailable && row.EqualizationAvailable && isfinite(row.ReceiverHestSINR_dB);
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

function T = localEmptyTable()
T = struct2table(localRowTemplate(struct(), NaN), "AsArray", true);
T = T([], :);
end
