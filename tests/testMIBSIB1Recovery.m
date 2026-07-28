function ok = testMIBSIB1Recovery()
%TESTMIBSIB1RECOVERY Regression check for waveform SIB1 recovery path.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.phy.sib1.enable = true;
cfg.channel.bandwidth_Hz = 20e6;
cfg.phy.channelBandwidth_Hz = 20e6;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NCellID = 17;
cfg.phy.sib1.payloadStruct = struct("plmn", "00101", "prach", struct("configurationIndex", 16));

[txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", 2);
rec = sixgr.phy.rrc.MIB_SIB1_Recovery(txWave, cfg, "SampleRate_Hz", txInfo.SampleRate_Hz);

assert(isfield(rec, "SIB1") && isstruct(rec.SIB1), "SIB1 result missing");
assert(~logical(rec.SIB1.Ok), "SIB1 must not pass from payloadStruct/default/config shortcuts.");
assert(contains(string(rec.SIB1.Source), "strict") || contains(string(rec.SIB1.Msg), "waveform"), ...
    "SIB1 shortcut removal must disclose strict waveform recovery failure.");
ok = true;
end
