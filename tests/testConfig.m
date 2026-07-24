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
assert(~logical(cfg2.channel.awgnOnly), "suite_config.json should not collapse a TDL-C campaign into AWGN-only mode.");
assert(strcmpi(char(string(cfg2.channel.tdlProfile)), "TDL-C"), "suite_config.json must preserve the concrete TDL-C profile.");
assert(double(sixgr.util.structGet(cfg2, "channel.doppler_Hz", 0)) > 0, "suite_config.json should keep Doppler non-zero for TDL-C fading.");

cfgLinkFull = sixgr_loadConfig(fullfile("config","suite_config_linkfull.json"));
cfgLinkFull = sixgr.config.normalizeConfig(cfgLinkFull);
sixgr.config.validateConfig(cfgLinkFull);
assert(~logical(cfgLinkFull.channel.awgnOnly), "suite_config_linkfull.json should not collapse a TDL-C campaign into AWGN-only mode.");
assert(strcmpi(char(string(cfgLinkFull.channel.tdlProfile)), "TDL-C"), "suite_config_linkfull.json must preserve the concrete TDL-C profile.");
assert(double(sixgr.util.structGet(cfgLinkFull, "channel.doppler_Hz", 0)) > 0, "suite_config_linkfull.json should keep Doppler non-zero for TDL-C fading.");

cfgConcrete = sixgr.config.defaultConfig();
cfgConcrete.channel.model = "TDL-C";
cfgConcrete = sixgr.config.normalizeConfig(cfgConcrete);
[cfgConcrete, defaultFrame] = sixgr.config.validateConfig(cfgConcrete);
assert(cfgConcrete.phy.prach.configurationIndex == 0 && ...
    ~isempty(defaultFrame.PRACHTiming.Occasions) && ...
    all(defaultFrame.PRACHTiming.Occasions.ULAvailable), ...
    "The default enabled PRACH configuration must resolve only onto UL-available TDD symbols.");
assert(strcmpi(char(string(cfgConcrete.channel.model)), "TDL"), "Concrete TDL profile must normalize to bare TDL model.");
assert(strcmpi(char(string(cfgConcrete.channel.type)), "TDL"), "Concrete TDL profile must keep channel.type aligned with channel.model.");
assert(strcmpi(char(string(cfgConcrete.channel.tdlProfile)), "TDL-C"), "Concrete TDL profile must be preserved in channel.tdlProfile.");

cfgFadingConcrete = sixgr.config.defaultConfig();
cfgFadingConcrete.channel.model = "TDL";
cfgFadingConcrete.channel.fading.model = "tdl-c";
cfgFadingConcrete.channel.fading.profile = "";
cfgFadingConcrete = sixgr.config.normalizeConfig(cfgFadingConcrete);
sixgr.config.validateConfig(cfgFadingConcrete);
assert(strcmpi(char(string(cfgFadingConcrete.channel.fading.model)), "TDL"), ...
    "Concrete channel.fading.model must normalize to the TDL family.");
assert(strcmpi(char(string(cfgFadingConcrete.channel.fading.profile)), "TDL-C"), ...
    "Concrete channel.fading.model must backfill channel.fading.profile.");
assert(strcmpi(char(string(cfgFadingConcrete.channel.tdlProfile)), "TDL-C"), ...
    "Concrete channel.fading.model must backfill channel.tdlProfile.");

cfgLegacy = sixgr.config.defaultConfig();
cfgLegacy.channel.model = "CDL";
cfgLegacy.channel.fading.model = "CDL";
cfgLegacy.channel.fading.profile = "CDL-D";
cfgLegacy = sixgr.config.normalizeConfig(cfgLegacy);
sixgr.config.validateConfig(cfgLegacy);
assert(strcmpi(char(string(cfgLegacy.channel.cdlProfile)), "CDL-D"), "Legacy channel.fading.profile must backfill channel.cdlProfile.");
assert(strcmpi(char(string(cfgLegacy.channel.fading.model)), "CDL"), ...
    "channel.fading.model must stay normalized to the CDL family.");
assert(strcmpi(char(string(cfgLegacy.channel.fading.profile)), "CDL-D"), ...
    "channel.fading.profile must preserve the concrete CDL profile.");

cfgMismatch = sixgr.config.defaultConfig();
cfgMismatch.channel.model = "TDL";
cfgMismatch.channel.fading.model = "CDL";
cfgMismatch.channel.fading.profile = "CDL-D";
cfgMismatch = sixgr.config.normalizeConfig(cfgMismatch);
threwMismatch = false;
try
    sixgr.config.validateConfig(cfgMismatch);
catch ME
    threwMismatch = contains(string(ME.identifier), "BadChannelProfile");
    assert(contains(string(ME.message), "conflicts with concrete CDL profile"), ...
        "Mismatched TDL/CDL configs should fail with a clear conflict message.");
end
assert(threwMismatch, "Mismatched TDL/CDL family inputs must be rejected.");

cfgBad = sixgr.config.defaultConfig();
cfgBad.channel.model = "TDL";
cfgBad.channel.delayProfile = "";
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

threwFactoryBare = false;
try
    sixgr.channel.ChannelFactory.create(cfgBad, "Model", cfgBad.channel.model);
catch ME
    threwFactoryBare = contains(string(ME.identifier), "ChannelFactory:BadDelayProfile");
    assert(contains(string(ME.message), "concrete delay profile") || contains(string(ME.message), "concrete profile"), ...
        "ChannelFactory should reject bare families before any toolbox DelayProfile assignment.");
end
assert(threwFactoryBare, "ChannelFactory must reject bare TDL/CDL inputs before toolbox construction.");

cfgStrictFastMex = sixgr.config.defaultConfig();
cfgStrictFastMex.run.strictMode = true;
cfgStrictFastMex.run.useMex = true;
cfgStrictFastMex.phy.rx.useFastChannelEstMex = true;
cfgStrictFastMex.channel.model = "TDL";
cfgStrictFastMex.channel.fading.model = "TDL";
cfgStrictFastMex.channel.fading.profile = "TDL-C";
cfgStrictFastMex = sixgr.config.normalizeConfig(cfgStrictFastMex);
threwEstimatorGuard = false;
try
    sixgr.config.validateConfig(cfgStrictFastMex);
catch ME
    threwEstimatorGuard = strcmp(ME.identifier, 'sixgr:config:InvalidChannelEstimator');
    assert(contains(string(ME.message), "useFastChannelEstMex"), ...
        "Strict estimator guard should mention the fast scalar estimator flags.");
end
assert(threwEstimatorGuard, ...
    "Strict mode must reject scalar fast channel estimation on selective fading truth configs.");

cfgAwgnOnly = sixgr.config.defaultConfig();
cfgAwgnOnly.channel.awgnOnly = true;
cfgAwgnOnly = sixgr.config.normalizeConfig(cfgAwgnOnly);
sixgr.config.validateConfig(cfgAwgnOnly);
assert(strcmpi(char(string(cfgAwgnOnly.channel.model)), "AWGN"), "awgnOnly must force the canonical AWGN model.");
assert(strcmpi(char(string(cfgAwgnOnly.channel.type)), "AWGN"), "awgnOnly must keep channel.type aligned with the AWGN model.");
assert(isfield(cfgAwgnOnly.channel, "fading") && ~logical(cfgAwgnOnly.channel.fading.enable), ...
    "awgnOnly must disable fading.");
assert(strlength(string(cfgAwgnOnly.channel.fading.model)) == 0, ...
    "awgnOnly must clear stale channel.fading.model values.");
assert(strlength(string(cfgAwgnOnly.channel.fading.profile)) == 0, ...
    "awgnOnly must clear stale channel.fading.profile values.");

cfgWaveformBackend = sixgr.config.defaultConfig();
cfgWaveformBackend.system.phyBackend = "waveform";
cfgWaveformBackend = sixgr.config.normalizeConfig(cfgWaveformBackend);
sixgr.config.validateConfig(cfgWaveformBackend);
assert(strcmpi(char(string(cfgWaveformBackend.system.phyBackend)), "waveform"), ...
    "system.phyBackend='waveform' must survive normalize/validate.");

cfgBadBackend = sixgr.config.defaultConfig();
cfgBadBackend.system.phyBackend = "nonsense";
cfgBadBackend = sixgr.config.normalizeConfig(cfgBadBackend);
threwBadBackend = false;
try
    sixgr.config.validateConfig(cfgBadBackend);
catch ME
    threwBadBackend = strcmp(ME.identifier, 'sixgr:config:BadEnum');
    assert(contains(string(ME.message), "system.phyBackend"), ...
        "Bad system.phyBackend errors should identify the field.");
end
assert(threwBadBackend, "validateConfig must reject unknown system.phyBackend values.");

ok = true;
end
