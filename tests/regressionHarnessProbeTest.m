function tests = regressionHarnessProbeTest()
% Test-harness self-test only. Default invocation is a passing test.
tests = functiontests(localfunctions);
end

function testExecution(testCase)
key = 'sixgrRegressionHarnessProbeMode';
if ~isappdata(0,key), return; end
mode = getappdata(0,key);
setappdata(0,'sixgrRegressionHarnessProbeExecuted',true);
switch mode
    case 'fail'
        verifyTrue(testCase,false,'Intentional harness negative-case failure.');
    case 'incomplete'
        assumeTrue(testCase,false,'Intentional harness incomplete-case check.');
end
end
