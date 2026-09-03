function ok = testHARQEntityYAMLRVAuthority()
%TESTHARQENTITYYAMLRVAUTHORITY YAML-derived RV order drives live HARQ state.

cfg = struct();
cfg.phy.harq.rvSequence = [0 3 2 1];
cfg.phy.harq.nProcesses = 4;
cfg.mac.harq.numProcesses = 4;
cfg.mac.harq.maxRetx = 3;

harq = sixgr.l2.mac.HARQEntityDL(cfg);
assert(isequal(harq.RVSequence, [0 3 2 1]), ...
    "Live HARQEntity did not consume cfg.phy.harq.rvSequence.");
assert(harq.NumProcesses == 4 && harq.MaxRetx == 3, ...
    "Live HARQEntity did not consume configured process-count/maxRetx authority.");

% Explicit constructor overrides are visible test authority and must win.
override = sixgr.l2.mac.HARQEntityDL(cfg, "RVSequence", [0 2], ...
    "NumProcesses", 2, "MaxRetx", 1);
assert(isequal(override.RVSequence, [0 2]) && ...
    override.NumProcesses == 2 && override.MaxRetx == 1);

bad = cfg;
bad.phy.harq.rvSequence = [2 0 3 1];
threw = false;
try
    sixgr.l2.mac.HARQEntityDL(bad); %#ok<NASGU>
catch ME
    threw = string(ME.identifier) == "sixgr:mac:InvalidHARQRVSequence";
end
assert(threw, "Invalid configured new-data RV must fail closed.");

ok = true;
fprintf("testHARQEntityYAMLRVAuthority: PASS\n");
end
