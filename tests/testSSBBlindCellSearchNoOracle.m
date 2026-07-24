function ok = testSSBBlindCellSearchNoOracle()
%TESTSSBBLINDCELLSEARCHNOORACLE PCI must come from received PSS/SSS, not cfg.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end

cfgTx = sixgr.config.defaultConfig();
cfgTx.phy.carrier.NCellID = 17;
cfgTx.phy.carrier.SubcarrierSpacing = 30;
cfgTx.phy.carrier.SubcarrierSpacing_kHz = 30;
cfgTx.phy.carrier.NSizeGrid = 273;

[txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfgTx, "NumSubframes", 2);

cfgRx = cfgTx;
cfgRx.phy.carrier.NCellID = 999;
cfgRx.phy.NCellID = 999;

[rxSSBGrid, sync] = sixgr.phy.dl.SSB_Rx(txWave, cfgRx, ...
    "SampleRate_Hz", txInfo.SampleRate_Hz);
assert(double(sync.NID2) == 2, "PSS search must recover NID2=2 for transmitted PCI 17.");
assert(double(sync.NID1) == 5, "SSS search must recover NID1=5 for transmitted PCI 17.");
assert(double(sync.NCellID) == 17, ...
    "SSB_Rx must recover physical cell ID from waveform, not cfg.phy.carrier.NCellID.");
assert(~logical(sync.ConfiguredCellIDUsed), "SSB_Rx must not consume configured cell ID.");
assert(string(sync.NCellIDSource) == "blind_pss_sss_correlation", ...
    "SSB_Rx must report blind PSS/SSS PCI recovery as the cell-ID source.");

[pbch, ~] = sixgr.phy.dl.PBCH_Recovery(rxSSBGrid, sync, cfgRx);
assert(logical(pbch.Ok), "PBCH decode must pass using the blind recovered PCI.");
assert(double(pbch.NCellID) == 17, "PBCH recovery must use the blind recovered PCI.");
ok = true;
end
