function ok = testRegressionExecutionAuthority()
% A suite factory is not evidence until its contained tests execute.
keys = {'sixgrRegressionHarnessProbeMode','sixgrRegressionHarnessProbeExecuted'};
present = cellfun(@(key)isappdata(0,key),keys);
values = cell(size(keys));
for k = find(present), values{k} = getappdata(0,keys{k}); end
cleanup = onCleanup(@()localRestore(keys,present,values)); %#ok<NASGU>
for mode = ["pass","fail","incomplete"]
    setappdata(0,keys{1},char(mode)); setappdata(0,keys{2},false);
    if mode == "pass"
        executeRegressionTest(@regressionHarnessProbeTest);
    else
        localReject(@()executeRegressionTest(@regressionHarnessProbeTest), ...
            'sixgr:tests:UnsuccessfulTestResults');
    end
    assert(getappdata(0,keys{2}), 'The test body was never executed.');
end
executeRegressionTest(@()true);
executeRegressionTest(@localNoOutput);
localReject(@()executeRegressionTest(@()false),'sixgr:tests:UnsuccessfulReturn');
localReject(@()executeRegressionTest(@()struct('ok',false)), ...
    'sixgr:tests:UnsuccessfulReturn');
localReject(@()executeRegressionTest(@()matlab.unittest.TestSuite.empty), ...
    'sixgr:tests:EmptySuite');
% Both report-returning and command-line paths must reject the failed probe.
setappdata(0,keys{1},'fail');
report = runFocusedTests("regressionHarnessProbeTest","ShowSlowest",0);
assert(~report.ok && ~report.results(1).ok);
localReject(@()runFocusedTests("regressionHarnessProbeTest","ShowSlowest",0), ...
    'sixgr:tests:RegressionFailed');
localReject(@()testAll("Names","regressionHarnessProbeTest","ShowSlowest",0), ...
    'sixgr:tests:RegressionFailed');
for file = ["testAll.m","runFocusedTests.m"]
    source = fileread(fullfile(fileparts(mfilename('fullpath')),file));
    assert(contains(source,'executeRegressionTest(fn);') && ~contains(source,'feval(fn);'));
end
ok = true;
fprintf('PASS testRegressionExecutionAuthority (intentional negative probe failures above were required).\n');
end

function localNoOutput()
assert(true);
end
function localRestore(keys,present,values)
for k = 1:numel(keys)
    if present(k), setappdata(0,keys{k},values{k});
    elseif isappdata(0,keys{k}), rmappdata(0,keys{k}); end
end
end
function localReject(call,identifier)
try
    call();
catch exception
    assert(strcmp(exception.identifier,identifier),'Expected %s, received %s.',identifier,exception.identifier);
    return;
end
error('testRegressionExecutionAuthority:MissingRejection','Expected %s.',identifier);
end
