function ok = testSIB1WaveformRecoveryAWGN()
%TESTSIB1WAVEFORMRECOVERYAWGN Positive waveform SIB1 path must pass.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
cfg = localCfg();
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    localAssertSIRNTIUnsupported(cfg);
    ok = true;
    return;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
assert(logical(rx.StrictOk), "Strict SIB1 waveform recovery must pass at high SNR.");
assert(logical(rx.DCIBlindDecodeSuccess) && double(rx.DCIRNTI) == 65535, "SI-RNTI DCI must decode.");
assert(logical(rx.SIB1TreeEqual), "Decoded SIB1 tree must equal transmitted tree after decode.");
assert(isempty(rx.UsedOracleFields), "Receiver must not consume transmitter oracle fields before decode.");
ok = true;
end

function localAssertSIRNTIUnsupported(cfg)
threw = false;
try
    sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:phy:broadcast:SIRNTIUnsupported");
end
assert(threw, "Current build must fail closed when SI-RNTI waveform support is unavailable.");
end

function cfg = localCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 52;
cfg.phy.sib1.coreset0Index = 0;
cfg.phy.sib1.searchSpaceZero = 0;
end
