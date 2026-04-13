function ok = testSLS_Abstract()
%TESTSLS_ABSTRACT Abstract/proxy SLS backend must be quarantined.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.system.phyBackend = "waveform";
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

threw = false;
try
    sixgr.system.PhyFactory.create(cfg, struct("PHYBackend", "abstract")); %#ok<NASGU>
catch ME
    threw = strcmp(ME.identifier, "sixgr:system:ProxyBackendRemoved");
    assert(contains(string(ME.message), "waveform"), ...
        "Abstract backend quarantine should explain the waveform-only requirement.");
end
assert(threw, "Abstract/proxy SLS backend must be quarantined.");
ok = true;
end
