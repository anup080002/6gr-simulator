function ok = testSweepPointFailureIsolation()
% Orchestration tests only: these callbacks make no physical PHY claim.
setup6GRSimToolkit('Verbose',false);
policy = "retain_failure_and_continue";
callbacks = {@() localThrow('test:PointFailure','Retained failure'), ...
    @() struct('Ok',false), @() struct('Ok',true)};
outcomes = cell(1,numel(callbacks));
for i = 1:numel(callbacks)
    outcomes{i} = sixgr.lls6g.runners.executeSweepPoint(callbacks{i},policy);
end
assert(~outcomes{1}.Ok && ~outcomes{1}.Returned);
assert(outcomes{1}.ExecutionStatus == "execution_error");
assert(outcomes{1}.ErrorIdentifier == "test:PointFailure");
assert(contains(outcomes{1}.ErrorReport,"Retained failure"));
assert(outcomes{2}.Returned && ~outcomes{2}.Ok && ...
    outcomes{2}.ExecutionStatus == "completed_fail");
assert(outcomes{3}.Returned && outcomes{3}.Ok && ...
    outcomes{3}.ExecutionStatus == "completed_pass");
assert(~all(cellfun(@(r) r.Ok,outcomes)));
localReject(callbacks{1},"abort","test:PointFailure");
localReject(@() localThrow('MATLAB:nomem','resource exhaustion'),policy,"MATLAB:nomem");
localReject(@() localThrow('MATLAB:OperationTerminated','interrupted'),policy,"MATLAB:OperationTerminated");
localReject(@() struct('Ok',NaN),policy,"sixgr:lls6g:runner:InvalidSweepPointResult");
root = fullfile('simulator','configs','scenarios');
for name = ["lls_tdd_5mhz_rank2_shared_awgn_snr_sweep.yaml", ...
        "lls_tdd_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml"]
    scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(root,name));
    assert(string(scfg.get('scenario.sweep.execution_error_policy')) == policy);
    raw = scfg.toStruct();
    raw.scenario.sweep.execution_error_policy = 'silently_pass';
    rejected = false;
    try
        sixgr.lls6g.config.validateScenarioConfig(raw,'Kind','scenario','AllowPartial',false);
    catch
        rejected = true;
    end
    assert(rejected,'Unsupported sweep error policy must fail configuration validation.');
end
fprintf('SWEEP_POINT_FAILURE_ISOLATION_PASS continuation_without_pass_or_phy_fabrication\n');
ok = true;
end

function result = localThrow(identifier,message) %#ok<STOUT>
error(identifier,'%s',message);
end

function localReject(execute,policy,identifier)
try
    sixgr.lls6g.runners.executeSweepPoint(execute,policy);
catch failure
    assert(string(failure.identifier) == identifier);
    return;
end
error('test:ExpectedSweepFailure','Expected failure %s.',identifier);
end
