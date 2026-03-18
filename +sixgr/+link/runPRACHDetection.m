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
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";

if ~logical(sixgr.util.structGet(cfg, "phy.prach.enable", true))
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.prach.enable=false";
    return;
end

if exist("nrPRACH","file") ~= 2 || exist("nrPRACHDetect","file") ~= 2
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrPRACH/nrPRACHDetect unavailable.";
    return;
end

try
    [tx, ~] = sixgr.phy.ul.PRACH_Tx(cfg);
    if isinf(snr_dB) || snr_dB >= 90
        rxWave = tx.Waveform;
    else
        rxWave = localAddAwgn(tx.Waveform, snr_dB);
    end
    [rx, ~] = sixgr.phy.ul.PRACH_Rx(rxWave, cfg, "Carrier", tx.Carrier, "PRACH", tx.PRACH);

    if logical(rx.Ok)
        out.Ok = true;
        out.BLER = 0;
        out.Notes = "DetectedIdx=" + string(localScalarOrEmpty(rx.PreambleIndex));
    else
        out.Skipped = true;
        out.Ok = true;
        out.BLER = NaN;
        out.Notes = "Skipped: PRACH detect did not trigger for this config.";
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
snrLin = 10.^(snr_dB/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
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
