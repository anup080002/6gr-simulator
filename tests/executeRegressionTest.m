function executeRegressionTest(fn)
%EXECUTEREGRESSIONTEST Execute assertions, not merely construct a TestSuite.
if nargout(fn) == 0
    feval(fn);
    return;
end
outcome = feval(fn);
if isa(outcome,'matlab.unittest.TestSuite')
    assert(~isempty(outcome),'sixgr:tests:EmptySuite', ...
        'Test %s returned an empty suite.',func2str(fn));
    outcome = run(outcome);
end
if isa(outcome,'matlab.unittest.TestResult')
    assert(~isempty(outcome) && all([outcome.Passed]), ...
        'sixgr:tests:UnsuccessfulTestResults', ...
        'Test %s contains failed or incomplete tests.',func2str(fn));
elseif islogical(outcome) || isnumeric(outcome)
    assert(isscalar(outcome) && isequal(double(outcome),1), ...
        'sixgr:tests:UnsuccessfulReturn', ...
        'Test %s did not return scalar success.',func2str(fn));
elseif isstruct(outcome) && isscalar(outcome) && isfield(outcome,'ok')
    assert(isequal(outcome.ok,true), 'sixgr:tests:UnsuccessfulReturn', ...
        'Test %s returned a failed report.',func2str(fn));
else
    error('sixgr:tests:UnsupportedReturn', ...
        'Test %s returned unsupported result type %s.',func2str(fn),class(outcome));
end
end
