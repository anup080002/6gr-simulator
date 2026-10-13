function ok = testTRSWrongResourceMappingNegative()
setup6GRSimToolkit("Verbose", false);
localAssertNegative("wrong_resource_mapping");
% The former +1 mutation only worked for [4,8] and [5,9]. Cover the
% report scenario's [6,10] pair through the production validation runner.
bundle = trsStrictAnchorResult();
resolved = sixgr.lls6g.config.loadScenarioConfig(bundle.ScenarioPath).toStruct();
for pair = [5 6;9 10]
    resolved.reference_signals.trs.symbol_locations = pair.';
    cfg = sixgr.lls6g.buildInternalConfig(resolved,tempname);
    result = sixgr.phy.trs.runStrictTRSValidation(cfg,'WriteArtifacts',false);
    T = result.ArtifactTables.trs_negative_trials;
    row = T(string(T.TrialType)=="wrong_resource_mapping",:);
    assert(height(row)==1 && ~row.StrictOk && row.NegativeExpectedOk && ...
        ~row.ProxyUsed && ~row.Skipped, ...
        'Every supported pair must execute the wrong-resource physical negative.');
end
bad = result.Config;
bad.SymbolLocation = [7 11];
try
    sixgr.phy.trs.buildNZPCSIRSResourceSetForTRS(bad);
    error('testTRSWrongResourceMappingNegative:ExpectedRejection','Invalid pair was accepted.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:phy:trs:UnsupportedTrackingSymbolPair'));
end
ok = true;
end

function localAssertNegative(name)
T = trsStrictAnchorResult().Result.ArtifactTables.trs_negative_trials;
row = T(string(T.TrialType) == string(name), :);
assert(height(row) == 1 && ~logical(row.StrictOk(1)) && logical(row.NegativeExpectedOk(1)), ...
    "%s must fail strict as an expected negative.", name);
end
