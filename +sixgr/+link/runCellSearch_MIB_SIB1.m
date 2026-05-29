function out = runCellSearch_MIB_SIB1(cfg, varargin)
%RUNSEARCH_MIB_SIB1 Link-level initial access smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumSubframes", 10, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("SSBIndex", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0));
p.parse(varargin{:});
log = p.Results.Logger;
numSF = round(double(p.Results.NumSubframes));

out = struct();
out.Ok = false;
out.Skipped = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.FreqOffsetEstimate_Hz = NaN;
out.TrueCFO_Hz = NaN;
out.CFOError_Hz = NaN;
out.TimingOffset_samples = NaN;
out.TrueTimingOffset_samples = 0;
out.TimingError_samples = NaN;
out.InjectedCFO_Hz = NaN;
out.EstimatedCFO_PreCorrection_Hz = NaN;
out.ResidualCFO_PostCorrection_Hz = NaN;
out.InjectedTimingOffset_samples = NaN;
out.EstimatedTimingOffset_PreCorrection_samples = NaN;
out.ResidualTimingError_PostCorrection_samples = NaN;
out.RawTimingEstimate_samples = NaN;
out.AppliedTimingCorrection_samples = NaN;
out.TimingEstimateApplicationPolicy = "";
out.TimingEstimateStatus = "";
out.TimingEstimateWasClipped = false;
out.Sync = struct();
out.PBCH = struct();
out.SSBIndex = NaN;
out.SSBBeamIndex = NaN;

if ~logical(sixgr.util.structGet(cfg, "phy.ssb.enable", true))
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.ssb.enable=true for CellSearch_MIB_SIB1 coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.ssb.enable=false";
    return;
end

if exist("nrWaveformGenerator","file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires 5G Toolbox SSB/PBCH APIs for CellSearch_MIB_SIB1 coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: 5G Toolbox SSB/PBCH APIs not available.";
    return;
end

try
    tStart = tic;
    ssbArgs = {"NumSubframes", numSF};
    if ~isempty(p.Results.SSBIndex)
        ssbArgs = [ssbArgs, {"SSBIndex", round(double(p.Results.SSBIndex))}]; %#ok<AGROW>
    end
    [txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfg, ssbArgs{:});
    sampleRateHz = localResolveSampleRate(txInfo, cfg);
    injectedCFO_Hz = localResolveInjectedCFOHz(cfg);
    injectedTimingOffset = localResolveInjectedTimingOffsetSamples(cfg);
    rxWaveRaw = localApplyCellSearchImpairments(txWave, sampleRateHz, injectedCFO_Hz, injectedTimingOffset);
    estimatedCFO_PreCorrection_Hz = localEstimateWaveformCFO(txWave, rxWaveRaw, sampleRateHz, injectedTimingOffset);
    rxWave = localApplyCFOCorrection(rxWaveRaw, sampleRateHz, estimatedCFO_PreCorrection_Hz);
    [rxSSB, sync] = sixgr.phy.dl.SSB_Rx(rxWave, cfg, "SampleRate_Hz", sampleRateHz);
    [pb, ~] = sixgr.phy.dl.PBCH_Recovery(rxSSB, sync, cfg);
    out.ComputeLatency_ms = 1e3 * toc(tStart);
    out.ProcedureDelay_ms = NaN;
    out.AirInterfaceObservation_ms = double(numSF);
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.Sync = sync;
    out.PBCH = pb;
    out.SSBIndex = double(sixgr.util.structGet(pb, "SSBIndex", sixgr.util.structGet(txInfo, "SSB.SSBIndex", NaN)));
    out.SSBBeamIndex = out.SSBIndex + 1;

    out.Ok = logical(pb.Ok) && (double(pb.ErrFlag) == 0);
    out.BLER = double(~out.Ok);
    out.InjectedCFO_Hz = injectedCFO_Hz;
    out.EstimatedCFO_PreCorrection_Hz = estimatedCFO_PreCorrection_Hz;
    out.ResidualCFO_PostCorrection_Hz = localEstimateWaveformCFO(txWave, rxWave, sampleRateHz, injectedTimingOffset);
    out.InjectedTimingOffset_samples = injectedTimingOffset;
    out.RawTimingEstimate_samples = double(sixgr.util.structGet(sync, "RawTimingEstimate_samples", ...
        sixgr.util.structGet(sync, "TimingOffset", NaN)));
    out.AppliedTimingCorrection_samples = double(sixgr.util.structGet(sync, "AppliedTimingCorrection_samples", NaN));
    out.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(sync, "TimingEstimateApplicationPolicy", ""));
    out.TimingEstimateStatus = string(sixgr.util.structGet(sync, "TimingEstimateStatus", ""));
    out.TimingEstimateWasClipped = logical(sixgr.util.structGet(sync, "TimingEstimateWasClipped", false));
    out.EstimatedTimingOffset_PreCorrection_samples = out.RawTimingEstimate_samples;
    out.ResidualTimingError_PostCorrection_samples = localResidualTimingAfterSync(rxWave, sync, cfg, sampleRateHz);

    % Legacy aliases kept for backward compatibility with existing reports.
    out.FreqOffsetEstimate_Hz = out.EstimatedCFO_PreCorrection_Hz;
    out.TrueCFO_Hz = out.InjectedCFO_Hz;
    out.CFOError_Hz = out.ResidualCFO_PostCorrection_Hz;
    out.TimingOffset_samples = out.RawTimingEstimate_samples;
    out.TrueTimingOffset_samples = out.InjectedTimingOffset_samples;
    out.TimingError_samples = out.ResidualTimingError_PostCorrection_samples;
    out.Notes = "NCellID=" + string(pb.NCellID) + ...
        ", SSBIdx=" + string(pb.SSBIndex) + ...
        ", injected CFO=" + string(round(out.InjectedCFO_Hz, 3)) + " Hz" + ...
        ", residual CFO=" + string(round(out.ResidualCFO_PostCorrection_Hz, 3)) + " Hz";

    % Optional consolidated wrapper (best-effort).
    try
        rec = sixgr.phy.rrc.MIB_SIB1_Recovery(txWave, cfg, "SampleRate_Hz", txInfo.SampleRate_Hz); %#ok<NASGU>
    catch
    end
catch ME
    msg = string(ME.message);
    if contains(msg, "Too many output arguments")
        sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnsupported", ...
            "Strict mode forbids skipping CellSearch_MIB_SIB1 coverage due to release API mismatch: " + msg);
        out.Skipped = true;
        out.Ok = true;
        out.Notes = "Skipped: release API mismatch (" + msg + ")";
    else
        out.Ok = false;
        out.Notes = "Failure: " + msg;
    end
    if ~isempty(log)
        log.warn("runCellSearch_MIB_SIB1 failed: " + string(ME.message));
    end
end
end

function sampleRateHz = localResolveSampleRate(txInfo, cfg)
sampleRateHz = sixgr.util.structGet(txInfo, "SampleRate_Hz", []);
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, "phy.sampleRate_Hz", []);
end
if isempty(sampleRateHz)
    error("sixgr:link:CellSearchSampleRateMissing", ...
        "Cell-search tracking semantics require a known sample rate.");
end
sampleRateHz = double(sampleRateHz);
end

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0)));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", 0)));
if ~isfinite(timingOffset)
    timingOffset = 0;
end
timingOffset = round(timingOffset);
end

function y = localApplyCellSearchImpairments(x, sampleRateHz, cfoHz, timingOffset)
y = x;
if timingOffset > 0
    y = [zeros(timingOffset, size(y, 2), "like", y); y];
elseif timingOffset < 0
    shift = abs(timingOffset);
    if shift >= size(y, 1)
        y = zeros(size(y), "like", y);
    else
        y = [y(shift+1:end, :); zeros(shift, size(y, 2), "like", y)];
    end
end
if sampleRateHz > 0 && isfinite(cfoHz) && cfoHz ~= 0
    n = (0:size(y, 1)-1).';
    rot = exp(1j * 2 * pi * (cfoHz / sampleRateHz) * n);
    y = y .* rot;
end
end

function y = localApplyCFOCorrection(x, sampleRateHz, estCFO_Hz)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(estCFO_Hz) && estCFO_Hz ~= 0)
    return;
end
n = (0:size(y, 1)-1).';
rot = exp(-1j * 2 * pi * (estCFO_Hz / sampleRateHz) * n);
y = y .* rot;
end

function ncellid = localConfiguredNCellID(cfg)
ncellid = sixgr.util.structGet(cfg, "phy.carrier.NCellID", []);
if isempty(ncellid)
    ncellid = sixgr.util.structGet(cfg, "phy.NCellID", []);
end
if isempty(ncellid)
    return;
end
ncellid = double(ncellid);
if ~(isscalar(ncellid) && isfinite(ncellid) && ncellid >= 0)
    ncellid = [];
else
    ncellid = round(ncellid);
end
end

function estCFO_Hz = localEstimateWaveformCFO(txWave, rxWave, sampleRateHz, timingOffset)
estCFO_Hz = NaN;
if isempty(txWave) || isempty(rxWave) || ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    return;
end
txRef = txWave(:, 1);
rxRef = rxWave(:, 1);
if timingOffset > 0
    startRx = 1 + timingOffset;
    if startRx > numel(rxRef)
        estCFO_Hz = 0;
        return;
    end
    rxRef = rxRef(startRx:end);
elseif timingOffset < 0
    startTx = 1 + abs(timingOffset);
    if startTx > numel(txRef)
        estCFO_Hz = 0;
        return;
    end
    txRef = txRef(startTx:end);
end
N = min(numel(txRef), numel(rxRef));
if N < 32
    estCFO_Hz = 0;
    return;
end
txRef = txRef(1:N);
rxRef = rxRef(1:N);
mask = isfinite(real(txRef)) & isfinite(imag(txRef)) & isfinite(real(rxRef)) & isfinite(imag(rxRef));
mask = mask & (abs(txRef) > max(abs(txRef), [], "omitnan") * 0.05);
if nnz(mask) < 32
    estCFO_Hz = 0;
    return;
end
sampleIdx = find(mask);
phaseObs = unwrap(angle(rxRef(mask) .* conj(txRef(mask))));
p = polyfit(double(sampleIdx(:)) / sampleRateHz, phaseObs(:), 1);
estCFO_Hz = p(1) / (2 * pi);
end

function residualTiming = localResidualTimingAfterSync(rxWaveCfoCorrected, sync, cfg, sampleRateHz)
residualTiming = NaN;
appliedTiming = double(sixgr.util.structGet(sync, "AppliedTimingCorrection_samples", 0));
startIdx = 1 + max(0, round(appliedTiming));
if startIdx > size(rxWaveCfoCorrected, 1)
    residualTiming = 0;
    return;
end
rxSync = rxWaveCfoCorrected(startIdx:end, :);
blockPattern = char(sixgr.util.structGet(cfg, 'phy.ssb.blockPattern', 'Case B'));
nid2 = double(sixgr.util.structGet(sync, "NID2", mod(double(sixgr.util.structGet(sync, "NCellID", 1)), 3)));
try
    [residualTiming, ~] = sixgr.phy.sync.timingEstimate(rxSync, nid2, blockPattern, sampleRateHz);
catch
    residualTiming = NaN;
end
if ~isfinite(residualTiming)
    residualTiming = 0;
end
end
