function ok = testPRACHOracleGuard()
%TESTPRACHORACLEGUARD Receiver no-oracle PRACH guard.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
oracleT = b.Result.ArtifactTables.prach_oracle_guard;
trialT = b.Result.ArtifactTables.prach_trials;

for fieldName = ["tx_preamble_index","tx_root_sequence_index","tx_timing_offset_samples", ...
        "tx_snr_db","tx_collision_label","ue_object_internal_state"]
    assert(any(string(oracleT.OracleFieldName) == fieldName), ...
        "Oracle guard must audit forbidden receiver field " + fieldName + ".");
end
assert(all(~logical(oracleT.WasAccessed) & ~logical(oracleT.Violation)), ...
    "Strict PRACH detector must not access transmitter oracle fields.");
assert(all(strlength(strtrim(string(trialT.UsedOracleFields))) == 0), ...
    "Strict PRACH trial rows must not list any used oracle fields.");

ok = true;
end
