function ok = testSRSMultiUECollision()
setup6GRSimToolkit("Verbose", false);
T = srsStrictAnchorResult().Result.ArtifactTables.srs_multi_ue_trials;
assert(any(logical(T.CollisionInjected) & logical(T.CollisionDetected)), ...
    "SRS multi-UE evidence must include an explicit collision row.");
ok = true;
end
