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
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;
cfg.initial_access.type0 = struct("monitoring_occasion_ordinal",2);
cfg.initial_access.sib1.pdsch = struct("prb_start",0, ...
    "num_prb",24,"symbol_start",2,"num_symbols",12,"mcs",0,"rv",0);
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    ok = true;
    return;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg);
expectedStartSample = round(double(tx.SIB1AbsoluteSlot) * ...
    (1e-3 / double(tx.Carrier.SlotsPerSubframe)) * ...
    double(tx.SampleRateHz));
assert(double(tx.SIB1AbsoluteSlot) == double(rx.SIB1AbsoluteSlot) && ...
    double(rx.Type0MonitoringOccasionOrdinal) == 2, ...
    "TX and no-oracle RX must independently resolve the configured Type-0 occasion.");
assert(double(tx.SIB1WaveformStartSample) == expectedStartSample && ...
    size(tx.SSBWaveform, 1) < expectedStartSample, ...
    "SIB1 must use the absolute Type-0 slot timeline, not an appended synthetic gap.");
assert(isempty(rx.UsedOracleFields), "SIB1 receiver must not use tx DCI/PDSCH/SIB1 oracle fields.");
assert(~logical(rx.ProxyUsed) && ~logical(rx.Skipped), "SIB1 receiver must not use proxy/skipped success.");
assert(logical(rx.StrictOk) && logical(rx.SIB1SemanticValid), ...
    "No-oracle SIB1 receiver must pass from waveform and decoded semantics alone.");
ok = true;
end
