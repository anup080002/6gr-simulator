function ok = testSIB1PDCCHNegativeCandidates()
%TESTSIB1PDCCHNEGATIVECANDIDATES Wrong RNTI/no-signal/corrupt PDCCH fail.

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
wrong = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "ReceiverRNTI", 4660, ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
assert(~logical(wrong.StrictOk) && double(wrong.WrongRNTIRejectCount) > 0, "Wrong SI-RNTI attempt must be rejected.");
nosig = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "nosignal", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
assert(~logical(nosig.StrictOk) && double(nosig.NoSignalRejectCount) > 0, "No-signal CORESET must not decode DCI.");
corrupt = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "corruptpdcch", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
assert(~logical(corrupt.StrictOk), "Corrupted PDCCH must not produce strict SIB1 success.");
ok = true;
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
