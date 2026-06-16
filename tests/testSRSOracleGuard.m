function ok = testSRSOracleGuard()
setup6GRSimToolkit("Verbose", false);
T = srsStrictAnchorResult().Result.ArtifactTables.srs_oracle_guard;
assert(height(T) > 0 && ~any(logical(T.Violation)), "SRS oracle guard must report zero forbidden receiver inputs.");
ok = true;
end
