function ok = testTargetScenarioPRACHRuntimeGating()
%TESTTARGETSCENARIOPRACHRUNTIMEGATING Guard canonical carrier-slot gating.

setup6GRSimToolkit("Verbose", false);
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scenario, fullfile(tmp, "run"));

validSlots = double(sixgr.util.structGet( ...
    cfg, "phy.prach.validSlots1Based", []));
assert(~isempty(validSlots), ...
    "The strict target scenario must resolve at least one PRACH carrier slot.");
for slot = 1:double(sixgr.util.structGet( ...
        cfg, "frame_timing.slots_per_frame", 20))
    expected = ismember(slot, validSlots);
    actual = sixgr.truth.isActivePRACHOccasion(cfg, slot);
    assert(actual == expected, ...
        "Runtime PRACH gating disagrees with canonical carrier slot %d.", ...
        slot);
end

for slot = validSlots(:).'
    % validSlots1Based and the coupled runtime counter are one-based;
    % resolveTDDSlotPartition consumes an absolute zero-based slot.
    partition = sixgr.util.resolveTDDSlotPartition(cfg, slot - 1);
    assert(logical(partition.AllowUL), ...
        "Resolved PRACH carrier slot %d is not UL-available in TDD.", ...
        slot);
end
ok = true;
end

function localCleanup(pathText)
if isfolder(pathText)
    rmdir(pathText, "s");
end
end
