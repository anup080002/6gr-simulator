function ok = testStrictProxyGuards()
%TESTSTRICTPROXYGUARDS Ensure quarantined proxy paths fail closed.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(which("setup6GRSimToolkit"));

assert(exist(fullfile(repoRoot, "+sixgr", "+system", "BLER_DB.m"), "file") == 0, ...
    "BLER_DB proxy backend source should be removed from the repo.");
assert(exist(fullfile(repoRoot, "+sixgr", "+system", "BLER_LUT.m"), "file") == 0, ...
    "BLER_LUT proxy backend source should be removed from the repo.");
assert(exist(fullfile(repoRoot, "+sixgr", "+hybrid", "CalibrateBLER.m"), "file") == 0, ...
    "Hybrid calibration source should be removed from the repo.");

cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
threwPHY = false;
try
    sixgr.system.PhyFactory.create(cfg, struct("PHYBackend", "abstract")); %#ok<NASGU>
catch ME
    threwPHY = strcmp(ME.identifier, "sixgr:system:ProxyBackendRemoved");
end
assert(threwPHY, "PhyFactory should reject the removed abstract/proxy backend.");

ok = true;
end
