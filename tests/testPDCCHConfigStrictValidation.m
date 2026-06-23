function ok = testPDCCHConfigStrictValidation()
%TESTPDCCHCONFIGSTRICTVALIDATION Strict PDCCH config validation guards.

setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
configT = b.Result.ArtifactTables.pdcch_config_strict;
assert(height(configT) == 1, "Strict PDCCH config export must contain one effective config row.");
assert(logical(configT.StrictValid(1)), "Strict PDCCH mini-anchor config must be valid.");
assert(string(configT.RNTIType(1)) == "C-RNTI", "Strict PDCCH anchor must preserve configured C-RNTI.");
assert(double(configT.ConfiguredDCIPayloadSizeBits(1)) == double(configT.DCIPayloadSizeBits(1)), ...
    "Strict PDCCH anchor YAML payload size must match the standard-derived DCI size.");
assert(~logical(configT.DCIPayloadConfiguredMismatch(1)), ...
    "Strict PDCCH anchor must not carry a stale configured DCI payload size.");

missing = b.InternalConfig;
missing.phy.pdcch = rmfield(missing.phy.pdcch, "coreset");
failedClosed = false;
try
    sixgr.phy.pdcch.PDCCHConfigStrict(missing, "RunFolder", tempname, "ScenarioName", "missing_coreset");
catch ME
    failedClosed = strcmp(string(ME.identifier), "sixgr:phy:pdcch:MissingStrictConfigField");
end
assert(failedClosed, "Strict PDCCH must fail closed when mandatory CORESET fields are missing.");

bad = b.Config;
bad.AggregationLevel = 3;
bad.StrictValidation = sixgr.phy.pdcch.validatePDCCHConfigStrict(bad);
assert(~logical(bad.StrictValidation.StrictValid), "Strict PDCCH must reject invalid aggregation levels.");

badFmt = b.Config;
badFmt.DCIMonitoringFormats = "2_0";
badFmt.StrictValidation = sixgr.phy.pdcch.validatePDCCHConfigStrict(badFmt);
assert(~logical(badFmt.StrictValidation.StrictValid), "Strict PDCCH must fail closed for unsupported DCI formats.");
ok = true;
end
