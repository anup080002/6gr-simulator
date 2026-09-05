function ok = testRequiredPHYProfilerCoverage()
%TESTREQUIREDPHYPROFILERCOVERAGE Required RX stages emit measured scopes.

setup6GRSimToolkit("Verbose", false);
cfg = struct();
cfg.perf = struct( ...
    "timeProfilingEnabled", true, ...
    "requiredFunctionStages", [ ...
        "sixgr.phy.dl.PDSCH_Rx"; ...
        "sixgr.phy.rx.mimoDetect"]);
sixgr.perf.TimeProfiler.configure(cfg);
cleanup = onCleanup(@()sixgr.perf.TimeProfiler.configure(struct())); %#ok<NASGU>

% Exercise the production PDSCH TX/RX chain rather than inserting a
% profiler-only marker or synthetic record.
assert(testPDSCHSISORegression(), ...
    "The profiled production PDSCH round trip must pass.");

% Exercise the production MIMO detector with a non-trivial 2x2 channel.
H = zeros(4, 2, 2);
H(:, 1, 1) = 1;
H(:, 2, 2) = 0.8;
H(:, 1, 2) = 0.15;
H(:, 2, 1) = -0.1i;
x = [1+1i, -1+1i; -1-1i, 1-1i; 1-1i, 1+1i; -1+1i, -1-1i] ./ sqrt(2);
y = zeros(4, 2);
for k = 1:4
    y(k, :) = (squeeze(H(k, :, :)) * x(k, :).').';
end
sixgr.phy.rx.mimoDetect(y, H, 1e-3, "Algorithm", "MMSE");

[calls, ~, coverage] = sixgr.perf.TimeProfiler.snapshot();
for functionName = cfg.perf.requiredFunctionStages.'
    row = coverage(string(coverage.FunctionName) == functionName, :);
    assert(height(row) == 1, "Missing profiler coverage row for %s.", functionName);
    assert(string(row.CoverageStatus(1)) == "executed", ...
        "Required profiler stage %s was not executed.", functionName);
    assert(double(row.ExecutedCallCount(1)) >= 1, ...
        "Required profiler stage %s has no measured call.", functionName);
    callRows = calls(string(calls.FunctionName) == functionName, :);
    assert(any(double(callRows.Elapsed_s) >= 0), ...
        "Required profiler stage %s has no measured elapsed time.", functionName);
end

fprintf("RequiredPHYProfilerCoverage: PDSCH RX and MIMO detector scopes verified.\n");
ok = true;
end
