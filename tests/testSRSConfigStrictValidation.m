function ok = testSRSConfigStrictValidation()
setup6GRSimToolkit("Verbose", false);
b = srsStrictAnchorResult();
cfg = b.Config;
assert(logical(cfg.StrictValidation.StrictValid), "Strict SRS config must validate.");
assert(isa(cfg.ToolboxSRS, "nrSRSConfig"), "Strict SRS must bind to nrSRSConfig.");
assert(double(cfg.NumSRSPorts) == 1 && double(cfg.ExpectedNumRB) == 24, "Strict SRS anchor must expose configured ports and full-band RB target.");
bad = cfg; bad.CombOffset = double(cfg.CombNumber);
assert(~logical(sixgr.phy.srs.validateSRSConfigStrict(bad).StrictValid), "Invalid comb offset must fail strict validation.");
bad = cfg; bad.NumSRSPorts = 3;
assert(~logical(sixgr.phy.srs.validateSRSConfigStrict(bad).StrictValid), "Unsupported SRS port count must fail strict validation.");
bad = cfg; bad.ResourceType = "aperiodic"; bad.DCITriggerReferenceId = "";
assert(~logical(sixgr.phy.srs.validateSRSConfigStrict(bad).StrictValid), "Aperiodic SRS without decoded DCI trigger must fail.");
bad = cfg; bad.ResourceType = "semiPersistent"; bad.ActivationMACCEReferenceId = "";
assert(~logical(sixgr.phy.srs.validateSRSConfigStrict(bad).StrictValid), "Semi-persistent SRS without activation evidence must fail closed.");
ok = true;
end
