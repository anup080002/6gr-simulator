function ok = testConfig()
%TESTCONFIG Regression checks for config load/normalize/validate.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr_loadConfig(fullfile("config","suite_config.json"));
assert(isstruct(cfg), "cfg must be a struct");
assert(isfield(cfg, "run") && isfield(cfg.run, "mode"), "cfg.run.mode missing");
assert(isfield(cfg, "phy") && isfield(cfg.phy, "carrier"), "cfg.phy.carrier missing");
assert(isfield(cfg, "mac") && isfield(cfg.mac, "scheduler"), "cfg.mac.scheduler missing");
assert(isfield(cfg, "traffic") && isfield(cfg.traffic, "model"), "cfg.traffic.model missing");

cfg2 = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg2);
assert(isfield(cfg2, "channel") && isfield(cfg2.channel, "bandwidth_Hz"), "cfg.channel.bandwidth_Hz missing after normalize");

cfgConcrete = sixgr.config.defaultConfig();
cfgConcrete.channel.model = "TDL-C";
cfgConcrete = sixgr.config.normalizeConfig(cfgConcrete);
sixgr.config.validateConfig(cfgConcrete);
assert(strcmpi(char(string(cfgConcrete.channel.model)), "TDL"), "Concrete TDL profile must normalize to bare TDL model.");
assert(strcmpi(char(string(cfgConcrete.channel.tdlProfile)), "TDL-C"), "Concrete TDL profile must be preserved in channel.tdlProfile.");

cfgLegacy = sixgr.config.defaultConfig();
cfgLegacy.channel.model = "CDL";
cfgLegacy.channel.fading.model = "CDL";
cfgLegacy.channel.fading.profile = "CDL-D";
cfgLegacy = sixgr.config.normalizeConfig(cfgLegacy);
sixgr.config.validateConfig(cfgLegacy);
assert(strcmpi(char(string(cfgLegacy.channel.cdlProfile)), "CDL-D"), "Legacy channel.fading.profile must backfill channel.cdlProfile.");

cfgBad = sixgr.config.defaultConfig();
cfgBad.channel.model = "TDL";
cfgBad.channel.fading.profile = "";
cfgBad = sixgr.config.normalizeConfig(cfgBad);
assert(~isfield(cfgBad.channel, "tdlProfile") || ~strcmpi(char(string(cfgBad.channel.tdlProfile)), "TDL"), ...
    "normalizeConfig must not manufacture channel.tdlProfile='TDL' from a bare TDL model.");
threwBare = false;
try
    sixgr.config.validateConfig(cfgBad);
catch ME
    threwBare = contains(string(ME.identifier), "AmbiguousChannelModel");
    assert(contains(string(ME.message), "concrete TDL profile"), "Bare TDL rejection should explain the missing concrete profile.");
end
assert(threwBare, "Bare TDL channel config should be rejected before ChannelFactory runs.");

ok = true;
end
