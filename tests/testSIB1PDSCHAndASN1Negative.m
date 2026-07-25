function ok = testSIB1PDSCHAndASN1Negative()
%TESTSIB1PDSCHANDASN1NEGATIVE Corrupted PDSCH/ASN.1 cannot pass strict.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
cfg = localCfg();
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    ok = true;
    return;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
pdsch = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "corruptpdsch");
assert(~logical(pdsch.StrictOk), "Corrupted SIB1 PDSCH must fail strict.");
asn1 = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "corruptasn1");
assert(~logical(asn1.StrictOk), "Corrupted decoded SIB1 payload must fail ASN.1/tree strict gate.");

missing = cfg;
missing.initial_access.sib1 = rmfield( ...
    missing.initial_access.sib1, "pdsch");
localVerifyError(@() sixgr.phy.broadcast. ...
    generateSSB_MIB_SIB1_Waveform(missing), ...
    "sixgr:phy:broadcast:MissingSIB1Allocation");
small = cfg;
small.initial_access.sib1.pdsch.num_prb = 1;
localVerifyError(@() sixgr.phy.broadcast. ...
    generateSSB_MIB_SIB1_Waveform(small), ...
    "sixgr:phy:broadcast:SIB1AllocationTooSmall");
ok = true;
end

function cfg = localCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;
cfg.initial_access.type0 = struct("monitoring_occasion_ordinal",2);
cfg.initial_access.sib1.pdsch = struct("prb_start",0, ...
    "num_prb",24,"symbol_start",2,"num_symbols",12,"mcs",0,"rv",0);
cfg.phy.sib1.coreset0Index = 0;
cfg.phy.sib1.searchSpaceZero = 0;
end

function localVerifyError(action, expected)
observed = "";
try
    action();
catch ME
    observed = string(ME.identifier);
end
assert(observed == string(expected), ...
    "Expected typed error %s, observed %s.", expected, observed);
end
