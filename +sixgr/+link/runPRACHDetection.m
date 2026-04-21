function out = runPRACHDetection(cfg, varargin)
%RUNPRACHDETECTION PRACH Tx/Rx detection KPI case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 12), @(x) isnumeric(x) && isscalar(x));
p.addParameter("DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0 && x<=1));
p.addParameter("CanonicalSlot", NaN, @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.addParameter("PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.parse(varargin{:});
log = p.Results.Logger;
snr_dB = double(p.Results.SNR_dB);
detectionThreshold = localResolveDetectionThreshold(cfg, p.Results.DetectionThreshold);
canonicalSlot = double(p.Results.CanonicalSlot);
preambleIndex = p.Results.PreambleIndex;
carrierSlot = localResolveCarrierSlot(cfg, canonicalSlot);
if isempty(preambleIndex)
    preambleIndex = sixgr.util.structGet(cfg, "phy.prach.preambleIndex", []);
end

out = struct();
out.Ok = false;
out.Skipped = false;
out.Detected = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.DetectionMetric = NaN;
out.PreambleIndex = [];
out.TimingOffset_samples = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.FalseAlarmFlag = 0;
out.Notes = "";

if ~logical(sixgr.util.structGet(cfg, "phy.prach.enable", true))
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.prach.enable=true for PRACH coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.prach.enable=false";
    return;
end

if exist("nrPRACH","file") ~= 2 || exist("nrPRACHDetect","file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrPRACH/nrPRACHDetect for PRACH coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrPRACH/nrPRACHDetect unavailable.";
    return;
end

try
    [tx, txInfo] = sixgr.phy.ul.PRACH_Tx(cfg, "NPRACHSlot", carrierSlot, "PreambleIndex", preambleIndex);
    activeOccasionPresent = logical(sixgr.util.structGet(txInfo, "ActiveOccasionPresent", ~isempty(tx.Waveform)));
    if isempty(tx.Waveform) || isempty(sixgr.util.structGet(tx, "Symbols", [])) || ~activeOccasionPresent
        out.Skipped = true;
        out.Ok = true;
        out.Notes = "Skipped: no PRACH occasion is active for carrier slot " + string(carrierSlot) + ...
            " with configuration_index=" + string(sixgr.util.structGet(cfg, "phy.prach.configurationIndex", NaN)) + ".";
        return;
    end
    if isinf(snr_dB) || snr_dB >= 90
        rxWave = tx.Waveform;
    else
        rxWave = localAddAwgn(tx.Waveform, snr_dB);
    end
    tDetect = tic;
    rxArgs = {"Carrier", tx.Carrier, "PRACH", tx.PRACH};
    if ~isempty(detectionThreshold)
        rxArgs = [rxArgs {"DetectionThreshold", detectionThreshold}]; %#ok<AGROW>
    end
    if ~isempty(preambleIndex)
        rxArgs = [rxArgs {"PreambleIndex", preambleIndex}]; %#ok<AGROW>
    end
    [rx, ~] = sixgr.phy.ul.PRACH_Rx(rxWave, cfg, rxArgs{:});
    noiseOnlyWave = zeros(size(tx.Waveform), "like", tx.Waveform);
    if ~(isinf(snr_dB) || snr_dB >= 90)
        noiseOnlyWave = localAddAwgn(noiseOnlyWave, snr_dB);
    end
    [rxNoise, ~] = sixgr.phy.ul.PRACH_Rx(noiseOnlyWave, cfg, rxArgs{:});
    out.ComputeLatency_ms = toc(tDetect) * 1e3;
    out.ProcedureDelay_ms = NaN;
    out.AirInterfaceObservation_ms = localWaveformDurationMs(tx, cfg);
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.Detected = logical(rx.Ok);
    out.DetectionMetric = double(out.Detected);
    out.PreambleIndex = rx.PreambleIndex;
    out.TimingOffset_samples = localScalarOrNaN(rx.TimingOffset);
    out.FalseAlarmFlag = double(logical(sixgr.util.structGet(rxNoise, "Ok", false)));

    if out.Detected
        out.Ok = true;
        out.BLER = 0;
        out.Notes = "DetectedIdx=" + string(localScalarOrEmpty(rx.PreambleIndex)) + ...
            "; carrier_slot=" + string(carrierSlot);
    else
        out.Ok = true;
        out.BLER = 1;
        out.Notes = "Not detected: PRACH detect did not trigger for carrier slot " + string(carrierSlot) + ".";
    end
catch ME
    out.Ok = false;
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runPRACHDetection failed: " + string(ME.message));
    end
end
end

function y = localAddAwgn(x, snr_dB)
[y, ~] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function s = localScalarOrEmpty(x)
if isempty(x)
    s = "[]";
    return;
end
if isscalar(x)
    s = string(x);
else
    s = "[" + strjoin(string(x(:).'), ",") + "]";
end
end

function v = localScalarOrNaN(x)
if isempty(x)
    v = NaN;
    return;
end

x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = x(1);
end
end

function durMs = localWaveformDurationMs(tx, cfg)
durMs = NaN;
wave = sixgr.util.structGet(tx, "Waveform", []);
if isempty(wave)
    return;
end
sampleRateHz = sixgr.util.structGet(tx, "SampleRate_Hz", []);
if isempty(sampleRateHz)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            sampleRateHz = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            sampleRateHz = [];
        end
    end
end
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, "phy.sampleRate_Hz", []);
end
sampleRateHz = double(sampleRateHz);
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    return;
end
durMs = 1e3 * (size(wave, 1) / sampleRateHz);
end

function threshold = localResolveDetectionThreshold(cfg, explicitThreshold)
if ~isempty(explicitThreshold)
    threshold = double(explicitThreshold);
    return;
end
threshold = sixgr.util.structGet(cfg, "random_access.detection_threshold", []);
if isempty(threshold)
    threshold = sixgr.util.structGet(cfg, "phy.prach.detectionThreshold", []);
end
if isempty(threshold)
    threshold = [];
else
    threshold = double(threshold);
end
end

function carrierSlot = localResolveCarrierSlot(cfg, canonicalSlot)
if isfinite(canonicalSlot)
    carrierSlot = max(0, round(double(canonicalSlot)) - 1);
    return;
end
configured = sixgr.util.structGet(cfg, "phy.prach.nPrachSlot", []);
if ~isempty(configured) && isfinite(double(configured))
    carrierSlot = max(0, round(double(configured)));
    return;
end
carrierSlot = localFindFirstActiveCarrierSlot(cfg);
end

function carrierSlot = localFindFirstActiveCarrierSlot(cfg)
persistent slotCache
if isempty(slotCache)
    slotCache = containers.Map('KeyType', 'char', 'ValueType', 'double');
end
key = sprintf('%g|%g|%g|%g', ...
    double(sixgr.util.structGet(cfg, 'phy.prach.configurationIndex', NaN)), ...
    double(sixgr.util.structGet(cfg, 'phy.prach.subcarrierSpacing_kHz', NaN)), ...
    double(sixgr.util.structGet(cfg, 'phy.carrier.NSizeGrid', NaN)), ...
    double(sixgr.util.structGet(cfg, 'channel.fc_Hz', NaN)));
if isKey(slotCache, key)
    carrierSlot = double(slotCache(key));
    return;
end
scanSlots = max(40, round(double(sixgr.util.structGet(cfg, 'run.totalSlots', ...
    sixgr.util.structGet(cfg, 'simulation.n_slots', sixgr.util.structGet(cfg, 'phy.numerology.slotsPerFrame', 20) * 2)))));
carrierSlot = 0;
for slotCandidate = 0:max(0, scanSlots - 1)
    try
        [tx, info] = sixgr.phy.ul.PRACH_Tx(cfg, 'NPRACHSlot', slotCandidate);
        activeOccasionPresent = logical(sixgr.util.structGet(info, 'ActiveOccasionPresent', ~isempty(sixgr.util.structGet(tx, 'Waveform', []))));
        if activeOccasionPresent && ~isempty(sixgr.util.structGet(tx, 'Waveform', []))
            carrierSlot = double(slotCandidate);
            slotCache(key) = carrierSlot;
            return;
        end
    catch
    end
end
slotCache(key) = carrierSlot;
end
