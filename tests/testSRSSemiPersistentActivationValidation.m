function ok = testSRSSemiPersistentActivationValidation()
setup6GRSimToolkit("Verbose", false);
cfg = srsStrictAnchorResult().Config;
cfg.ResourceType = "semiPersistent";
cfg.ActivationMACCEReferenceId = "";
T = sixgr.phy.srs.validateSRSSemiPersistentActivation(cfg);
assert(~logical(T.ActivationValid) && contains(string(T.Status), "missing_fail_closed"), ...
    "Semi-persistent SRS without MAC CE activation evidence must fail closed.");
assert(~logical(sixgr.phy.srs.validateSRSConfigStrict(cfg).StrictValid), ...
    "Strict SRS config must reject unsupported semi-persistent activation profile.");
ok = true;
end
