function ok = testPAModelSelectionAuthority()
% The selected mathematical PA model must be the one actually executed.
assert(exist('comm.MemorylessNonlinearity','class')==8, ...
    'This native-model equivalence test requires Communications Toolbox.');
cfg.rf.pa = struct('enable',true,'method','memoryless', ...
    'backoff_dB',2,'gain_dB',1,'iip3_dBm',35,'ampm_deg',4);
pa = sixgr.rf.PAModel(cfg);
assert(~pa.MemoryEnabled && pa.UseCommObj, ...
    'The word memoryless must not enable a memory polynomial.');
native = comm.MemorylessNonlinearity('Method','Cubic polynomial', ...
    'IIP3',35,'AMPMConversion',4);
x = logspace(-3,-0.1,97).' .* exp(1i*(0:96).'/19);
expected = native(x*10^(-2/20))*10^(1/20);
actual = pa.apply(x);
assert(max(abs(actual-expected)) < 4e-15, ...
    'Native AM/AM and AM/PM must execute exactly once with authored gain/backoff.');
bad = cfg;
bad.rf.pa.method = 'unrecognized_model';
localReject(@()sixgr.rf.PAModel(bad),'PAModel:UnsupportedMethod');
bad = cfg;
bad.rf.pa.memory.enable = true;
localReject(@()sixgr.rf.PAModel(bad),'PAModel:ConflictingMemoryAuthority');
bad = cfg;
bad.rf.pa.iip3_dBm = NaN;
localReject(@()sixgr.rf.PAModel(bad),'PAModel:BackendInitializationFailed');
cfg.powerAndRF.ueTxPower_dBm = 0;
cfg.powerAndRF.ueRFChainCount = 1;
[~,power] = sixgr.rf.applyPowerContext(x,cfg,'UL',struct());
assert(string(power.PAModel)=="memoryless" && string(power.PAExecutionStatus)== ...
    "applied_memoryless_pa_in_physical_sample_units", ...
    'Power evidence must not relabel memoryless execution as memory polynomial.');
ok = true;
disp('PA_MODEL_SELECTION_AUTHORITY_PASS');
end

function localReject(action,identifier)
try
    action();
catch cause
    assert(string(cause.identifier)==string(identifier), ...
        'Expected %s; got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('testPAModelSelectionAuthority:MissingError','Expected %s.',identifier);
end
