function ok = testStrictProxyGuards()
%TESTSTRICTPROXYGUARDS Ensure strict mode blocks synthetic/proxy calibration.

setup6GRSimToolkit("Verbose", false);

% BLER_DB must reject implicit synthetic tensor generation.
threwImplicit = false;
try
    sixgr.system.BLER_DB(); %#ok<NASGU>
catch
    threwImplicit = true;
end
assert(threwImplicit, "BLER_DB should reject implicit synthetic generation.");

% BLER_DB strict build must reject synthetic tensor generation.
threwDB = false;
try
    sixgr.system.BLER_DB("StrictMode", true); %#ok<NASGU>
catch
    threwDB = true;
end
assert(threwDB, "Strict BLER_DB build should reject synthetic fallback.");

% PhyFactory strict mode must reject default/synthetic DB source.
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
params = struct("BLERDB", sixgr.system.BLER_DB("AllowSynthetic", true));
threwPHY = false;
try
    sixgr.system.PhyFactory.create(cfg, params); %#ok<NASGU>
catch
    threwPHY = true;
end
assert(threwPHY, "Strict PhyFactory should reject synthetic/default BLER DB.");

% CalibrateBLER should not silently synthesize unsupported contexts by default.
cfgCal = cfg;
cfgCal.run.strictMode = false;
ctxCal = sixgr.core.SimContext(cfgCal);
threwCal = false;
try
    sixgr.hybrid.CalibrateBLER(ctxCal, struct( ...
        "SNRGrid_dB", [0], ...
        "CalibFrames", 1, ...
        "CalibDirection", ["DL"], ...
        "CalibMCS", [6], ...
        "CalibPRB", [10], ...
        "CalibLayers", [1], ...
        "CalibSCS_kHz", [30], ...
        "CalibDopplerHz", [0], ...
        "CalibChannelModels", ["TDL-C"]));
catch
    threwCal = true;
end
assert(threwCal, "CalibrateBLER should fail on unsupported truth context unless fallback is explicitly enabled.");

ok = true;
end
