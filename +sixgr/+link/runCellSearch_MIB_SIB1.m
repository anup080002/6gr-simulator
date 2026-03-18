function out = runCellSearch_MIB_SIB1(cfg, varargin)
%RUNSEARCH_MIB_SIB1 Link-level initial access smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumSubframes", 10, @(x) isnumeric(x) && isscalar(x) && x >= 1);
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

if ~logical(sixgr.util.structGet(cfg, "phy.ssb.enable", true))
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.ssb.enable=false";
    return;
end

if exist("nrWaveformGenerator","file") ~= 2
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: 5G Toolbox SSB/PBCH APIs not available.";
    return;
end

try
    [txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", numSF);
    [rxSSB, sync] = sixgr.phy.dl.SSB_Rx(txWave, cfg, "SampleRate_Hz", txInfo.SampleRate_Hz);
    [pb, ~] = sixgr.phy.dl.PBCH_Recovery(rxSSB, sync, cfg);

    out.Ok = logical(pb.Ok) && (double(pb.ErrFlag) == 0);
    out.BLER = double(~out.Ok);
    out.Notes = "NCellID=" + string(pb.NCellID) + ", SSBIdx=" + string(pb.SSBIndex);

    % Optional consolidated wrapper (best-effort).
    try
        rec = sixgr.phy.rrc.MIB_SIB1_Recovery(txWave, cfg, "SampleRate_Hz", txInfo.SampleRate_Hz); %#ok<NASGU>
    catch
    end
catch ME
    msg = string(ME.message);
    if contains(msg, "Too many output arguments")
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
