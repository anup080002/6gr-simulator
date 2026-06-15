function ok = testSIB1NoOracleReceiver()
%TESTSIB1NOORACLERECEIVER Receiver must disclose no transmitter oracle use.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 52;
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    ok = true;
    return;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
assert(isempty(rx.UsedOracleFields), "SIB1 receiver must not use tx DCI/PDSCH/SIB1 oracle fields.");
assert(~logical(rx.ProxyUsed) && ~logical(rx.Skipped), "SIB1 receiver must not use proxy/skipped success.");
ok = true;
end
