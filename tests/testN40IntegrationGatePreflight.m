function ok=testN40IntegrationGatePreflight()
setup6GRSimToolkit('Verbose',false);
gate='simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_integration_gate.yaml';
original='simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml';
a=sixgr.lls6g.config.loadScenarioConfig(gate);
b=sixgr.lls6g.config.loadScenarioConfig(original);
assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(a.toStruct()), ...
    sixgr.runtime.SlotCheckpoint.scientificScenario(b.toStruct())), ...
    'Integration checkpoint overlay must not alter science.');
root=tempname;
plan=sixgr.validation.preflightN40IntegrationGate(gate,root,'gate_preflight');
assert(numel(plan.Children)==2 && ~plan.PhysicalExecution);
reject(@()sixgr.validation.preflightN40IntegrationGate(original,root,'gate_preflight'), ...
    'sixgr:validation:N40GateCheckpoints');
mkdir(plan.RunFolder);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
reject(@()sixgr.validation.preflightN40IntegrationGate(gate,root,'gate_preflight'), ...
    'sixgr:validation:N40GateExistingRun');
fprintf('N40_INTEGRATION_GATE_PREFLIGHT_PASS physical_execution=0\n');
ok=true;
end

function reject(call,identifier)
caught=false;
try, call(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    caught=true;
end
assert(caught,'Expected %s.',identifier);
end
