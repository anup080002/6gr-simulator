function ok = testPUCCHPUSCHReservationFDDTDD()
%TESTPUCCHPUSCHRESERVATIONFDDTDD Exact configured PUCCH PRBs never enter PUSCH budgets.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localRemove(tmp)); %#ok<NASGU>
paths = [ ...
    "lls_mimo4x4_multiuser_beamformed.yaml", ...
    "lls_causal_access_to_data_wiring_tdd.yaml"];
for scenarioIndex = 1:numel(paths)
    scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
        "simulator", "configs", "scenarios", paths(scenarioIndex)));
    cfg = sixgr.lls6g.buildInternalConfig(scenario, ...
        fullfile(tmp, "run_" + string(scenarioIndex)));
    assert(logical(cfg.phy.pucch.reserveConfiguredPRBsFromPUSCH), ...
        "FDD and TDD fixtures must enable exact configured PUCCH reservation.");
    state = localBudgetState(cfg);
    budget = sixgr.truth.CoupledTruthRuntime.configuredSlotBudgetRuntime(state);
    expected = localConfiguredPUCCHPRBs(cfg.validation.pucch_resources.resources);
    assert(~isempty(expected) && isequal(sort(double(budget.ReservedPUCCHPRBSet)), ...
        sort(expected)), "Budget must disclose every reserved configured PUCCH PRB.");
    assert(isempty(intersect(double(budget.PRBSet), expected)), ...
        "PUSCH budget illegally includes a configured standalone PUCCH PRB.");
end
ok = true;
fprintf("[PASS] Exact PUCCH/PUSCH PRB reservation retained for FDD and TDD.\n");
end

function state = localBudgetState(cfg)
state = struct();
state.CfgMobility = cfg;
state.SymbolsPerSlot = double(sixgr.util.structGet(cfg, ...
    "phy.numerology.symbolsPerSlot", 14));
state.NumRB = double(sixgr.util.structGet(cfg, ...
    "phy.carrier.NSizeGrid", sixgr.util.structGet(cfg, "phy.nRB", NaN)));
state.CurrentSlot = 1;
state.CurrentDirection = "UL";
state.TimingControlAbsoluteSlot0Based = 0;
state.CurrentSlotULSymbolStart = 0;
state.CurrentSlotULNumSymbols = state.SymbolsPerSlot;
state.CurrentSlotDLSymbolStart = 0;
state.CurrentSlotDLNumSymbols = state.SymbolsPerSlot;
state.ControlGating = struct("PDCCHRequired", false);
end

function prbs = localConfiguredPUCCHPRBs(resources)
prbs = zeros(1, 0);
for i = 1:numel(resources)
    startPRB = double(resources(i).starting_prb);
    count = double(resources(i).nrof_prbs);
    prbs = union(prbs, startPRB:(startPRB + count - 1), "stable");
end
end

function localRemove(root)
if isfolder(root)
    rmdir(root, "s");
end
end
