function ok = testTRSOracleGuard()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_oracle_guard;
assert(height(T) > 0 && ~any(logical(T.Violation)) && ~any(logical(T.WasAccessed)), ...
    "TRS oracle guard must prove forbidden oracle fields were not accessed.");
ok = true;
end
