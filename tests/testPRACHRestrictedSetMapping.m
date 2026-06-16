function ok = testPRACHRestrictedSetMapping()
%TESTPRACHRESTRICTEDSETMAPPING Restricted-set, ZCZ, and root-budget evidence.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
mappingT = b.Result.ArtifactTables.prach_restricted_set_mapping;
zczT = b.Result.ArtifactTables.prach_zcz_cyclic_shift_mapping;
rootT = b.Result.ArtifactTables.prach_root_sequence_budget;

sets = unique(string(mappingT.RestrictedSet));
assert(all(ismember(["UnrestrictedSet","RestrictedSetTypeA","RestrictedSetTypeB"], sets)), ...
    "Strict PRACH mapping must cover unrestricted, restricted set A, and restricted set B.");
assert(all(logical(mappingT.Valid)), "Long-sequence anchor restricted-set mappings must be valid.");
assert(all(isfinite(double(mappingT.NCS))), "Restricted-set mapping must export finite N_CS values.");
assert(all(logical(zczT.Valid)) && all(isfinite(double(zczT.CyclicShiftValue))), ...
    "ZCZ cyclic-shift mapping must export finite valid cyclic shifts.");
assert(all(logical(rootT.BudgetOk)) && all(double(rootT.NumPreamblesAvailable) > 0), ...
    "Root sequence budget must prove the requested preambles are supportable.");

shortFailedClosed = false;
try
    sixgr.phy.prach.deriveNCSFromZeroCorrelationZone(8, "RestrictedSetTypeA", 139);
catch ME
    shortFailedClosed = strcmp(string(ME.identifier), "sixgr:phy:prach:RestrictedSetInvalidForShortFormat");
end
assert(shortFailedClosed, "Unsupported short-format restricted-set PRACH must fail closed.");

ok = true;
end
