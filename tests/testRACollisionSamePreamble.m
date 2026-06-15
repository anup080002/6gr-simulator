function ok = testRACollisionSamePreamble()
res = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), "FaultMode", "collision_same_preamble", "WriteArtifacts", false);
assert(~logical(res.RACompleted) && ~logical(res.StrictOk), "Same-preamble collision must not silently pass.");
assert(logical(res.CollisionDetected), "Collision evidence must be explicit.");
assert(string(res.FailureReason) == "preamble_collision_unresolved", "Collision failure reason must be explicit.");
ok = true;
end
