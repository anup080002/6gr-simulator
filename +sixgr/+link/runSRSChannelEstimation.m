function out = runSRSChannelEstimation(cfg, varargin)
%RUNSRSCHANNELESTIMATION SRS Tx/Rx channel-estimation smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 20), @(x) isnumeric(x) && isscalar(x));
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
out.NMSE_dB = NaN;

if ~logical(sixgr.util.structGet(cfg, "phy.srs.enable", true))
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.srs.enable=false";
    return;
end

if exist("nrSRS", "file") ~= 2 || exist("nrSRSIndices", "file") ~= 2
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrSRS APIs unavailable.";
    return;
end

try
    [tx, ~] = sixgr.phy.ul.SRS_Tx(cfg);
    rxWave = localAddAwgn(tx.Waveform, snr_dB);
    [rx, ~] = sixgr.phy.ul.SRS_Rx(rxWave, cfg, "Carrier", tx.Carrier, "SRS", tx.SRS);

    if isempty(rx.Hest)
        out.Ok = false;
        out.Notes = "SRS channel estimate is empty.";
        return;
    end

    e = rx.Hest(:) - 1;
    nmse = mean(abs(e).^2) / max(mean(abs(ones(size(e))).^2), eps);
    out.NMSE_dB = 10*log10(max(nmse, eps));
    out.Ok = true;
    out.Notes = "SRS NMSE=" + string(round(out.NMSE_dB,2)) + " dB";
catch ME
    out.Ok = false;
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runSRSChannelEstimation failed: " + string(ME.message));
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
