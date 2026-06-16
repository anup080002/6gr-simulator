function ok = testPRACHConfigStrictValidation()
%TESTPRACHCONFIGSTRICTVALIDATION Strict PRACH config validation guards.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
configT = b.Result.ArtifactTables.prach_config_strict;
assert(height(configT) == 1, "Strict PRACH config export must contain exactly one effective config row.");
assert(logical(configT.StrictValid(1)), "Strict PRACH config row must be valid for the mini anchor.");
assert(string(configT.RestrictedSet(1)) == "RestrictedSetTypeA", ...
    "Mini anchor must preserve the configured restricted-set type A profile.");
assert(string(configT.DuplexMode(1)) == "FDD", "Strict PRACH FDD config must remain FDD.");

missing = b.InternalConfig;
missing.random_access = rmfield(missing.random_access, "n_cell_id");
failedClosed = false;
try
    sixgr.phy.prach.PRACHConfigStrict(missing, "RunFolder", tempname, "ScenarioName", "missing_ncellid");
catch ME
    failedClosed = strcmp(string(ME.identifier), "sixgr:phy:prach:MissingStrictConfigField");
end
assert(failedClosed, "Strict PRACH must fail closed when mandatory n_cell_id is missing.");

badPreamble = b.Config;
badPreamble.PreambleIndex = 999;
badPreamble.StrictValidation = sixgr.phy.prach.validatePRACHConfigStrict(badPreamble);
assert(~logical(badPreamble.StrictValidation.StrictValid), ...
    "Strict PRACH validation must reject out-of-range preamble indices.");
assert(any(contains(string(badPreamble.StrictValidation.FailureReasons), "preamble_index_out_of_range")), ...
    "Out-of-range preamble rejection must be explicit in validation reasons.");

badZCZ = b.Config;
badZCZ.ZeroCorrelationZone = 999;
badZCZ.StrictValidation = sixgr.phy.prach.validatePRACHConfigStrict(badZCZ);
assert(~logical(badZCZ.StrictValidation.StrictValid), ...
    "Strict PRACH validation must reject invalid zeroCorrelationZoneConfig values.");

ok = true;
end
