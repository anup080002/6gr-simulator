function prach = applyPRACHCfgToObject(prach, cfg, carrier)
%APPLYPRACHCFGTOOBJECT Apply cfg.phy.prach to an nrPRACHConfig object.

duplex = sixgr.util.structGet(cfg, "phy.duplex.mode", "TDD");
try
    prach.DuplexMode = upper(char(string(duplex)));
catch
end

fc = double(sixgr.util.structGet(cfg, "channel.fc_Hz", 3.5e9));
try
    if fc >= 24.25e9
        prach.FrequencyRange = "FR2";
    else
        prach.FrequencyRange = "FR1";
    end
catch
end

cfgIdx = sixgr.util.structGet(cfg, "phy.prach.configurationIndex", []);
if ~isempty(cfgIdx)
    try
        prach.ConfigurationIndex = cfgIdx;
    catch
    end
end

scs = sixgr.util.structGet(cfg, "phy.prach.subcarrierSpacing_kHz", []);
if ~isempty(scs)
    try
        prach.SubcarrierSpacing = scs;
    catch
    end
end

seqIdx = sixgr.util.structGet(cfg, "phy.prach.rootSeqIndex", []);
if isempty(seqIdx)
    seqIdx = sixgr.util.structGet(cfg, "phy.prach.sequenceIndex", []);
end
if ~isempty(seqIdx)
    try
        prach.SequenceIndex = seqIdx;
    catch
    end
end

zcz = sixgr.util.structGet(cfg, "phy.prach.zeroCorrelationZone", []);
if ~isempty(zcz)
    try
        prach.ZeroCorrelationZone = zcz;
    catch
    end
end

freqStart = sixgr.util.structGet(cfg, "phy.prach.frequencyStart", []);
if ~isempty(freqStart)
    try
        prach.FrequencyStart = freqStart;
    catch
    end
end

cfgSlot = sixgr.util.structGet(cfg, "phy.prach.nPrachSlot", []);
if isempty(cfgSlot)
    cfgSlot = sixgr.util.structGet(cfg, "phy.prach.NPRACHSlot", []);
end
if ~isempty(cfgSlot)
    vals = double(cfgSlot(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        try
            prach.NPRACHSlot = vals(1);
        catch
        end
        return;
    end
end

try
    prach.NPRACHSlot = carrier.NSlot;
catch
end
end
