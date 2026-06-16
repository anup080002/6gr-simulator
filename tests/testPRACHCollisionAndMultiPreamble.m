function ok = testPRACHCollisionAndMultiPreamble()
%TESTPRACHCOLLISIONANDMULTIPREAMBLE Collision and multi-preamble evidence.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
collisionT = b.Result.ArtifactTables.prach_collision_trials;
assert(height(collisionT) >= 4, "Collision sweep must include same-preamble and different-preamble UE rows.");
assert(any(logical(collisionT.SamePreamble)) && any(~logical(collisionT.SamePreamble)), ...
    "Collision sweep must include both same-preamble and different-preamble cases.");
assert(any(logical(collisionT.SamePreamble) & logical(collisionT.CollisionDetected)), ...
    "Same-preamble collision must be explicitly detected.");
assert(any(logical(collisionT.MultiplePreamblesDetected)), ...
    "Collision sweep must expose measured multi-candidate detection evidence.");
assert(all(logical(collisionT.CollisionInjected) & logical(collisionT.SameOccasion)), ...
    "Collision rows must explicitly state collision injection and same-occasion scope.");

ok = true;
end
