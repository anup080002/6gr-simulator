function ok = testFourStepRAPreservesConcreteChannelModel()
%TESTFOURSTEPRAPRESERVESCONCRETECHANNELMODEL RA PRACH config must not force AWGN.
cfg = raStrictAnchorConfig();
cfg.channel.model = "TDL";
cfg.channel.awgnOnly = false;
cfg.channel.tdlProfile = "TDL-C";
raCfg = sixgr.mac.ra.RAConfig(cfg, "RunId", "test_ra_tdlc_profile");

prachCfg = sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg, raCfg);
assert(string(prachCfg.ChannelModel) == "TDL-C", ...
    "Four-step RA PRACH config must preserve concrete TDL/CDL channel profile.");

cfg.channel.model = "CDL-D";
if isfield(cfg.channel, "tdlProfile")
    cfg.channel = rmfield(cfg.channel, "tdlProfile");
end
prachCfg = sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg, raCfg);
assert(string(prachCfg.ChannelModel) == "CDL-D", ...
    "Four-step RA PRACH config must preserve concrete CDL channel model.");
ok = true;
end
