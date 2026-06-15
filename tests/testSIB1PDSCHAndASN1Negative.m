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
pdsch = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "corruptpdsch", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
assert(~logical(pdsch.StrictOk), "Corrupted SIB1 PDSCH must fail strict.");
asn1 = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "corruptasn1", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
assert(~logical(asn1.StrictOk), "Corrupted decoded SIB1 payload must fail ASN.1/tree strict gate.");
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
