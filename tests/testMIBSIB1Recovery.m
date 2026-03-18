function ok = testMIBSIB1Recovery()
%TESTMIBSIB1RECOVERY Regression check for SIB1 payload recovery path.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.phy.sib1.enable = true;
cfg.phy.sib1.payloadStruct = struct( ...
    "cellID", double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1)), ...
    "plmn", "00101", ...
    "tac", 42, ...
    "prach", struct("configurationIndex", 16, "subcarrierSpacing_kHz", 1.25, "preambleFormat", "A1", "nPreambles", 64));

[txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", 2);
rec = sixgr.phy.rrc.MIB_SIB1_Recovery(txWave, cfg, "SampleRate_Hz", txInfo.SampleRate_Hz);

assert(isfield(rec, "SIB1") && isstruct(rec.SIB1), "SIB1 result missing");
assert(logical(rec.SIB1.Ok), "SIB1 recovery failed for payloadStruct-backed path");
assert(isfield(rec.SIB1, "Payload") && isstruct(rec.SIB1.Payload), "SIB1 payload missing");
assert(isfield(rec.SIB1.Payload, "plmn"), "SIB1 payload missing PLMN");
assert(isfield(rec.SIB1.Payload, "prach"), "SIB1 payload missing PRACH section");
assert(isfield(rec.SIB1, "CORESET0") && isfield(rec.SIB1, "SearchSpace0"), ...
    "SIB1 scheduling params missing");
ok = true;
end
