function ok = testRAConfigBinding()
cfg = raStrictAnchorConfig();
ra = sixgr.mac.ra.RAConfig(cfg, "RunId", "test_ra_config");
assert(ra.BindingSource == "scenario_config_pending_sib1", "RA binding source must be explicit.");
assert(strlength(ra.RACHConfigHash) > 16, "RA config hash must be exported.");
bad = cfg;
bad.random_access = rmfield(bad.random_access, "preamble_index");
threw = false;
try
    sixgr.mac.ra.RAConfig(bad);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:mac:ra:MissingMandatoryRACHFields");
end
assert(threw, "Missing mandatory RACH fields must fail closed.");
ok = true;
end
