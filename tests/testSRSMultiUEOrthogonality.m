function ok = testSRSMultiUEOrthogonality()
setup6GRSimToolkit("Verbose", false);
T = srsStrictAnchorResult().Result.ArtifactTables.srs_multi_ue_trials;
assert(any(logical(T.OrthogonalityPass) & logical(T.ChannelEstimateAvailable)), ...
    "SRS multi-UE evidence must include an orthogonal separable resource row.");
ok = true;
end
