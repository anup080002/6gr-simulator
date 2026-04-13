function ok = testChannelFactoryCDLAntennaArray()
%TESTCHANNELFACTORYCDLANTENNAARRAY CDL creation must honor requested antenna counts.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "CDL";
cfg.channel.cdlProfile = "CDL-D";
cfg.channel.delayProfile = "CDL-D";
cfg.channel.delaySpread_s = 300e-9;
cfg.channel.doppler_Hz = 30;
cfg.channel.channelFiltering = true;
cfg.channel.fading.profile = "CDL-D";
cfg.channel.fading.model = "CDL-D";
cfg.channel.nTxAnt = 8;
cfg.channel.nRxAnt = 8;
cfg.phy.fc_Hz = 30e9;
cfg.antenna_and_array.bs_array_geometry = "ura";
cfg.antenna_and_array.ue_array_geometry = "ula";
cfg.antenna_and_array.polarization = "single";

ch = sixgr.channel.ChannelFactory.create(cfg, ...
    "Model", "CDL-D", ...
    "SampleRate", 30.72e6, ...
    "NumTxAnt", 8, ...
    "NumRxAnt", 8, ...
    "Fc_Hz", 30e9, ...
    "Seed", 11);

assert(strcmp(string(ch.Type), "nrCDLChannel"), "Expected nrCDLChannel output.");
infoCh = info(ch.Object);
assert(infoCh.NumTransmitAntennas == 8, "CDL channel did not honor the requested Tx antenna count.");
assert(infoCh.NumReceiveAntennas == 8, "CDL channel did not honor the requested Rx antenna count.");

x = complex(randn(256, 8), randn(256, 8));
y = ch.Object(x);
assert(isequal(size(y), [256 8]), "CDL channel output size does not match the requested 8x8 shape.");

ok = true;
end
