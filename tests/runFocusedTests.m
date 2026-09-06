function report = runFocusedTests(names, varargin)
%RUNFOCUSEDTESTS Execute a named subset without constructing the full suite.

p = inputParser;
p.addParameter("ShowSlowest", 10, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.parse(varargin{:});
showSlowest = double(p.Results.ShowSlowest);

names = string(names);
names = strtrim(names(:));
names = names(strlength(names) > 0);
missing = strings(0, 1);
tests = cell(numel(names), 1);
for i = 1:numel(names)
    name = char(names(i));
    if exist(name, "file") ~= 2 && exist(name, "builtin") ~= 5
        missing(end + 1, 1) = string(name); %#ok<AGROW>
        continue;
    end
    tests{i} = str2func(name);
end
assert(isempty(missing), "Unknown tests requested: %s", strjoin(missing, ", "));

report = struct();
report.ok = true;
report.results = struct([]);
report.selected_tests = cellstr(names);
report.total_duration_s = NaN;

suiteStart = tic;
for k = 1:numel(tests)
    fn = tests{k};
    name = func2str(fn);
    r = struct("name", name, "ok", false, "msg", "", "duration_s", NaN);
    testStart = tic;
    try
        executeRegressionTest(fn);
        r.ok = true;
    catch ME
        r.ok = false;
        r.msg = ME.message;
        report.ok = false;
    end
    r.duration_s = toc(testStart);
    report.results = [report.results; r]; %#ok<AGROW>
    fprintf("[%s] %s (%.2fs)\n", localTernary(r.ok, "PASS", "FAIL"), name, r.duration_s);
    if ~r.ok
        fprintf("       %s\n", r.msg);
    end
    drawnow;
end
report.total_duration_s = toc(suiteStart);
localPrintSlowest(report.results, showSlowest);
if nargout == 0 && ~report.ok
    error('sixgr:tests:RegressionFailed', 'One or more focused regressions failed; see per-test diagnostics.');
end
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end

function localPrintSlowest(results, showSlowest)
if isempty(results) || showSlowest <= 0
    return;
end
durations = [results.duration_s];
[sortedDurations, order] = sort(durations, 'descend');
n = min(numel(order), showSlowest);
fprintf("Slowest %d test(s):\n", n);
for i = 1:n
    idx = order(i);
    fprintf("  %2d. %s (%.2fs)\n", i, results(idx).name, sortedDurations(i));
end
end
