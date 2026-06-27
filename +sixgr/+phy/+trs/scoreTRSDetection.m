function score = scoreTRSDetection(cfg, rx, det, timing, freq, ch, tracking, varargin)
%SCORETRSDETECTION Build strict TRS trial score and row.

p = inputParser;
addParameter(p, "TrialId", 1, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "TrialType", "positive_awgn", @(x) ischar(x) || isstring(x));
addParameter(p, "NegativeExpected", false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

negativeExpected = logical(opt.NegativeExpected);
detectionOk = logical(det.DetectionSuccess);
timingOk = logical(timing.Attempted) && logical(timing.EstimateAvailable) && ...
    isfinite(double(timing.TimingError_samples)) && abs(double(timing.TimingError_samples)) <= double(cfg.TimingToleranceSamples);
freqOk = logical(freq.Attempted) && logical(freq.EstimateAvailable) && ...
    isfinite(double(freq.FrequencyError_Hz)) && abs(double(freq.FrequencyError_Hz)) <= double(cfg.FrequencyToleranceHz);
channelOk = logical(ch.Attempted) && logical(ch.EstimateAvailable) && ...
    isfinite(double(ch.MeanNMSE_dB)) && double(ch.MeanNMSE_dB) <= double(cfg.ChannelNMSEThresholddB);
positiveStrictOk = detectionOk && timingOk && freqOk && channelOk && logical(tracking.StrictOk);
strictOk = positiveStrictOk && ~negativeExpected;
negativeOk = negativeExpected && ~positiveStrictOk;
failure = "";
if ~strictOk && ~negativeOk
    missing = strings(0, 1);
    if ~detectionOk, missing(end+1, 1) = "detection"; end %#ok<AGROW>
    if ~timingOk, missing(end+1, 1) = "timing"; end %#ok<AGROW>
    if ~freqOk, missing(end+1, 1) = "frequency"; end %#ok<AGROW>
    if ~channelOk, missing(end+1, 1) = "channel"; end %#ok<AGROW>
    failure = "trs_strict_components_incomplete:" + strjoin(missing, "|");
end

row = localTrialRow();
row.RunId = string(cfg.RunId);
row.ScenarioName = string(cfg.ScenarioName);
row.TrialId = double(opt.TrialId);
row.TrialType = string(opt.TrialType);
row.CellId = double(cfg.CellId);
row.UEId = double(cfg.UEId);
row.ConfigHash = string(cfg.ConfigHash);
row.Frame = double(cfg.FrameNumber);
row.Slot = double(cfg.SlotNumbers(end));
row.CSIRSRowNumber = double(cfg.RowNumber);
row.NumCSIRSPorts = double(cfg.NumCSIRSPorts);
row.DetectionAttempted = logical(det.DetectionAttempted);
row.DetectionSuccess = logical(det.DetectionSuccess);
row.DetectionMetric = double(det.MeanDetectionMetric);
row.ResourceCoverageRatio = double(det.MinCoverageRatio);
row.TimingTrackingAttempted = logical(timing.Attempted);
row.TRSTimingEstimateAvailable = logical(timing.EstimateAvailable);
row.EstimatedTimingOffset_samples = double(timing.EstimatedTimingOffset_samples);
row.InjectedTimingOffset_samples = double(rx.InjectedTimingOffset_samples);
row.TimingError_samples = double(timing.TimingError_samples);
row.FrequencyTrackingAttempted = logical(freq.Attempted);
row.TRSCFOEstimateAvailable = logical(freq.EstimateAvailable);
row.EstimatedCFO_Hz = double(freq.EstimatedCFO_Hz);
row.EstimatedCFO_PreCorrection_Hz = double(freq.EstimatedCFO_Hz);
row.EstimatedOscillatorCFO_Hz = double(freq.EstimatedCFO_Hz);
row.EstimatedCommonFrequency_Hz = double(sixgr.util.structGet(freq, "EstimatedCommonFrequency_Hz", NaN));
row.PhysicalDoppler_Hz = double(sixgr.util.structGet(freq, "PhysicalDoppler_Hz", NaN));
row.InjectedCFO_Hz = double(rx.InjectedCFO_Hz);
row.FrequencyError_Hz = double(freq.FrequencyError_Hz);
row.ChannelEstimationAttempted = logical(ch.Attempted);
row.TRSChannelEstimateAvailable = logical(ch.EstimateAvailable);
row.NMSE_dB = double(ch.MeanNMSE_dB);
row.PhaseTrackingError_deg = NaN;
row.QCLAccuracy = double(max(0, min(1, det.MeanDetectionMetric)));
row.AppliedAWGNSNR_dB = double(rx.AppliedAWGNSNR_dB);
row.NoiseVariance = double(rx.NoiseVariance);
row.ChannelModel = string(cfg.ChannelModel);
row.ProxyUsed = false;
row.Skipped = false;
row.ToolboxMissing = false;
row.UsedOracleFields = "";
row.TrackingEstimateSource = "trs_nzp_csirs_waveform_estimator";
row.StrictOk = logical(strictOk);
row.NegativeExpectedOk = logical(negativeOk);
row.Status = string(sixgr.phy.trs.localTernary(strictOk, "PASS", "FAIL"));
row.FailureReason = string(failure);
row.TruthStatus = "real_lls_evidence";

score = struct();
score.StrictOk = logical(strictOk);
score.NegativeExpectedOk = logical(negativeOk);
score.PositiveComponentsOk = logical(positiveStrictOk);
score.FailureReason = string(failure);
score.TrialRow = row;
end

function row = localTrialRow()
row = struct("RunId", "", "ScenarioName", "", "TrialId", NaN, "TrialType", "", ...
    "CellId", NaN, "UEId", NaN, "ConfigHash", "", "Frame", NaN, "Slot", NaN, ...
    "CSIRSRowNumber", NaN, "NumCSIRSPorts", NaN, ...
    "DetectionAttempted", false, "DetectionSuccess", false, "DetectionMetric", NaN, ...
    "ResourceCoverageRatio", NaN, "TimingTrackingAttempted", false, ...
    "TRSTimingEstimateAvailable", false, "EstimatedTimingOffset_samples", NaN, ...
    "InjectedTimingOffset_samples", NaN, "TimingError_samples", NaN, ...
    "FrequencyTrackingAttempted", false, "TRSCFOEstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "EstimatedOscillatorCFO_Hz", NaN, "EstimatedCommonFrequency_Hz", NaN, ...
    "PhysicalDoppler_Hz", NaN, ...
    "InjectedCFO_Hz", NaN, "FrequencyError_Hz", NaN, ...
    "ChannelEstimationAttempted", false, "TRSChannelEstimateAvailable", false, ...
    "NMSE_dB", NaN, "PhaseTrackingError_deg", NaN, "QCLAccuracy", NaN, ...
    "AppliedAWGNSNR_dB", NaN, "NoiseVariance", NaN, "ChannelModel", "", ...
    "ProxyUsed", false, "Skipped", false, "ToolboxMissing", false, ...
    "UsedOracleFields", "", "TrackingEstimateSource", "", "StrictOk", false, ...
    "NegativeExpectedOk", false, "Status", "", "FailureReason", "", "TruthStatus", "");
end
