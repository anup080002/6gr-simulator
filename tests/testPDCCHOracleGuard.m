function ok = testPDCCHOracleGuard()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_oracle_guard;
assert(height(T) > 0, "Oracle guard table must be exported.");
assert(~any(logical(T.WasAccessed) & ~logical(T.Allowed)), ...
    "Strict PDCCH receiver must not access transmitter/scheduler oracle fields before decode.");
assert(~any(logical(T.Violation)), "Strict PDCCH oracle guard must have zero violations.");
ok = true;
end
