function out = runPRACHDetection(cfg, varargin)
%RUNPRACHDETECTION PRACH Tx/Rx detection KPI case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 12), @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
log = p.Results.Logger;
snr_dB = double(p.Results.SNR_dB);

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
    [tx, ~] = sixgr.phy.ul.PRACH_Tx(cfg);
    if isempty(tx.Waveform)
        sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageInvalidPRACHConfig", ...
            "Strict mode requires a materialized PRACH waveform. Check random_access.configuration_index and PRACH timing/resource settings.");
        out.Skipped = true;
        out.Ok = true;
        out.Notes = "Skipped: PRACH waveform is empty for this configuration.";
        return;
    end
    if isinf(snr_dB) || snr_dB >= 90
        rxWave = tx.Waveform;
    else
        rxWave = localAddAwgn(tx.Waveform, snr_dB);
    end
    tDetect = tic;
    [rx, ~] = sixgr.phy.ul.PRACH_Rx(rxWave, cfg, "Carrier", tx.Carrier, "PRACH", tx.PRACH);
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

    if out.Detected
        out.Ok = true;
        out.BLER = 0;
        out.Notes = "DetectedIdx=" + string(localScalarOrEmpty(rx.PreambleIndex));
    else
        out.Ok = true;
        out.BLER = 1;
        out.Notes = "Not detected: PRACH detect did not trigger for this config.";
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
